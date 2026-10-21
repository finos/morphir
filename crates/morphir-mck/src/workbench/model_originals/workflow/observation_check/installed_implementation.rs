//! Factual implementation relationships, after old predicates and before Blocked.
use super::super::super::installed_measurements::implementation::*;
use super::*;
fn need(owner: &mut CompareOwner, value: bool, fault: Fault) -> Result<()> {
    require_value(owner, value, fault)
}
fn bytes(owner: &mut CompareOwner, length: usize) -> Result<()> {
    owner.charge(CompareResource::ComparisonBytes, length)
}
fn same(a: &OsOperand, b: &OsOperand, owner: &mut CompareOwner) -> Result<bool> {
    match (a, b) {
        (OsOperand::UnixBytes { bytes: a }, OsOperand::UnixBytes { bytes: b }) => {
            bytes(owner, a.bytes().len().saturating_add(b.bytes().len()))?;
            Ok(a.bytes() == b.bytes())
        }
        (OsOperand::WindowsWide { units: a }, OsOperand::WindowsWide { units: b }) => {
            bytes(owner, a.0.len().saturating_add(b.0.len()).saturating_mul(2))?;
            Ok(a.0.iter().map(|n| n.0).eq(b.0.iter().map(|n| n.0)))
        }
        _ => Ok(false),
    }
}
fn word(a: &OsOperand, text: &str, owner: &mut CompareOwner) -> Result<bool> {
    bytes(owner, text.len())?;
    match a {
        OsOperand::UnixBytes { bytes: a } => {
            bytes(owner, a.bytes().len())?;
            Ok(a.bytes() == text.as_bytes())
        }
        OsOperand::WindowsWide { units } => {
            bytes(owner, units.0.len().saturating_mul(2))?;
            Ok(units
                .0
                .iter()
                .map(|n| n.0)
                .eq(text.encode_utf16().map(u64::from)))
        }
    }
}
fn joined(a: &OsOperand, root: &OsOperand, member: &str, owner: &mut CompareOwner) -> Result<bool> {
    bytes(owner, member.len())?;
    match (a, root) {
        (OsOperand::UnixBytes { bytes: a }, OsOperand::UnixBytes { bytes: r }) => {
            let r = r.bytes();
            bytes(owner, a.bytes().len().saturating_add(r.len()))?;
            let separator = if r.ends_with(b"/") {
                &b""[..]
            } else {
                &b"/"[..]
            };
            Ok(a.bytes().iter().copied().eq(r
                .iter()
                .chain(separator)
                .chain(member.as_bytes())
                .copied()))
        }
        (OsOperand::WindowsWide { units: a }, OsOperand::WindowsWide { units: r }) => {
            bytes(owner, a.0.len().saturating_add(r.0.len()).saturating_mul(2))?;
            let sep = if r.0.last().is_some_and(|n| matches!(n.0, 47 | 92)) {
                None
            } else {
                Some(92)
            };
            Ok(a.0.iter().map(|n| n.0).eq(r
                .0
                .iter()
                .map(|n| n.0)
                .chain(sep)
                .chain(member.encode_utf16().map(u64::from))))
        }
        _ => Ok(false),
    }
}
fn absolute(a: &OsOperand) -> bool {
    match a {
        OsOperand::UnixBytes { bytes } => bytes.bytes().starts_with(b"/"),
        OsOperand::WindowsWide { units } => {
            let u = &units.0;
            let sep = |v: u64| matches!(v, 47 | 92);
            if u.len() >= 2 && sep(u[0].0) && sep(u[1].0) {
                // Rust's non-Disk prefix kinds have an implicit root. Verbatim
                // requires literal backslashes; DeviceNS accepts normal separators.
                if u.len() >= 4
                    && ((u[0].0 == 92 && u[1].0 == 92 && u[2].0 == 63 && u[3].0 == 92)
                        || (u[2].0 == 46 && sep(u[3].0)))
                {
                    return true;
                }
                let rest = &u[2..];
                let Some(server) = rest.iter().position(|n| sep(n.0)) else {
                    return false;
                };
                server > 0 && rest.get(server + 1).is_some_and(|n| !sep(n.0))
            } else {
                u.len() >= 3 && matches!(u[0].0,65..=90|97..=122) && u[1].0 == 58 && sep(u[2].0)
            }
        }
    }
}
fn checked_absolute(a: &OsOperand, owner: &mut CompareOwner) -> Result<bool> {
    let length = match a {
        OsOperand::UnixBytes { bytes } => bytes.bytes().len(),
        OsOperand::WindowsWide { units } => units.0.len().saturating_mul(2),
    };
    bytes(owner, length)?;
    Ok(absolute(a))
}
fn confined(a: &OsOperand, owner: &mut CompareOwner) -> Result<bool> {
    fn component(values: impl Iterator<Item = u64>) -> bool {
        let mut n = 0;
        let mut dots = true;
        for value in values {
            n += 1;
            dots &= value == 46;
            if value == 0 {
                return false;
            }
        }
        n > 0 && !(dots && n <= 2)
    }
    Ok(match a {
        OsOperand::UnixBytes { bytes: a } => {
            bytes(owner, a.bytes().len())?;
            !a.bytes().starts_with(b"/")
                && a.bytes()
                    .split(|b| *b == b'/')
                    .all(|p| component(p.iter().map(|b| u64::from(*b))))
        }
        OsOperand::WindowsWide { units } => {
            bytes(owner, units.0.len().saturating_mul(2))?;
            !absolute(a)
                && !units.0.iter().any(|v| v.0 == 58)
                && units
                    .0
                    .split(|v| matches!(v.0, 47 | 92))
                    .all(|p| component(p.iter().map(|v| v.0)))
        }
    })
}
fn resolves(
    directory: &OsOperand,
    relative: &OsOperand,
    target: &str,
    owner: &mut CompareOwner,
) -> Result<bool> {
    bytes(owner, target.len())?;
    Ok(match (directory, relative) {
        (OsOperand::UnixBytes { bytes: d }, OsOperand::UnixBytes { bytes: r }) => {
            let d = d.bytes();
            let r = r.bytes();
            bytes(owner, d.len().saturating_add(r.len()))?;
            let sep = if d.ends_with(b"/") { None } else { Some(b'/') };
            target
                .bytes()
                .eq(d.iter().copied().chain(sep).chain(r.iter().copied()))
        }
        (OsOperand::WindowsWide { units: d }, OsOperand::WindowsWide { units: r }) => {
            bytes(owner, d.0.len().saturating_add(r.0.len()).saturating_mul(2))?;
            let sep = if d.0.last().is_some_and(|n| matches!(n.0, 47 | 92)) {
                None
            } else {
                Some(92)
            };
            target.encode_utf16().map(u64::from).eq(d
                .0
                .iter()
                .map(|v| v.0)
                .chain(sep)
                .chain(r.0.iter().map(|v| v.0)))
        }
        _ => false,
    })
}
pub(super) fn published_matches(
    actual: &InstalledClientMeasurements,
    path: &str,
    owner: &mut CompareOwner,
) -> Result<bool> {
    let root = actual.wire.destination.root.as_str();
    let suffix = actual.wire.published_relative_root.as_str();
    bytes(
        owner,
        path.len()
            .saturating_add(root.len())
            .saturating_add(suffix.len()),
    )?;
    if path.strip_prefix(root).and_then(|p| p.strip_prefix('/')) == Some(suffix) {
        return Ok(true);
    }
    let ImplementationObservation::Observed { command_paths, .. } = &actual.wire.implementation
    else {
        return Ok(false);
    };
    match &command_paths.destination {
        OsOperand::UnixBytes { bytes: r } => {
            bytes(owner, r.bytes().len())?;
            Ok(path.bytes().eq(r
                .bytes()
                .iter()
                .copied()
                .chain(Some(b'/'))
                .chain(suffix.bytes())))
        }
        OsOperand::WindowsWide { units: r } => {
            bytes(owner, r.0.len().saturating_mul(2))?;
            Ok(path.encode_utf16().map(u64::from).eq(r
                .0
                .iter()
                .map(|v| v.0)
                .chain(Some(92))
                .chain(suffix.encode_utf16().map(u64::from))))
        }
    }
}
fn completion(value: &DirectProcessCompletion) -> bool {
    matches!(value,DirectProcessCompletion::Finished{exit:ProcessExit::Code{value}} if value.0==0)
}
fn census<'a>(
    entries: impl Iterator<Item = Descriptor<'a>>,
    owner: &mut CompareOwner,
) -> Result<[u8; 32]> {
    let mut hash = Sha256::new();
    let mut previous = None;
    for Descriptor {
        kind,
        mode,
        path,
        length,
        digest,
    } in entries
    {
        owner.visit()?;
        if let Some(prior) = previous {
            bytes(owner, path.len().saturating_add(str::len(prior)))?;
            need(
                owner,
                prior.as_bytes() < path.as_bytes(),
                Fault::ImplementationDigest,
            )?;
        }
        previous = Some(path);
        bytes(owner, path.len().saturating_add(50))?;
        hash.update([kind, mode]);
        hash.update((path.len() as u64).to_be_bytes());
        hash.update(path.as_bytes());
        hash.update(length.to_be_bytes());
        hash.update(digest);
    }
    Ok(hash.finalize().into())
}
fn package_has(package: &PackageCensus, path: &str, owner: &mut CompareOwner) -> Result<bool> {
    for entry in &package.entries.0 {
        owner.visit()?;
        if owner.same_text(entry.path.as_str(), path)? {
            return Ok(true);
        }
    }
    Ok(false)
}
fn query_arguments(query: &GitQuery) -> &'static [&'static str] {
    use super::super::super::installed_measurements::implementation as model;
    match query {
        GitQuery::Revision => model::REVISION,
        GitQuery::TrackedInventory => model::INVENTORY,
        GitQuery::TrackedStatus => model::STATUS,
    }
}

#[derive(Clone, Copy)]
enum ProcessScope<'a> {
    Complete(&'a InstalledClientMeasurements),
    Prefix(&'a ProcessMeasurement),
}
impl ProcessScope<'_> {
    fn processes(&self) -> &[ProcessMeasurement] {
        match self {
            Self::Complete(actual) => &actual.wire.processes.0,
            Self::Prefix(process) => std::slice::from_ref(*process),
        }
    }
}
pub(super) fn check(
    plan: &InstalledClientPlan<'_>,
    actual: &InstalledClientMeasurements,
    owner: &mut CompareOwner,
) -> Result<()> {
    check_association(
        plan,
        &actual.wire.implementation,
        ProcessScope::Complete(actual),
        owner,
    )
}
pub(super) fn check_prefix(
    plan: &InstalledClientPlan<'_>,
    implementation: &ImplementationObservation,
    process: &ProcessMeasurement,
    owner: &mut CompareOwner,
) -> Result<()> {
    check_association(plan, implementation, ProcessScope::Prefix(process), owner)
}
fn check_association(
    plan: &InstalledClientPlan<'_>,
    implementation: &ImplementationObservation,
    scope: ProcessScope<'_>,
    owner: &mut CompareOwner,
) -> Result<()> {
    owner.ready()?;
    let actual_processes = scope.processes();
    let ImplementationObservation::Observed {
        before_action,
        launch,
        runtime,
        command_paths: paths,
        package,
        source,
        metadata_tools: tools,
    } = implementation
    else {
        return owner.refuse(ObservationError::InstalledClient(
            Fault::ImplementationMissing,
        ));
    };
    need(owner, before_action.0 == 2, Fault::ImplementationBinding)?;
    for operand in [
        &runtime.program,
        &package.root,
        &source.root,
        &paths.launch_file,
        &paths.connection_file,
        &paths.source_selection_file,
        &paths.project_selection_file,
    ] {
        let yes = checked_absolute(operand, owner)?;
        need(owner, yes, Fault::ImplementationProcess)?;
    }
    let relative = confined(&paths.destination, owner)?;
    need(owner, relative, Fault::ImplementationProcess)?;
    let package_digest = census(package.entries.0.iter().map(PackageFile::descriptor), owner)?;
    need(
        owner,
        package_digest == package.sha256.0,
        Fault::ImplementationDigest,
    )?;
    let source_digest = census(source.entries.0.iter().map(SourceEntry::descriptor), owner)?;
    need(
        owner,
        source_digest == source.sha256.0,
        Fault::ImplementationDigest,
    )?;
    for entry in &source.entries.0 {
        owner.visit()?;
        if let SourceEntry::SymlinkLiteral {
            target_bytes,
            byte_length,
            sha256,
            ..
        } = entry
        {
            bytes(owner, target_bytes.bytes().len())?;
            let digest: [u8; 32] = Sha256::digest(target_bytes.bytes()).into();
            need(
                owner,
                target_bytes.bytes().len() as u64 == byte_length.0 && digest == sha256.0,
                Fault::ImplementationDigest,
            )?;
        }
    }
    for path in [
        "package.json",
        "build-provider/connected.mjs",
        "build-provider/originals.mjs",
    ] {
        let yes = package_has(package, path, owner)?;
        need(owner, yes, Fault::ImplementationBinding)?;
    }
    match launch {
        LaunchObservation::NodePackage { entry } => {
            let yes = joined(entry, &package.root, "bin/morphir.js", owner)?;
            need(owner, yes, Fault::ImplementationProcess)?;
            let yes = package_has(package, "bin/morphir.js", owner)?;
            need(owner, yes, Fault::ImplementationBinding)?;
        }
        LaunchObservation::NativeExecutable { program, .. } => {
            let yes = checked_absolute(program, owner)?;
            need(owner, yes, Fault::ImplementationProcess)?;
        }
    }
    need(
        owner,
        tools.0.len() == 3
            && match scope {
                ProcessScope::Complete(_) => actual_processes.len() == 3,
                ProcessScope::Prefix(process) => matches!(process.command, ProcessCommand::Publish),
            },
        Fault::ImplementationProcess,
    )?;
    for process in actual_processes {
        owner.visit()?;
        let yes = checked_absolute(&process.directory, owner)?;
        need(owner, yes, Fault::ImplementationProcess)?;
        let equal = same(&process.directory, &actual_processes[0].directory, owner)?;
        need(owner, equal, Fault::ImplementationProcess)?;
    }
    if let ProcessScope::Complete(actual) = scope {
        let bound = resolves(
            &actual_processes[0].directory,
            &paths.destination,
            actual.wire.destination.root.as_str(),
            owner,
        )?;
        need(owner, bound, Fault::ImplementationBinding)?;
    }
    for (index, tool) in tools.0.iter().enumerate() {
        owner.visit()?;
        let query = matches!(
            (index, &tool.query),
            (0, GitQuery::Revision)
                | (1, GitQuery::TrackedInventory)
                | (2, GitQuery::TrackedStatus)
        );
        let absolute_program = checked_absolute(&tool.program, owner)?;
        need(
            owner,
            tool.process_ordinal.0 == index as u64
                && query
                && completion(&tool.completion)
                && !tool.stderr_truncated.observed()
                && absolute_program,
            Fault::ImplementationProcess,
        )?;
        let same_program = same(&tool.program, &tools.0[0].program, owner)?;
        let directory = same(&tool.directory, &source.root, owner)?;
        need(
            owner,
            same_program && directory,
            Fault::ImplementationProcess,
        )?;
        let wanted = query_arguments(&tool.query);
        need(
            owner,
            tool.arguments.0.len() == wanted.len(),
            Fault::ImplementationProcess,
        )?;
        for (arg, wanted) in tool.arguments.0.iter().zip(wanted) {
            let yes = word(arg, wanted, owner)?;
            need(owner, yes, Fault::ImplementationProcess)?;
        }
    }
    for (index, process) in actual_processes.iter().enumerate() {
        owner.visit()?;
        let expected_ordinal = match scope {
            ProcessScope::Complete(_) => index as u64 + 3,
            ProcessScope::Prefix(_) => {
                let mut previous = 0u64;
                for (index, action) in plan.actions().enumerate() {
                    owner.visit()?;
                    if index as u64 >= process.action_index.0 {
                        break;
                    }
                    if matches!(action, Action::Run { .. }) {
                        previous += 1;
                    }
                }
                tools.0.len() as u64 + previous
            }
        };
        need(
            owner,
            process.process_ordinal.0 == expected_ordinal,
            Fault::ImplementationProcess,
        )?;
        let program = match launch {
            LaunchObservation::NodePackage { .. } => &runtime.program,
            LaunchObservation::NativeExecutable { program, .. } => program,
        };
        let yes = same(&process.program, program, owner)?;
        need(owner, yes, Fault::ImplementationProcess)?;
        let Some(Action::Run { command, arguments }) =
            plan.actions().nth(process.action_index.0 as usize)
        else {
            return owner.refuse(ObservationError::InstalledClient(
                Fault::ImplementationProcess,
            ));
        };
        let prefix = usize::from(matches!(launch, LaunchObservation::NodePackage { .. }));
        need(
            owner,
            process.arguments.0.len() == arguments.0.len() + prefix + 2,
            Fault::ImplementationProcess,
        )?;
        if let LaunchObservation::NodePackage { entry } = launch {
            let yes = same(&process.arguments.0[0], entry, owner)?;
            need(owner, yes, Fault::ImplementationProcess)?;
        }
        for (actual, wanted) in process.arguments.0[prefix..].iter().zip(&arguments.0) {
            owner.visit()?;
            let wanted = wanted.as_str();
            bytes(owner, wanted.len())?;
            let value = match wanted {
                "$launchFile" => Some(&paths.launch_file),
                "$connectionFile" => Some(&paths.connection_file),
                "$sourceSelectionFile" => Some(&paths.source_selection_file),
                "$projectSelectionFile" => Some(&paths.project_selection_file),
                "$destination" => Some(&paths.destination),
                "$verifiedNodeRuntime" => Some(&runtime.program),
                _ => None,
            };
            let yes = if let Some(value) = value {
                same(actual, value, owner)?
            } else {
                word(actual, wanted, owner)?
            };
            need(owner, yes, Fault::ImplementationProcess)?;
        }
        let (flag, helper) = match command {
            Command::Connect => ("--connected-helper", "build-provider/connected.mjs"),
            Command::List | Command::Publish => {
                ("--originals-helper", "build-provider/originals.mjs")
            }
        };
        let end = process.arguments.0.len();
        let yes = word(&process.arguments.0[end - 2], flag, owner)?
            && joined(&process.arguments.0[end - 1], &package.root, helper, owner)?;
        need(owner, yes, Fault::ImplementationProcess)?;
    }
    let raw = tools.0[0].stdout.bytes();
    bytes(owner, raw.len())?;
    let revision = std::str::from_utf8(raw).ok();
    let Some(revision) = revision else {
        return owner.refuse(ObservationError::InstalledClient(
            Fault::ImplementationBinding,
        ));
    };
    bytes(owner, revision.len())?;
    let mut lines = revision.split_terminator('\n');
    let root = lines.next();
    let format = lines.next();
    let head = lines.next();
    need(
        owner,
        lines.next().is_none() && revision.ends_with('\n'),
        Fault::ImplementationBinding,
    )?;
    let root_matches = match root {
        Some(root) => word(&source.root, root, owner)?,
        None => false,
    };
    let format_name = match source.object_format {
        ObjectFormat::Sha1 => "sha1",
        ObjectFormat::Sha256 => "sha256",
    };
    let head_matches = match head {
        Some(head) => owner.same_text(head, source.head.as_str())?,
        None => false,
    };
    bytes(owner, source.head.as_str().len())?;
    need(
        owner,
        root_matches
            && format == Some(format_name)
            && head_matches
            && source.head.as_str().len() == if format_name == "sha1" { 40 } else { 64 }
            && source
                .head
                .as_str()
                .bytes()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)),
        Fault::ImplementationBinding,
    )?;
    let inventory = tools.0[1].stdout.bytes();
    bytes(owner, inventory.len())?;
    let Some(inventory) = std::str::from_utf8(inventory).ok() else {
        return owner.refuse(ObservationError::InstalledClient(
            Fault::ImplementationBinding,
        ));
    };
    bytes(owner, inventory.len())?;
    need(
        owner,
        inventory.is_empty() || inventory.ends_with('\0'),
        Fault::ImplementationBinding,
    )?;
    let mut records = inventory.split_terminator('\0');
    for entry in &source.entries.0 {
        owner.visit()?;
        let Some(row) = records.next() else {
            return owner.refuse(ObservationError::InstalledClient(
                Fault::ImplementationBinding,
            ));
        };
        bytes(owner, row.len())?;
        let Some((metadata, path)) = row.split_once('\t') else {
            return owner.refuse(ObservationError::InstalledClient(
                Fault::ImplementationBinding,
            ));
        };
        bytes(owner, metadata.len())?;
        let mut fields = metadata.split(' ');
        let recorded_mode = fields.next();
        let blob = fields.next();
        let stage = fields.next();
        let Descriptor {
            kind,
            mode: m,
            path: wanted_path,
            ..
        } = entry.descriptor();
        let wanted_mode = if kind == 1 {
            "120000"
        } else if m == 1 {
            "100755"
        } else {
            "100644"
        };
        let yes = owner.same_text(path, wanted_path)?;
        need(
            owner,
            yes && recorded_mode == Some(wanted_mode)
                && stage == Some("0")
                && fields.next().is_none(),
            Fault::ImplementationBinding,
        )?;
        let blob_ok = if let Some(blob) = blob {
            bytes(owner, blob.len())?;
            blob.len() == source.head.as_str().len()
                && blob
                    .bytes()
                    .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
        } else {
            false
        };
        need(owner, blob_ok, Fault::ImplementationBinding)?;
    }
    need(
        owner,
        records.next().is_none(),
        Fault::ImplementationBinding,
    )?;
    let unchanged = tools.0[2].stdout.bytes().is_empty();
    need(
        owner,
        unchanged == matches!(source.tracked_status, TrackedStatus::Unchanged),
        Fault::ImplementationBinding,
    )?;
    Ok(())
}

#[cfg(test)]
#[path = "windows_absolute_tests.rs"]
mod windows_absolute_tests;
