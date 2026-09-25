//! The kit's cucumber steps: each step of a `.feature` kit case checks the report records of its
//! own fence.
//!
//! A step does not read its text for data. It finds its fence by position: the running
//! scenario's node path and outline row (morphir-bdd's `ScenarioRef`) and the step's source line,
//! in the step-to-fence map of the lowered kit ([`FeatureKit::fences`]). The first step of a case
//! runs the whole case through the engine's per-case code ([`run_case`]), exactly once, through
//! the [`KitRun`] component every scenario shares. Each step then checks only the records of its
//! own fence, one per path mode, so the records equal what the legacy engine writes for the same
//! kit and adapter.
//!
//! A step fails when one of its records is a `fail` or a `kit-error`. A `pass` or a `skipped`
//! record passes the step: a skip is not a failure in the kit, and its message goes to stdout. A
//! tree check (`Then the "<set>" tree reads back as the canonical form`) has no fence of its own:
//! it checks every tree file record of its set in the same case.

use std::collections::BTreeMap;
use std::fmt;
use std::path::Path;
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use cucumber::gherkin::Step;
use cucumber::{given, then};
use morphir_bdd::world::{MorphirWorld, ScenarioRef};
use morphir_gherkin::NodePath;

use crate::ir::run::{RunState, Testee, kit_error_records, run_case};
use crate::kit::gherkin::lower::FenceRef;
use crate::kit::gherkin::vocabulary::{KitStep, parse_step};
use crate::kit::load::FeatureKit;
use crate::kit::syntax::info_string::set_label;
use crate::kit::{KIT_PATH, Role};
use crate::report::{Outcome, Record};

/// Why a step fails when the lowered kit has no fence for it.
pub const NO_FENCE: &str = "no kit fence for this step; run morphir mck check";

/// A step's key in [`FeatureKit::fences`]: the scenario's node path (an outline row's Examples
/// block), the outline row, and the step's source line.
type FenceKey = (NodePath, Option<usize>, usize);

/// One kit run shared by every scenario: the kit, the adapter, and each case's records once
/// the case has run.
///
/// Give it to the suite with `Suite::with_component`. Every scenario gets a clone, and all the
/// clones share one [`KitRunState`].
#[derive(Clone)]
pub struct KitRun(pub Arc<Mutex<KitRunState>>);

/// The state behind a [`KitRun`].
pub struct KitRunState {
    /// The lowered `.feature` kit and its step-to-fence maps.
    pub kit: FeatureKit,
    /// The adapter's capabilities, and whether the conversation has ended.
    pub state: RunState,
    /// The adapter under test.
    pub testee: Box<dyn Testee + Send>,
    /// Milliseconds from any fixed origin, for the records' durations.
    pub clock: Box<dyn Fn() -> f64 + Send>,
    /// Records by case index, filled the first time any step of the case runs.
    pub records: BTreeMap<usize, Vec<Record>>,
}

impl KitRun {
    /// A run of `kit` against `testee`. It asks the testee for its capabilities first, as the
    /// legacy engine's run does, so the adapter sees the same requests in the same order.
    pub fn new(
        kit: FeatureKit,
        mut testee: Box<dyn Testee + Send>,
        clock: Box<dyn Fn() -> f64 + Send>,
    ) -> Self {
        let state = RunState::open(testee.as_mut());
        Self(Arc::new(Mutex::new(KitRunState {
            kit,
            state,
            testee,
            clock,
            records: BTreeMap::new(),
        })))
    }

    /// Locks the shared state. A step that panicked while it held the lock leaves the state as
    /// it was, so a poisoned lock is still usable.
    fn lock(&self) -> MutexGuard<'_, KitRunState> {
        self.0.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// The records of `case`, running the case first if it has not run.
    pub fn records_of(&self, case: usize) -> Vec<Record> {
        self.lock().records_of(case).to_vec()
    }

    /// Kit errors, then every case that ran, in kit order.
    pub fn report_records(&self) -> Vec<Record> {
        let state = self.lock();
        let mut records = kit_error_records(&state.kit.kit);
        records.extend(state.records.values().flatten().cloned());
        records
    }
}

impl fmt::Debug for KitRun {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        // `try_lock`: a panic message formatted while a step holds the lock must not deadlock.
        let Ok(state) = self.0.try_lock() else {
            return f.write_str("KitRun { .. }");
        };
        f.debug_struct("KitRun")
            .field("cases", &state.kit.kit.cases.len())
            .field("kit_errors", &state.kit.kit.errors.len())
            .field("cases_run", &state.records.len())
            .finish()
    }
}

impl KitRunState {
    /// The records of `case`, running it first if it has not run. A case index outside the kit
    /// has no records.
    fn records_of(&mut self, case: usize) -> &[Record] {
        let Self {
            kit,
            state,
            testee,
            clock,
            records,
        } = self;
        records.entry(case).or_insert_with(|| {
            kit.kit.cases.get(case).map_or_else(Vec::new, |kit_case| {
                run_case(&kit.kit, kit_case, state, testee.as_mut(), clock.as_ref())
            })
        })
    }

    /// The kit-wide case index of `fence`, whose `case` counts from the first case of `file`.
    /// `KitCase.file` may be the real path of a directory-sourced kit, so the file is matched by
    /// its name: every kit case file is at the top of the kit directory.
    fn kit_case(&self, file: &str, fence: FenceRef) -> Option<usize> {
        let name = file_name(file);
        let cases = &self.kit.kit.cases;
        let first = cases.iter().position(|c| file_name(&c.file) == name)?;
        let index = first + fence.case;
        cases
            .get(index)
            .is_some_and(|c| file_name(&c.file) == name)
            .then_some(index)
    }

    /// The records of the fence a data step gives: one per path mode.
    fn step_records(&mut self, file: &str, key: &FenceKey) -> Result<Vec<Record>, String> {
        let fence = self
            .kit
            .fences
            .get(file)
            .and_then(|fences| fences.get(key))
            .copied()
            .ok_or(NO_FENCE)?;
        let case = self.kit_case(file, fence).ok_or(NO_FENCE)?;
        Ok(self
            .records_of(case)
            .iter()
            .filter(|r| r.fence_index == fence.fence)
            .cloned()
            .collect())
    }

    /// The records of every tree file in `set` of the case that the scenario at `path` and `row`
    /// belongs to. The case is the one the scenario's data steps give fences to.
    fn tree_records(
        &mut self,
        file: &str,
        path: &NodePath,
        row: Option<usize>,
        set: &str,
    ) -> Result<Vec<Record>, String> {
        let fence = self
            .kit
            .fences
            .get(file)
            .and_then(|fences| {
                fences
                    .iter()
                    .filter(|((p, r, _), _)| p == path && *r == row)
                    .map(|(_, fence)| *fence)
                    .min_by_key(|fence| (fence.case, fence.fence))
            })
            .ok_or(NO_FENCE)?;
        let case = self.kit_case(file, fence).ok_or(NO_FENCE)?;
        let members: Vec<usize> = self.kit.kit.cases[case]
            .fences
            .iter()
            .filter(|f| f.info.role == Role::File && f.info.set() == set)
            .map(|f| f.index)
            .collect();
        if members.is_empty() {
            return Err(format!(
                "no tree file in set {} in this case",
                set_label(set)
            ));
        }
        Ok(self
            .records_of(case)
            .iter()
            .filter(|r| members.contains(&r.fence_index))
            .cloned()
            .collect())
    }
}

/// The last component of a path, or the whole text when it has none.
fn file_name(path: &str) -> &str {
    Path::new(path)
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or(path)
}

/// The shared run and the running scenario, or why a kit step cannot run.
fn located(world: &MorphirWorld) -> (KitRun, &ScenarioRef, String) {
    let kit_run = world
        .context
        .get::<KitRun>()
        .expect("no KitRun component: run the kit through a Suite `with_component(kit_run)`")
        .clone();
    let scenario = world
        .scenario
        .as_ref()
        .expect("no running scenario: run the kit through morphir_bdd::Suite");
    let name = scenario
        .document
        .path
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_default();
    (kit_run, scenario, format!("{KIT_PATH}/{name}"))
}

/// Passes when no record is a `fail` or a `kit-error`, and prints each skip. Otherwise the error
/// lists each failing record as `<path>: <message>`.
fn judge(records: &[Record]) -> Result<(), String> {
    let mut failures = Vec::new();
    for record in records {
        let message = record.message.as_deref().unwrap_or(record.result.as_str());
        match record.result {
            Outcome::Pass => {}
            Outcome::Skipped => println!("skipped: {message}"),
            Outcome::Fail | Outcome::KitError => {
                let path = record.path.map_or("-", |path| path.as_str());
                failures.push(format!("{path}: {message}"));
            }
        }
    }
    if failures.is_empty() {
        Ok(())
    } else {
        Err(failures.join("\n"))
    }
}

/// Runs a data step: finds its fence and judges that fence's records.
fn check_fence(world: &mut MorphirWorld, step: &Step) {
    let (kit_run, scenario, file) = located(world);
    let key = (scenario.path.clone(), scenario.row, step.position.line);
    let outcome = kit_run
        .lock()
        .step_records(&file, &key)
        .and_then(|records| judge(&records));
    if let Err(message) = outcome {
        panic!("{message}");
    }
}

/// Runs a tree check: judges the records of every tree file of its set in the same case.
fn check_tree(world: &mut MorphirWorld, step: &Step) {
    let set = match parse_step(&step.value, None) {
        Some(Ok(KitStep::TreeCheck { set })) => set.unwrap_or_default(),
        _ => panic!("not a tree check step: {}", step.value),
    };
    let (kit_run, scenario, file) = located(world);
    let outcome = kit_run
        .lock()
        .tree_records(&file, &scenario.path, scenario.row, &set)
        .and_then(|records| judge(&records));
    if let Err(message) = outcome {
        panic!("{message}");
    }
}

// One step per matcher of the vocabulary (`kit::gherkin::vocabulary`), except that one step
// matches all three `accepts <…>` forms (inline, inline with a warning, and a doc string with a
// warning). The `regex` crate has no lookahead to keep the plain inline matcher off the two
// warning forms, and cucumber-rs refuses a step that two matchers match. The groups do not
// capture: a step finds its fence by position, not by its text.

/// `Given the tree file "<path>":`, with `in set "<set>"` and the `read-only` forms.
#[given(regex = r#"^the (?:read-only )?tree file "[^"]+"(?: in set "[^"]+")?:$"#)]
fn tree_file(world: &mut MorphirWorld, step: &Step) {
    check_fence(world, step);
}

/// `Then its canonical <format> spelling is:` with a doc string.
#[then(regex = r"^its canonical (?:YAML|JSON|text) spelling is:$")]
fn canonical_doc(world: &mut MorphirWorld, step: &Step) {
    check_fence(world, step);
}

/// `Then its canonical <format> spelling is <spelling>`.
#[then(regex = r"^its canonical (?:YAML|JSON|text) spelling is .+$")]
fn canonical_inline(world: &mut MorphirWorld, step: &Step) {
    check_fence(world, step);
}

/// `Then a reader of <format> accepts:` with a doc string.
#[then(regex = r"^a reader of (?:YAML|JSON|text) accepts:$")]
fn accepted_doc(world: &mut MorphirWorld, step: &Step) {
    check_fence(world, step);
}

/// `Then a reader of <format> accepts <input>`, `…accepts <input> with warning <code>`, and
/// `…accepts with warning <code>:` with a doc string.
#[then(regex = r"^a reader of (?:YAML|JSON|text) accepts .+$")]
fn accepted(world: &mut MorphirWorld, step: &Step) {
    check_fence(world, step);
}

/// `Then a reader of <format> rejects with <diagnostic>:` with a doc string.
#[then(regex = r"^a reader of (?:YAML|JSON|text) rejects with \S+:$")]
fn rejected_doc(world: &mut MorphirWorld, step: &Step) {
    check_fence(world, step);
}

/// `Then a reader of <format> rejects <input> with <diagnostic>`.
#[then(regex = r"^a reader of (?:YAML|JSON|text) rejects .+ with \S+$")]
fn rejected_inline(world: &mut MorphirWorld, step: &Step) {
    check_fence(world, step);
}

/// `Then a reader of <format> reads as a <Node>:` with a doc string.
#[then(regex = r"^a reader of (?:YAML|JSON|text) reads as an? \S+:$")]
fn reads_as_doc(world: &mut MorphirWorld, step: &Step) {
    check_fence(world, step);
}

/// `Then a reader of <format> reads <input> as a <Node>`.
#[then(regex = r"^a reader of (?:YAML|JSON|text) reads .+ as an? \S+$")]
fn reads_as_inline(world: &mut MorphirWorld, step: &Step) {
    check_fence(world, step);
}

/// `Then the "<set>" tree reads back as the canonical form`.
#[then(regex = r#"^the "[^"]+" tree reads back as the canonical form$"#)]
fn tree_check_set(world: &mut MorphirWorld, step: &Step) {
    check_tree(world, step);
}

/// `Then the tree reads back as the canonical form`, for the unnamed set.
#[then(regex = r"^the tree reads back as the canonical form$")]
fn tree_check(world: &mut MorphirWorld, step: &Step) {
    check_tree(world, step);
}

/// Keeps this crate's steps in a binary that links it.
///
/// cucumber-rs collects steps through link-time registration, so the linker keeps a library's
/// steps only if the binary uses something from the same object. Call this from the `main` of
/// every binary that runs the kit through a `Suite`.
pub fn link() {
    std::hint::black_box(check_fence as fn(&mut MorphirWorld, &Step));
    std::hint::black_box(check_tree as fn(&mut MorphirWorld, &Step));
    std::hint::black_box(tree_file as fn(&mut MorphirWorld, &Step));
    std::hint::black_box(canonical_doc as fn(&mut MorphirWorld, &Step));
}

#[cfg(test)]
mod tests {
    use std::borrow::Cow;

    use morphir_gherkin::Segment;
    use serde_json::{Map, Value};

    use super::*;
    use crate::kit::KitSource;
    use crate::kit::load::load_feature_kit;
    use crate::report::{Millis, RecordProfile, Role as RecordRole};
    use crate::transport::protocol::{PathMode, Request};

    /// An adapter that is never asked anything: the tests fill the records by hand.
    struct Silent;

    impl Testee for Silent {
        fn exchange(&mut self, request: &Request) -> Result<Map<String, Value>, String> {
            panic!("the silent adapter was asked {request:?}")
        }
    }

    const TREE: &str = r#"Feature: Document tree
  Scenario: document-tree-0001 A tree
    Then its canonical YAML spelling is:
      """yaml
      a: 1
      """
    Given the tree file "manifest" in set "s":
      """yaml
      a: 1
      """
    And the tree file "pkg/module" in set "s":
      """yaml
      b: 2
      """
    Then the "s" tree reads back as the canonical form
"#;

    const NAMES: &str = r#"Feature: Names
  Scenario: names-0001 A name
    Then its canonical JSON spelling is "a"

  Scenario: names-0002 Another name
    Then its canonical JSON spelling is "b"
"#;

    /// A kit state over `files`, with no case run and an adapter that must not be asked.
    fn state_of(files: &[(&str, &str)]) -> KitRunState {
        let files = files
            .iter()
            .map(|(p, t)| ((*p).to_owned(), Cow::Owned(t.as_bytes().to_vec())))
            .collect();
        let kit = load_feature_kit(KitSource::map("test kit", files)).unwrap();
        assert!(kit.kit.errors.is_empty(), "{:?}", kit.kit.errors);
        KitRunState {
            kit,
            state: RunState {
                caps: None,
                dead: None,
            },
            testee: Box::new(Silent),
            clock: Box::new(|| 0.0),
            records: BTreeMap::new(),
        }
    }

    fn record(case_id: &str, fence_index: usize, result: Outcome, message: &str) -> Record {
        Record {
            case_id: case_id.to_owned(),
            ir_version: 4,
            profile: RecordProfile::Yaml,
            role: RecordRole::Canonical,
            fence_index,
            path: Some(PathMode::Current),
            result,
            expected_diagnostic: None,
            observed_diagnostic: None,
            message: Some(message.to_owned()),
            duration_ms: Millis(0.0),
        }
    }

    fn scenario(i: usize) -> NodePath {
        NodePath::feature().push(Segment::Scenario(i))
    }

    #[test]
    fn a_session_can_be_a_kit_run_testee() {
        fn send<T: Send>() {}
        send::<crate::transport::Session>();
    }

    #[test]
    fn a_fence_in_a_later_file_counts_from_that_file_s_first_case() {
        let mut state = state_of(&[
            ("spec/ir/mck/document-tree.feature", TREE),
            ("spec/ir/mck/names.feature", NAMES),
        ]);
        let names: Vec<_> = (0..4).map(|i| format!("case {i}")).collect();
        for (i, name) in names.iter().enumerate() {
            state
                .records
                .insert(i, vec![record(name, 0, Outcome::Pass, name)]);
        }
        let got = state
            .step_records("spec/ir/mck/names.feature", &(scenario(1), None, 6))
            .unwrap();
        assert_eq!(got, vec![record("case 2", 0, Outcome::Pass, "case 2")]);
    }

    #[test]
    fn a_step_with_no_fence_fails_with_the_check_hint() {
        let mut state = state_of(&[("spec/ir/mck/names.feature", NAMES)]);
        assert_eq!(
            state.step_records("spec/ir/mck/names.feature", &(scenario(0), None, 99)),
            Err(NO_FENCE.to_owned())
        );
        assert_eq!(
            state.step_records("spec/ir/mck/types.feature", &(scenario(0), None, 3)),
            Err(NO_FENCE.to_owned())
        );
    }

    #[test]
    fn a_tree_check_takes_every_file_record_of_its_set() {
        let mut state = state_of(&[("spec/ir/mck/document-tree.feature", TREE)]);
        let records: Vec<_> = (0..3)
            .map(|i| record("document-tree-0001", i, Outcome::Pass, "ok"))
            .collect();
        state.records.insert(0, records.clone());
        let file = "spec/ir/mck/document-tree.feature";
        assert_eq!(
            state.tree_records(file, &scenario(0), None, "s"),
            Ok(records[1..].to_vec())
        );
        assert_eq!(
            state.tree_records(file, &scenario(0), None, ""),
            Err("no tree file in set (unnamed) in this case".to_owned())
        );
        assert_eq!(
            state.tree_records(file, &scenario(1), None, "s"),
            Err(NO_FENCE.to_owned())
        );
    }

    #[test]
    fn fail_and_kit_error_records_fail_a_step_and_skips_do_not() {
        assert_eq!(
            judge(&[
                record("c", 0, Outcome::Pass, "fine"),
                record("c", 0, Outcome::Skipped, "pending"),
            ]),
            Ok(())
        );
        let mut pinned = record("c", 0, Outcome::KitError, "adapter gone");
        pinned.path = Some(PathMode::Pinned);
        assert_eq!(
            judge(&[record("c", 0, Outcome::Fail, "line 1 differs"), pinned]),
            Err("current: line 1 differs\npinned: adapter gone".to_owned())
        );
    }

    #[test]
    fn report_records_put_kit_errors_first_then_cases_in_kit_order() {
        let state = state_of(&[("spec/ir/mck/names.feature", NAMES)]);
        let kit_run = KitRun(Arc::new(Mutex::new(state)));
        {
            let mut state = kit_run.lock();
            state
                .records
                .insert(1, vec![record("names-0002", 0, Outcome::Pass, "b")]);
            state
                .records
                .insert(0, vec![record("names-0001", 0, Outcome::Pass, "a")]);
        }
        let ids: Vec<_> = kit_run
            .report_records()
            .into_iter()
            .map(|r| r.case_id)
            .collect();
        assert_eq!(ids, ["names-0001", "names-0002"]);
        assert_eq!(
            format!("{kit_run:?}"),
            "KitRun { cases: 2, kit_errors: 0, cases_run: 2 }"
        );
    }
}
