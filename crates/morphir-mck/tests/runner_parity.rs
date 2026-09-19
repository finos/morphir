//! Parity with the first driver (`spec/mck/migration.md`, "Parity method").
//!
//! The Rust runner runs the kit against a replay of a frozen protocol
//! transcript, once per adapter the first driver was recorded against. The
//! replay refuses any request that is not byte for byte the one the old driver
//! sent at that point, so the runner must ask the same questions in the same
//! order. The report it writes must then equal that adapter's frozen report in
//! every member but the durations, with the header's timestamp and versions
//! taken from it.
//!
//! The two adapters exercise different answers: the TypeScript binding skips
//! the version 3 cases it does not support, and the Rust binding runs them.

use std::path::{Path, PathBuf};

use morphir_mck::ir::{RunOptions, Testee, run_kit};
use morphir_mck::kit::{KitSource, load_kit};
use morphir_mck::transport::protocol::{Request, parse_envelope};
use serde_json::{Map, Value};

fn repo() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// Answers from a transcript, one exchange at a time.
struct Replay {
    exchanges: std::vec::IntoIter<(String, Option<String>)>,
    next_id: u64,
    answered: usize,
}

impl Replay {
    fn new(path: &Path) -> Self {
        const REQUEST: &str = "{\"dir\":\"request\",\"message\":";
        const RESPONSE: &str = "{\"dir\":\"response\",\"message\":";
        let text = std::fs::read_to_string(path).unwrap();
        let mut exchanges: Vec<(String, Option<String>)> = Vec::new();
        for line in text.lines().filter(|l| !l.is_empty()) {
            let raw = |prefix: &str| {
                line.strip_prefix(prefix)
                    .and_then(|r| r.strip_suffix('}'))
                    .map(str::to_owned)
            };
            if let Some(request) = raw(REQUEST) {
                exchanges.push((request, None));
            } else if let Some(response) = raw(RESPONSE) {
                exchanges.last_mut().unwrap().1 = Some(response);
            }
        }
        Self {
            exchanges: exchanges.into_iter(),
            next_id: 1,
            answered: 0,
        }
    }
}

impl Testee for Replay {
    fn exchange(&mut self, request: &Request) -> Result<Map<String, Value>, String> {
        let sent = request.line(self.next_id);
        self.next_id += 1;
        let (recorded, response) = self
            .exchanges
            .next()
            .ok_or("more requests than the transcript holds")?;
        if sent != recorded {
            return Err(format!(
                "request differs from the transcript:\n sent     {sent}\n recorded {recorded}"
            ));
        }
        let response = response.ok_or("the transcript has no answer here")?;
        self.answered += 1;
        let (_, body) = parse_envelope(&response).map_err(|e| e.0)?;
        Ok(body)
    }
}

fn without_durations(mut report: Value) -> Value {
    for record in report["records"].as_array_mut().unwrap() {
        record.as_object_mut().unwrap().remove("durationMs");
    }
    report
}

/// Replays `binding`'s transcript and holds the run to its frozen report.
fn parity(binding: &str, answered: usize, header: &str, summary: &str) {
    let baseline: Value = serde_json::from_str(
        std::fs::read_to_string(repo().join(format!("spec/mck/baseline/reports/{binding}.json")))
            .unwrap()
            .trim_start_matches('\u{FEFF}'),
    )
    .unwrap();
    let kit = load_kit(KitSource::directory(&repo().join("spec/ir/mck"), None)).unwrap();
    assert_eq!(kit.errors, vec![]);

    let mut replay =
        Replay::new(&repo().join(format!("spec/mck/baseline/transcripts/{binding}.ndjson")));
    let clock = || 0.0;
    let options = RunOptions {
        filter: None,
        driver_version: baseline["driverVersion"].as_str().unwrap().to_owned(),
        kit_version: baseline["kitVersion"].as_str().unwrap().to_owned(),
        started_at: baseline["startedAt"].as_str().unwrap().to_owned(),
        clock: &clock,
    };
    let run = run_kit(&kit, &mut replay, &options);
    assert_eq!(
        replay.answered, answered,
        "every recorded exchange but exit was asked for"
    );
    assert_eq!(
        run.header.as_deref(),
        Some(header),
        "the header line the first driver printed"
    );

    let produced: Value = serde_json::from_str(&run.report.to_json()).unwrap();
    let (produced, expected) = (without_durations(produced), without_durations(baseline));
    let (produced_records, expected_records) = (
        produced["records"].as_array().unwrap(),
        expected["records"].as_array().unwrap(),
    );
    assert_eq!(
        produced_records.len(),
        expected_records.len(),
        "record count"
    );
    for (i, (p, e)) in produced_records.iter().zip(expected_records).enumerate() {
        assert_eq!(p, e, "record {i} differs");
    }
    assert_eq!(produced, expected);
    assert_eq!(run.report.summary_line(), summary);
}

#[test]
fn the_rust_runner_reproduces_the_typescript_report_from_the_same_answers() {
    parity(
        "morphir-typescript",
        705,
        "morphir-typescript supports IR format versions [4.0.0,4.1.0) (4.0.0 up to but not including 4.1.0)",
        "722 pass, 0 fail, 0 kit-error, 8 skipped",
    );
}

/// The Rust binding supports version 3 as well, so it answers the 8 exchanges
/// the TypeScript binding declined and the run has no skips at all.
#[test]
fn the_rust_runner_reproduces_the_rust_bindings_report_from_the_same_answers() {
    parity(
        "morphir-rust",
        713,
        "morphir-rust supports IR format versions [3.0.0,3.1.0),[4.0.0,4.1.0) (3.0.0 up to but not including 3.1.0, or 4.0.0 up to but not including 4.1.0)",
        "730 pass, 0 fail, 0 kit-error, 0 skipped",
    );
}
