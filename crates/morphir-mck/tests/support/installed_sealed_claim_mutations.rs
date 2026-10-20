// TEST support shared by historical engine controls and fresh installed CLI tests.
// Pure saved-report mutations only. No production checker or measured DATA issuer.
use serde_json::{Value, json};

pub(super) const SOURCE: &str = "/records/0/evidence/measurement/host/source";
pub(super) const WORKERS: &str = "/records/0/evidence/measurement/host/workers";

#[derive(Clone, Copy)]
pub(super) enum Mutation {
    PrefixMismatch,
    PrefixOverflow,
    DuplicateRole,
    MissingRole,
    ForeignPath,
    SentinelAttempt,
    RecordMinimum,
    PrimaryMinimum,
    WitnessOverflow,
    SealedWithObservedWorkers,
    OwnedHandle,
    DroppedHandle,
    EmptyJoined,
    NormalJoinMismatch,
    PanicJoinMismatch,
    BodyMismatch,
    CancelMismatch,
    NormalOverflow,
    CancelOverflow,
    AllCancelled,
    AllReturnedError,
    OpenAllCancelled,
    OpenAllReturnedError,
    OpenSourceWithJoinedWorkers,
}
impl Mutation {
    pub(super) fn name(self) -> &'static str {
        match self {
            Self::PrefixMismatch => "s01-prefix-mismatch",
            Self::PrefixOverflow => "s02-prefix-overflow",
            Self::DuplicateRole => "s03a-duplicate-role",
            Self::MissingRole => "s03b-missing-role",
            Self::ForeignPath => "s03c-foreign-path",
            Self::SentinelAttempt => "s04-sentinel-attempt",
            Self::RecordMinimum => "s05a-record-minimum",
            Self::PrimaryMinimum => "s05b-primary-minimum",
            Self::WitnessOverflow => "s06-witness-overflow",
            Self::SealedWithObservedWorkers => "w01-sealed-observed-workers",
            Self::OwnedHandle => "w02a-owned-handle",
            Self::DroppedHandle => "w02b-dropped-handle",
            Self::EmptyJoined => "w03-empty-joined",
            Self::NormalJoinMismatch => "w04a-normal-join",
            Self::PanicJoinMismatch => "w04b-panic-join",
            Self::BodyMismatch => "w04c-body-start",
            Self::CancelMismatch => "w04d-start-cancel",
            Self::NormalOverflow => "w04e-normal-overflow",
            Self::CancelOverflow => "w04f-start-cancel-overflow",
            Self::AllCancelled => "w05a-all-cancelled",
            Self::AllReturnedError => "w05b-all-returned-error",
            Self::OpenAllCancelled => "w06a-open-source-all-cancelled",
            Self::OpenAllReturnedError => "w06b-open-source-all-returned-error",
            Self::OpenSourceWithJoinedWorkers => "c01-open-source-joined-workers",
        }
    }
    pub(super) fn expected(self) -> &'static str {
        match self {
            Self::PrefixMismatch | Self::PrefixOverflow => "InstalledClient(SourceCoverage)",
            Self::DuplicateRole
            | Self::MissingRole
            | Self::ForeignPath
            | Self::SentinelAttempt
            | Self::RecordMinimum
            | Self::PrimaryMinimum => "InstalledClient(SourceWitness)",
            Self::WitnessOverflow => "SizeOverflow",
            Self::OpenSourceWithJoinedWorkers => "ExpectedBlocked",
            _ => "InstalledClient(WorkerCoverage)",
        }
    }
}
pub(super) const MUTATIONS: [Mutation; 24] = [
    Mutation::PrefixMismatch,
    Mutation::PrefixOverflow,
    Mutation::DuplicateRole,
    Mutation::MissingRole,
    Mutation::ForeignPath,
    Mutation::SentinelAttempt,
    Mutation::RecordMinimum,
    Mutation::PrimaryMinimum,
    Mutation::WitnessOverflow,
    Mutation::SealedWithObservedWorkers,
    Mutation::OwnedHandle,
    Mutation::DroppedHandle,
    Mutation::EmptyJoined,
    Mutation::NormalJoinMismatch,
    Mutation::PanicJoinMismatch,
    Mutation::BodyMismatch,
    Mutation::CancelMismatch,
    Mutation::NormalOverflow,
    Mutation::CancelOverflow,
    Mutation::AllCancelled,
    Mutation::AllReturnedError,
    Mutation::OpenAllCancelled,
    Mutation::OpenAllReturnedError,
    Mutation::OpenSourceWithJoinedWorkers,
];
fn number(value: &Value) -> u64 {
    value.as_str().unwrap().parse().unwrap()
}
fn role_index(report: &Value, role: &str) -> usize {
    let files = report
        .pointer(&format!("{SOURCE}/files"))
        .unwrap()
        .as_array()
        .unwrap();
    let indices: Vec<_> = files
        .iter()
        .enumerate()
        .filter_map(|(index, value)| (value["role"] == role).then_some(index))
        .collect();
    assert_eq!(
        indices.len(),
        1,
        "actual compiled-role projection is unique"
    );
    indices[0]
}
pub(super) fn altered(base: &Value, mutation: Mutation) -> Value {
    let mut report = base.clone();
    let record = role_index(&report, "compile-record");
    let primary = role_index(&report, "original-primary");
    let sentinel = role_index(&report, "undeclared-sentinel");
    let mut edits: Vec<(String, Value, Value)> = Vec::new();
    {
        let mut set = |path: String, value: Value| {
            let old = report
                .pointer_mut(&path)
                .expect("existing actual report node");
            assert_ne!(*old, value, "mutation must change its intended node");
            edits.push((path, old.clone(), value.clone()));
            *old = value;
        };
        let file = |index, field| format!("{SOURCE}/files/{index}/counts/{field}");
        let worker = |field| format!("{WORKERS}/counts/{field}");
        match mutation {
            Mutation::PrefixMismatch => {
                let path = format!("{SOURCE}/counts/total/returnedBytes");
                set(
                    path.clone(),
                    json!(
                        number(base.pointer(&path).unwrap())
                            .checked_add(1)
                            .unwrap()
                            .to_string()
                    ),
                );
            }
            Mutation::PrefixOverflow => {
                set(
                    format!("{SOURCE}/counts/total/attempts"),
                    json!(u64::MAX.to_string()),
                );
                set(
                    format!("{SOURCE}/counts/workspace/attempts"),
                    json!(u64::MAX.to_string()),
                );
                set(format!("{SOURCE}/counts/ambient/attempts"), json!("1"));
            }
            Mutation::DuplicateRole => set(
                format!("{SOURCE}/files/{sentinel}/role"),
                json!("original-primary"),
            ),
            Mutation::MissingRole => {
                let path = format!("{SOURCE}/files");
                let mut files = base.pointer(&path).unwrap().as_array().unwrap().clone();
                files.remove(sentinel);
                set(path, Value::Array(files));
            }
            Mutation::ForeignPath => set(
                format!("{SOURCE}/files/{primary}/relativePath"),
                json!("foreign-primary.bin"),
            ),
            Mutation::SentinelAttempt => {
                set(file(sentinel, "attempts"), json!("1"));
                for class in ["total", "workspace"] {
                    let path = format!("{SOURCE}/counts/{class}/attempts");
                    set(
                        path.clone(),
                        json!(
                            number(base.pointer(&path).unwrap())
                                .checked_add(1)
                                .unwrap()
                                .to_string()
                        ),
                    );
                }
            }
            Mutation::RecordMinimum => set(file(record, "returnedBytes"), json!("0")),
            Mutation::PrimaryMinimum => set(file(primary, "returnedBytes"), json!("0")),
            Mutation::WitnessOverflow => {
                set(
                    format!("{SOURCE}/counts/total/attempts"),
                    json!(u64::MAX.to_string()),
                );
                set(
                    format!("{SOURCE}/counts/workspace/attempts"),
                    json!(u64::MAX.to_string()),
                );
                assert_eq!(
                    base.pointer(&format!("{SOURCE}/counts/ambient/attempts"))
                        .unwrap(),
                    "0"
                );
                set(file(record, "attempts"), json!(u64::MAX.to_string()));
                // Primary is the real positive one-attempt witness, sentinel zero.
                assert_eq!(base.pointer(&file(primary, "attempts")).unwrap(), "1");
                assert_eq!(base.pointer(&file(sentinel, "attempts")).unwrap(), "0");
            }
            Mutation::SealedWithObservedWorkers => {
                set(format!("{WORKERS}/kind"), json!("observed-prefix"))
            }
            Mutation::OwnedHandle => set(worker("ownedHandles"), json!("1")),
            Mutation::DroppedHandle => set(worker("droppedUnjoined"), json!("1")),
            Mutation::EmptyJoined => {
                // Replace only counters actually nonzero in the genuine base.
                for (key, value) in base
                    .pointer(&format!("{WORKERS}/counts"))
                    .unwrap()
                    .as_object()
                    .unwrap()
                {
                    if number(value) != 0 {
                        set(worker(key), json!("0"));
                    }
                }
            }
            Mutation::NormalJoinMismatch => {
                set(worker("returnedOk"), json!("2"));
                set(worker("started"), json!("2"));
                set(worker("scheduled"), json!("2"));
            }
            Mutation::PanicJoinMismatch => {
                set(worker("panicked"), json!("1"));
                set(worker("started"), json!("2"));
                set(worker("scheduled"), json!("2"));
            }
            Mutation::BodyMismatch => {
                set(worker("started"), json!("2"));
                set(worker("scheduled"), json!("2"));
            }
            Mutation::CancelMismatch => set(worker("scheduled"), json!("2")),
            Mutation::NormalOverflow => {
                for field in ["returnedOk", "joinedOk", "started", "scheduled"] {
                    set(worker(field), json!(u64::MAX.to_string()));
                }
                set(worker("returnedError"), json!("1"));
            }
            Mutation::CancelOverflow => {
                for field in ["returnedOk", "joinedOk", "started", "scheduled"] {
                    set(worker(field), json!(u64::MAX.to_string()));
                }
                set(worker("joinedCancelled"), json!("1"));
            }
            Mutation::AllCancelled => {
                // Native worker equations remain coherent, but this cannot
                // corroborate the already verified actual Ready/adopted record.
                for field in ["started", "returnedOk", "joinedOk"] {
                    set(worker(field), json!("0"));
                }
                set(worker("joinedCancelled"), json!("1"));
            }
            Mutation::AllReturnedError => {
                // Errors are normally joined by joinedOk. Preserve that math
                // while removing every successful body from this sealed capture.
                set(worker("returnedOk"), json!("0"));
                set(worker("returnedError"), json!("1"));
            }
            Mutation::OpenAllCancelled => return open_worker_failure(base, Mutation::AllCancelled),
            Mutation::OpenAllReturnedError => {
                return open_worker_failure(base, Mutation::AllReturnedError);
            }
            Mutation::OpenSourceWithJoinedWorkers => {
                let counts = base.pointer(&format!("{SOURCE}/counts")).unwrap().clone();
                set(SOURCE.into(), json!({"kind":"open-prefix","counts":counts}));
            }
        }
    }
    let mut restored = report.clone();
    for (path, old, new) in edits.iter().rev() {
        let actual = restored.pointer_mut(path).unwrap();
        assert_eq!(actual, new);
        *actual = old.clone();
    }
    assert_eq!(&restored, base, "all other semantic nodes remain identical");
    report
}

fn open_worker_failure(base: &Value, mutation: Mutation) -> Value {
    // Same composition as the independently authored two companion controls.
    // Reuse the worker mutation and valid weaker projection, never copy math.
    let coherent_failure = altered(base, mutation);
    let compatible_open = altered(base, Mutation::OpenSourceWithJoinedWorkers);
    let old_source = coherent_failure.pointer(SOURCE).unwrap().clone();
    let open_source = compatible_open.pointer(SOURCE).unwrap().clone();
    assert_eq!(open_source["kind"], "open-prefix");
    assert!(open_source.get("files").is_none());
    assert_eq!(open_source["counts"], old_source["counts"]);
    let mut report = coherent_failure.clone();
    *report.pointer_mut(SOURCE).unwrap() = open_source;
    assert_eq!(report.pointer(WORKERS).unwrap()["kind"], "joined-cleanup");
    let mut restored = report.clone();
    *restored.pointer_mut(SOURCE).unwrap() = old_source;
    assert_eq!(restored, coherent_failure);
    *restored.pointer_mut(WORKERS).unwrap() = base.pointer(WORKERS).unwrap().clone();
    assert_eq!(restored, *base, "all unrelated report nodes unchanged");
    report
}
