//! Inspect and clean disposable content beneath Morphir Home.

use crate::home::MorphirHome;
use morphir_common::cache_maintenance::{
    CacheEntry, CacheEntryState, CacheExecutionLimits, CacheExecutionReport, CacheInventoryLimits,
    CacheMaintenanceSession, CachePolicy, CleanupMode, CleanupPlan, plan_cache_cleanup,
};
use serde::Serialize;
use starbase::AppResult;
use std::collections::BTreeMap;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tracing::info;

const DEFAULT_MAX_AGE_SECONDS: u64 = 30 * 24 * 60 * 60;
const DEFAULT_MAX_SIZE_BYTES: u64 = 2 * 1024 * 1024 * 1024;
const MANUAL_MAX_REMOVALS: usize = 10_000;
const MANUAL_MAX_BYTES: u64 = 16 * 1024 * 1024 * 1024;
const CACHE_NAMESPACES: [&str; 4] = ["desktop", "downloads", "extensions", "indexes"];

#[derive(Debug)]
struct NamespaceInventory {
    name: String,
    entries: Vec<CacheEntry>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct CacheNamespaceStatus {
    name: String,
    entry_count: usize,
    disposable_entries: usize,
    leased_entries: usize,
    unclassified_entries: usize,
    known_bytes: u64,
    unclassified_bytes: u64,
}

impl CacheNamespaceStatus {
    fn from_inventory(inventory: &NamespaceInventory) -> miette::Result<Self> {
        let disposable_entries = inventory
            .entries
            .iter()
            .filter(|entry| matches!(entry.state(), CacheEntryState::Disposable { .. }))
            .count();
        let leased_entries = inventory
            .entries
            .iter()
            .filter(|entry| matches!(entry.state(), CacheEntryState::ActiveLease { .. }))
            .count();
        let unclassified_entries = inventory
            .entries
            .iter()
            .filter(|entry| matches!(entry.state(), CacheEntryState::Unclassified))
            .count();
        let known_bytes = inventory
            .entries
            .iter()
            .filter(|entry| !matches!(entry.state(), CacheEntryState::Unclassified))
            .try_fold(0_u64, |total, entry| total.checked_add(entry.bytes()))
            .ok_or_else(|| miette::miette!("Known cache byte count exceeds the supported range"))?;
        let unclassified_bytes = inventory
            .entries
            .iter()
            .filter(|entry| matches!(entry.state(), CacheEntryState::Unclassified))
            .try_fold(0_u64, |total, entry| total.checked_add(entry.bytes()))
            .ok_or_else(|| {
                miette::miette!("Unclassified cache byte count exceeds the supported range")
            })?;

        Ok(Self {
            name: inventory.name.clone(),
            entry_count: inventory.entries.len(),
            disposable_entries,
            leased_entries,
            unclassified_entries,
            known_bytes,
            unclassified_bytes,
        })
    }
}

#[derive(Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
struct CacheTotals {
    entry_count: usize,
    disposable_entries: usize,
    leased_entries: usize,
    unclassified_entries: usize,
    known_bytes: u64,
    unclassified_bytes: u64,
}

impl CacheTotals {
    fn add(&mut self, namespace: &CacheNamespaceStatus) -> miette::Result<()> {
        self.entry_count = self
            .entry_count
            .checked_add(namespace.entry_count)
            .ok_or_else(|| miette::miette!("Cache entry count exceeds the supported range"))?;
        self.disposable_entries = self
            .disposable_entries
            .checked_add(namespace.disposable_entries)
            .ok_or_else(|| {
                miette::miette!("Disposable cache entry count exceeds the supported range")
            })?;
        self.leased_entries = self
            .leased_entries
            .checked_add(namespace.leased_entries)
            .ok_or_else(|| {
                miette::miette!("Leased cache entry count exceeds the supported range")
            })?;
        self.unclassified_entries = self
            .unclassified_entries
            .checked_add(namespace.unclassified_entries)
            .ok_or_else(|| {
                miette::miette!("Unclassified cache entry count exceeds the supported range")
            })?;
        self.known_bytes = self
            .known_bytes
            .checked_add(namespace.known_bytes)
            .ok_or_else(|| miette::miette!("Known cache byte count exceeds the supported range"))?;
        self.unclassified_bytes = self
            .unclassified_bytes
            .checked_add(namespace.unclassified_bytes)
            .ok_or_else(|| {
                miette::miette!("Unclassified cache byte count exceeds the supported range")
            })?;
        Ok(())
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct CacheStatus {
    policy: CachePolicy,
    last_successful_automatic_run: Option<u64>,
    namespaces: Vec<CacheNamespaceStatus>,
    totals: CacheTotals,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct CacheCleanResult {
    dry_run: bool,
    plan: CleanupPlan,
    #[serde(skip_serializing_if = "Option::is_none")]
    execution: Option<CacheExecutionReport>,
}

/// Report cache usage beneath Morphir Home without changing it.
pub fn run_cache_status(json: bool) -> AppResult<miette::Report> {
    let home = MorphirHome::resolve()
        .map_err(|error| miette::miette!("Failed to resolve Morphir Home: {error}"))?;
    let status = cache_status(&home, &CACHE_NAMESPACES)?;

    info!(
        event = "cache_status_finished",
        namespace_count = status.namespaces.len(),
        known_bytes = status.totals.known_bytes,
        unclassified_bytes = status.totals.unclassified_bytes,
        "cache status finished"
    );
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(&status)
                .map_err(|error| miette::miette!("Failed to serialize cache status: {error}"))?
        );
    } else {
        print_cache_status(&status);
    }
    Ok(None)
}

/// Plan or execute bounded cleanup of known disposable cache entries.
pub fn run_cache_clean(
    dry_run: bool,
    all: bool,
    component: Option<String>,
    json: bool,
) -> AppResult<miette::Report> {
    let home = MorphirHome::resolve()
        .map_err(|error| miette::miette!("Failed to resolve Morphir Home: {error}"))?;
    let namespace_names = selected_cache_namespace_names(component.as_deref())?;
    let result = clean_cache(&home, &namespace_names, dry_run, all, unix_timestamp()?)?;

    info!(
        event = "cache_cleanup_planned",
        dry_run,
        remove_all = all,
        namespace_count = namespace_names.len(),
        selected_entries = result
            .plan
            .decisions()
            .iter()
            .filter(|decision| decision.will_remove())
            .count(),
        reclaimable_bytes = result.plan.reclaimable_bytes(),
        unclassified_bytes = result.plan.unclassified_bytes(),
        "cache cleanup planned"
    );
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(&result)
                .map_err(|error| miette::miette!("Failed to serialize cache cleanup: {error}"))?
        );
    } else {
        print_cache_clean_result(&result);
    }
    Ok(None)
}

fn default_policy() -> CachePolicy {
    CachePolicy::new(
        Duration::from_secs(DEFAULT_MAX_AGE_SECONDS),
        DEFAULT_MAX_SIZE_BYTES,
    )
}

fn unix_timestamp() -> miette::Result<u64> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .map_err(|error| miette::miette!("System clock is before the Unix epoch: {error}"))
}

fn selected_cache_namespace_names(component: Option<&str>) -> miette::Result<Vec<&'static str>> {
    match component {
        None => Ok(CACHE_NAMESPACES.to_vec()),
        Some(component) => {
            let selected = CACHE_NAMESPACES
                .iter()
                .copied()
                .find(|name| *name == component)
                .ok_or_else(|| {
                    miette::miette!(
                        "Unknown cache component {component}. Available components: {}",
                        CACHE_NAMESPACES.join(", ")
                    )
                })?;
            Ok(vec![selected])
        }
    }
}

fn inventory_namespaces(
    session: &mut CacheMaintenanceSession<'_>,
    namespace_names: &[&str],
) -> miette::Result<Vec<NamespaceInventory>> {
    let entries = session
        .inventory(namespace_names, CacheInventoryLimits::default())
        .map_err(|error| miette::miette!("Failed to inventory Morphir caches: {error}"))?;
    let mut grouped = namespace_names
        .iter()
        .map(|name| ((*name).to_owned(), Vec::new()))
        .collect::<BTreeMap<_, _>>();
    for entry in entries {
        grouped
            .get_mut(entry.namespace())
            .expect("session inventory returns only requested namespaces")
            .push(entry);
    }
    Ok(namespace_names
        .iter()
        .map(|name| NamespaceInventory {
            name: (*name).to_owned(),
            entries: grouped.remove(*name).unwrap_or_default(),
        })
        .collect())
}

fn cache_status(home: &MorphirHome, namespace_names: &[&str]) -> miette::Result<CacheStatus> {
    let mut session = CacheMaintenanceSession::begin(home)
        .map_err(|error| miette::miette!("Failed to begin cache maintenance: {error}"))?;
    let namespaces = inventory_namespaces(&mut session, namespace_names)?
        .iter()
        .map(CacheNamespaceStatus::from_inventory)
        .collect::<miette::Result<Vec<_>>>()?;
    let mut totals = CacheTotals::default();
    for namespace in &namespaces {
        totals.add(namespace)?;
    }
    Ok(CacheStatus {
        policy: default_policy(),
        last_successful_automatic_run: None,
        namespaces,
        totals,
    })
}

fn clean_cache(
    home: &MorphirHome,
    namespace_names: &[&str],
    dry_run: bool,
    all: bool,
    now: u64,
) -> miette::Result<CacheCleanResult> {
    let mut session = CacheMaintenanceSession::begin(home)
        .map_err(|error| miette::miette!("Failed to begin cache maintenance: {error}"))?;
    let entries = inventory_namespaces(&mut session, namespace_names)?
        .into_iter()
        .flat_map(|namespace| namespace.entries)
        .collect();
    let mode = if all {
        CleanupMode::All
    } else {
        CleanupMode::Policy
    };
    let plan = plan_cache_cleanup(entries, default_policy(), now, mode)
        .map_err(|error| miette::miette!("Failed to plan cache cleanup: {error}"))?;
    let execution = if dry_run {
        None
    } else {
        Some(
            session
                .execute_cleanup(
                    &plan,
                    CacheInventoryLimits::default(),
                    CacheExecutionLimits::new(MANUAL_MAX_REMOVALS, MANUAL_MAX_BYTES).map_err(
                        |error| miette::miette!("Invalid cache cleanup limits: {error}"),
                    )?,
                )
                .map_err(|error| miette::miette!("Failed to execute cache cleanup: {error}"))?,
        )
    };
    Ok(CacheCleanResult {
        dry_run,
        plan,
        execution,
    })
}

fn print_cache_status(status: &CacheStatus) {
    println!(
        "Cache policy: max age {} seconds, max size {} bytes",
        status.policy.max_age_seconds(),
        status.policy.max_size_bytes()
    );
    for namespace in &status.namespaces {
        println!(
            "{}: {} entries, {} known bytes, {} unclassified bytes",
            namespace.name,
            namespace.entry_count,
            namespace.known_bytes,
            namespace.unclassified_bytes
        );
    }
    println!(
        "Total: {} entries, {} known bytes, {} unclassified bytes",
        status.totals.entry_count, status.totals.known_bytes, status.totals.unclassified_bytes
    );
}

fn print_cache_clean_result(result: &CacheCleanResult) {
    let selected = result
        .plan
        .decisions()
        .iter()
        .filter(|decision| decision.will_remove())
        .count();
    if result.dry_run {
        println!(
            "Dry run: {selected} entries selected, {} bytes reclaimable",
            result.plan.reclaimable_bytes()
        );
    } else if let Some(execution) = &result.execution {
        println!(
            "Cache cleanup: {} entries evaluated, {} bytes reclaimed",
            execution.items().len(),
            execution.removed_bytes()
        );
    }
    println!(
        "Protected unclassified content: {} bytes",
        result.plan.unclassified_bytes()
    );
}

#[cfg(test)]
mod tests {
    use super::clean_cache;
    use morphir_common::cache_maintenance::{
        CacheExecutionDisposition, CacheOwnershipMutationGuard,
    };
    use morphir_common::home::MorphirHome;

    #[test]
    fn clean_executes_the_same_plan_that_dry_run_reports() {
        let directory = tempfile::TempDir::new().unwrap();
        let home = MorphirHome::resolve_from(Some(directory.path().as_os_str()), None).unwrap();
        let artifact = home.downloads_cache_dir().join("desktop.pkg");
        std::fs::create_dir_all(artifact.parent().unwrap()).unwrap();
        let mutation =
            CacheOwnershipMutationGuard::begin(&home, "downloads", "desktop.pkg").unwrap();
        std::fs::write(&artifact, b"owned").unwrap();
        mutation.finish(1).unwrap();

        let dry_run = clean_cache(&home, &["downloads"], true, true, 2).unwrap();
        assert_eq!(dry_run.plan.reclaimable_bytes(), 5);
        assert!(dry_run.execution.is_none());
        assert!(artifact.exists());

        let executed = clean_cache(&home, &["downloads"], false, true, 2).unwrap();
        assert_eq!(executed.plan, dry_run.plan);
        let report = executed.execution.unwrap();
        assert_eq!(report.removed_bytes(), 5);
        assert_eq!(
            report.items()[0].disposition(),
            CacheExecutionDisposition::Removed
        );
        assert!(!artifact.exists());
    }
}
