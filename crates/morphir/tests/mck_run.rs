//! `morphir mck run` end to end (`spec/mck/cli-contract.md`, "`run`").
//!
//! This binary is also the adapter: started as
//! `mck_run --mck-test-adapter replay <transcript>` it answers from the frozen
//! protocol transcript of the TypeScript adapter. It accepts the new v2
//! capabilities request and answers with the frozen v1 capabilities, then
//! refuses any request that is not byte for byte the one the first driver
//! sent. So the whole command
//! runs against real recorded answers with no other runtime installed.

use std::io::{BufRead, Write};
use std::path::{Path, PathBuf};
use std::process::Output;

use serde_json::Value;

#[path = "support/metadata_acceptance.rs"]
mod metadata_acceptance;
#[path = "support/mvp_acceptance.rs"]
mod mvp_acceptance;
#[path = "support/package_acceptance.rs"]
mod package_acceptance;

const ADAPTER_FLAG: &str = "--mck-test-adapter";

fn repo() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn transcript() -> PathBuf {
    repo().join("spec/mck/baseline/transcripts/morphir-typescript.ndjson")
}

fn the_legacy_engine_option_is_rejected_after_cutover() {
    let output = morphir(&[
        "mck",
        "run",
        "--engine",
        "legacy",
        "--adapter",
        "unused-adapter",
    ]);
    assert_eq!(output.status.code(), Some(2), "{}", stderr(&output));
    assert!(stderr(&output).contains("unexpected argument '--engine'"));
}

fn replay_adapter(path: &Path, exit_code: i32) {
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
    let mut exchanges = exchanges.into_iter();
    for line in std::io::stdin().lock().lines().map_while(Result::ok) {
        let Some((expected, response)) = exchanges.next() else {
            std::process::exit(2)
        };
        // The frozen v1 transcript stays untouched. Its capabilities answer
        // is valid for a v2 driver, and all following request ids still align.
        let versioned_first = expected == r#"{"id":1,"op":"capabilities"}"#
            && line == r#"{"id":1,"op":"capabilities","contractVersion":"2.0.0-draft.1"}"#;
        if line != expected && !versioned_first {
            eprint!("request differs from the transcript:\n sent     {line}\n recorded {expected}");
            std::process::exit(2);
        }
        match response {
            Some(response) => {
                let mut out = std::io::stdout().lock();
                writeln!(out, "{response}").unwrap();
                out.flush().unwrap();
            }
            None => std::process::exit(exit_code),
        }
    }
    std::process::exit(exit_code);
}

fn metadata_adapter(mode: &str) {
    let corpus: Value = serde_json::from_str(include_str!(
        "../../../spec/ir/mck/metadata-contract-draft.json"
    ))
    .unwrap();
    let case = if mode == "reordered-facts" {
        corpus["cases"]
            .as_array()
            .unwrap()
            .iter()
            .find(|case| case["id"] == "metadata-0004")
            .unwrap()
    } else {
        &corpus["cases"][0]
    };
    for line in std::io::stdin().lock().lines().map_while(Result::ok) {
        let request: Value = serde_json::from_str(&line).unwrap();
        let id = request["id"].clone();
        let reply = match request["op"].as_str() {
            Some("capabilities") if mode == "old" => serde_json::json!({
                "id":id,"contractVersion":1,"binding":"old","language":"rust",
                "formatVersions":"[4.0.0,4.1.0)","versions":[4],"profiles":["json"],
                "layouts":["single"],"paths":["current","pinned"],"nodes":["Type"]
            }),
            Some("capabilities") => serde_json::json!({
                "id":id,"suite":"metadata","contractVersion":"0.1.0-draft.1",
                "implementation":"fixture","implementationVersion":"1.0.0",
                "claims":[{"operation":"normalize","profile":"json","layout":"single","irRevision":"4.1.0"}]
            }),
            Some("run") if mode == "pass" && request["caseId"] == "metadata-0001" => {
                assert_eq!(request["given"], case["given"]);
                serde_json::json!({"id":id,"ok":true,"observation":case["expected"]})
            }
            Some("run") if mode == "reordered-facts" && request["caseId"] == "metadata-0004" => {
                let mut observed = case["expected"].clone();
                let value = observed["facts"][0]["object"]["@value"]
                    .as_object_mut()
                    .unwrap();
                let reordered = ["backend", "frontend"]
                    .into_iter()
                    .map(|key| (key.to_owned(), value.remove(key).unwrap()))
                    .collect();
                *value = reordered;
                let fact = observed["facts"][0].as_object_mut().unwrap();
                let reordered = ["graph", "object", "predicate", "subject"]
                    .into_iter()
                    .map(|key| (key.to_owned(), fact.remove(key).unwrap()))
                    .collect();
                *fact = reordered;
                serde_json::json!({"id":id,"ok":true,"observation":observed})
            }
            Some("exit") => return,
            other => panic!("unexpected metadata adapter request {other:?}"),
        };
        println!("{reply}");
        std::io::stdout().flush().unwrap();
    }
}

fn metadata_cli_accepts_reordered_fact_object_members() {
    let work = tempfile::tempdir().unwrap();
    let report = work.path().join("metadata-report.json");
    let adapter = std::env::current_exe().unwrap();
    let output = morphir(&[
        "mck",
        "run",
        "--suite",
        "metadata",
        "--adapter",
        adapter.to_str().unwrap(),
        "--adapter-arg",
        ADAPTER_FLAG,
        "--adapter-arg",
        "reordered-facts",
        "--filter",
        "^metadata-0004$",
        "--report",
        report.to_str().unwrap(),
        "--strict",
    ]);
    assert!(output.status.success(), "{}", stderr(&output));
    assert_eq!(read_json(&report)["records"][0]["result"], "pass");
}

fn metadata_cli_runs_and_checks_one_fixed_case() {
    let work = tempfile::tempdir().unwrap();
    let report = work.path().join("metadata-report.json");
    let allowed = work.path().join("allowed.json");
    std::fs::write(&allowed, "{\"cases\":[]}").unwrap();
    let adapter = std::env::current_exe().unwrap();
    let output = morphir(&[
        "mck",
        "run",
        "--suite",
        "metadata",
        "--adapter",
        adapter.to_str().unwrap(),
        "--adapter-arg",
        ADAPTER_FLAG,
        "--adapter-arg",
        "pass",
        "--filter",
        "^metadata-0001$",
        "--report",
        report.to_str().unwrap(),
        "--strict",
    ]);
    assert!(output.status.success(), "{}", stderr(&output));
    let produced = read_json(&report);
    assert_eq!(produced["suite"], "metadata");
    assert_eq!(produced["records"][0]["result"], "pass");
    let checked = morphir(&[
        "mck",
        "report",
        "check",
        report.to_str().unwrap(),
        allowed.to_str().unwrap(),
        "--filter",
        "^metadata-0001$",
    ]);
    assert!(checked.status.success(), "{}", stderr(&checked));
    let rendered = work.path().join("metadata-report.html");
    let output = morphir(&[
        "mck",
        "report",
        "render",
        report.to_str().unwrap(),
        "--output",
        rendered.to_str().unwrap(),
    ]);
    assert!(output.status.success(), "{}", stderr(&output));
    assert!(
        std::fs::read_to_string(rendered)
            .unwrap()
            .contains("metadata-0001")
    );
}

fn old_capabilities_skip_metadata_and_fail_strict_qualification() {
    let work = tempfile::tempdir().unwrap();
    let report = work.path().join("metadata-report.json");
    let adapter = std::env::current_exe().unwrap();
    let output = morphir(&[
        "mck",
        "run",
        "--suite",
        "metadata",
        "--adapter",
        adapter.to_str().unwrap(),
        "--adapter-arg",
        ADAPTER_FLAG,
        "--adapter-arg",
        "old",
        "--filter",
        "^metadata-0001$",
        "--report",
        report.to_str().unwrap(),
        "--strict",
    ]);
    assert!(!output.status.success());
    let produced = read_json(&report);
    assert_eq!(produced["records"][0]["result"], "skipped");
}

fn morphir(args: &[&str]) -> Output {
    std::process::Command::new(env!("CARGO_BIN_EXE_morphir"))
        .env("MORPHIR_LOG_FILE", "false")
        .env_remove("MORPHIR_LOG_DIR")
        .env_remove("MORPHIR_OUT_DIR")
        .args(args)
        .output()
        .expect("morphir runs")
}

fn stdout(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).into_owned()
}

fn stderr(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}

fn read_json(path: &Path) -> Value {
    serde_json::from_str(
        std::fs::read_to_string(path)
            .unwrap()
            .trim_start_matches('\u{FEFF}'),
    )
    .unwrap()
}

fn without_volatile(mut report: Value) -> Value {
    for key in ["startedAt", "driverVersion"] {
        report.as_object_mut().unwrap().remove(key);
    }
    for record in report["records"].as_array_mut().unwrap() {
        record.as_object_mut().unwrap().remove("durationMs");
    }
    report
}

// ---------------------------------------------------------------- tests

fn a_missing_preacquired_kit_does_not_fall_back_to_embedded() {
    let work = tempfile::tempdir().unwrap();
    let output = std::process::Command::new(std::env::current_exe().unwrap())
        .env("MORPHIR_MCK_PREACQUIRED_KIT", work.path().join("missing"))
        .env_remove("MORPHIR_MCK_REQUIRE_NETWORK_DENIAL")
        .arg("installed_cli_runs_vendored_kit_without_tool_runtimes")
        .output()
        .unwrap();
    assert!(!output.status.success(), "explicit missing kit must fail");
    assert!(
        stderr(&output).contains("copy the pre-acquired kit"),
        "{}",
        stderr(&output)
    );
}

// Preserve every input. The managed-kit verifier must see and reject unexpected
// files; symlinks must not reintroduce access to an acquisition cache or checkout.
fn copy_snapshot(source: &Path, destination: &Path) -> std::io::Result<()> {
    if !std::fs::symlink_metadata(source)?.is_dir() {
        return Err(std::io::Error::other("snapshot must be a directory"));
    }
    std::fs::create_dir(destination)?;
    for entry in std::fs::read_dir(source)? {
        let entry = entry?;
        let target = destination.join(entry.file_name());
        let kind = entry.file_type()?;
        if kind.is_dir() {
            copy_snapshot(&entry.path(), &target)?;
        } else if kind.is_file() {
            std::fs::copy(entry.path(), target)?;
        } else {
            return Err(std::io::Error::other(
                "snapshot contains a non-regular input",
            ));
        }
    }
    Ok(())
}

fn copied_snapshots_preserve_unexpected_inputs_for_verification() {
    let work = tempfile::tempdir().unwrap();
    let source = work.path().join("source");
    std::fs::create_dir_all(source.join("nested")).unwrap();
    std::fs::write(source.join("nested/input"), b"\0\xff\r\n").unwrap();
    std::fs::write(source.join("unexpected"), b"do not filter me").unwrap();
    let target = work.path().join("copy");
    copy_snapshot(&source, &target).unwrap();
    assert_eq!(
        std::fs::read(target.join("nested/input")).unwrap(),
        b"\0\xff\r\n"
    );
    assert_eq!(
        std::fs::read(target.join("unexpected")).unwrap(),
        b"do not filter me"
    );
    #[cfg(unix)]
    {
        std::os::unix::fs::symlink(source.join("nested/input"), source.join("link")).unwrap();
        assert!(copy_snapshot(&source, &work.path().join("linked")).is_err());
    }
}

fn required_network_denial_fails_when_tcp_is_available() {
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let output = std::process::Command::new(std::env::current_exe().unwrap())
        .env(
            "MORPHIR_MCK_REQUIRE_NETWORK_DENIAL",
            listener.local_addr().unwrap().to_string(),
        )
        .arg("installed_cli_runs_vendored_kit_without_tool_runtimes")
        .output()
        .unwrap();
    assert!(!output.status.success());
    assert!(
        stderr(&output).contains("network isolation unavailable"),
        "{}",
        stderr(&output)
    );
}

// The release workflow points this at the executable extracted from its archive.
// The harness may use Cargo and source fixtures; the installed CLI and its native
// replay adapter run with only explicitly copied inputs and an empty tool path.
fn installed_cli_runs_vendored_kit_without_tool_runtimes() {
    let denied_probe = std::env::var("MORPHIR_MCK_REQUIRE_NETWORK_DENIAL")
        .ok()
        .map(|address| {
            let address: std::net::SocketAddr =
                address.parse().expect("explicit TCP probe address");
            let error =
                std::net::TcpStream::connect_timeout(&address, std::time::Duration::from_secs(3))
                    .expect_err("network isolation unavailable: direct outbound TCP succeeded");
            format!("{address}: {error}")
        });
    let work = tempfile::tempdir().unwrap();
    let home = work.path().join("home");
    std::fs::create_dir(&home).unwrap();
    let cli = work
        .path()
        .join(format!("morphir{}", std::env::consts::EXE_SUFFIX));
    let adapter = work
        .path()
        .join(format!("adapter{}", std::env::consts::EXE_SUFFIX));
    let installed = std::env::var_os("MORPHIR_MCK_INSTALLED_CLI")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_BIN_EXE_morphir")));
    std::fs::copy(&installed, &cli).expect("copy the selected installed CLI");
    std::fs::copy(std::env::current_exe().unwrap(), &adapter).unwrap();
    let replay = work.path().join("transcript.ndjson");
    std::fs::copy(transcript(), &replay).unwrap();
    let run = |args: &[&str]| {
        let mut command = std::process::Command::new(&cli);
        command.current_dir(work.path()).env_clear();
        // Windows needs its OS directory to load system libraries. No developer
        // tool, proxy or inherited Morphir/cache configuration is preserved.
        if let Some(system_root) = std::env::var_os("SystemRoot") {
            command.env("SystemRoot", system_root);
        }
        for key in [
            "HOME",
            "USERPROFILE",
            "LOCALAPPDATA",
            "APPDATA",
            "XDG_CACHE_HOME",
        ] {
            command.env(key, &home);
        }
        for key in ["TMPDIR", "TMP", "TEMP"] {
            command.env(key, &home);
        }
        command
            .env("PATH", "")
            .env("MORPHIR_LOG_FILE", "false")
            .args(args)
            .output()
            .expect("run copied installed CLI")
    };
    let success = |args: &[&str]| {
        let output = run(args);
        assert!(
            output.status.success(),
            "{args:?}: {}\n{}",
            stdout(&output),
            stderr(&output)
        );
        output
    };
    success(&["--version"]);
    for args in [
        vec!["mck", "--help"],
        vec!["mck", "schema", "check", "--help"],
        vec!["mck", "report", "check", "--help"],
        vec!["mck", "report", "render", "--help"],
    ] {
        success(&args);
    }
    if let Some(source) = std::env::var_os("MORPHIR_MCK_PREACQUIRED_KIT") {
        copy_snapshot(Path::new(&source), &work.path().join("kit"))
            .expect("copy the pre-acquired kit");
    } else {
        success(&[
            "mck", "kit", "vendor", "--source", "embedded", "--dest", "kit",
        ]);
    }
    let status = success(&["mck", "kit", "status", "--kit", "kit", "--json"]);
    success(&["mck", "check", "kit"]);
    success(&["mck", "coverage", "--kit", "kit"]);
    success(&["mck", "schema", "check", "--kit", "kit"]);

    let source = repo().join("spec/ir/mck");
    for (kit, report) in [
        (source.to_str().unwrap(), "source.json"),
        ("kit", "report.json"),
    ] {
        success(&[
            "mck",
            "run",
            "--adapter",
            adapter.to_str().unwrap(),
            "--adapter-arg",
            ADAPTER_FLAG,
            "--adapter-arg",
            "replay",
            "--adapter-arg",
            replay.to_str().unwrap(),
            "--kit",
            kit,
            "--report",
            report,
        ]);
    }
    let actual = read_json(&work.path().join("report.json"));
    let expected = read_json(&work.path().join("source.json"));
    assert_eq!(
        actual["kit"]["snapshotDigest"],
        expected["kit"]["snapshotDigest"]
    );
    assert_eq!(actual["execution"]["session"]["status"], "finished");
    assert_eq!(
        without_volatile(actual.clone())["records"],
        without_volatile(expected)["records"]
    );
    assert_eq!(actual["records"].as_array().unwrap().len(), 802);
    std::fs::write(work.path().join("allowed.json"), "{\"cases\":[]}").unwrap();
    success(&[
        "mck",
        "report",
        "check",
        "report.json",
        "allowed.json",
        "--kit",
        "kit",
    ]);
    success(&[
        "mck",
        "report",
        "render",
        "report.json",
        "--format",
        "html",
        "--output",
        "report.html",
    ]);
    assert!(
        std::fs::read_to_string(work.path().join("report.html"))
            .unwrap()
            .contains("<!doctype html>")
    );

    package_acceptance::qualify(work.path(), &adapter, &run, denied_probe.as_deref());
    if std::env::var_os("MORPHIR_MCK_MVP_REQUIRED").is_some_and(|value| !value.is_empty()) {
        mvp_acceptance::qualify(work.path(), &run, denied_probe.as_deref());
    }
    metadata_acceptance::qualify(work.path(), &run, denied_probe.as_deref());

    if let Some(directory) = std::env::var_os("MORPHIR_MCK_ACCEPTANCE_EVIDENCE") {
        let directory = Path::new(&directory);
        std::fs::create_dir_all(directory).unwrap();
        for name in [
            "source.json",
            "report.json",
            "report.html",
            "package-integrity.json",
            "package-resolution.json",
            "package-runtime.json",
            "package-mvp.json",
            "package-mvp.html",
            "package-mvp-runtime.json",
            "package-mvp-negative.log",
            "package-examples.log",
            "metadata-preview.json",
        ] {
            if work.path().join(name).exists() {
                std::fs::copy(work.path().join(name), directory.join(name)).unwrap();
            }
        }
        std::fs::write(directory.join("kit-status.json"), status.stdout).unwrap();
        std::fs::write(
            directory.join("runtime.json"),
            serde_json::to_vec_pretty(&serde_json::json!({
                "networkDenial": denied_probe,
                "snapshotDigest": actual["kit"]["snapshotDigest"],
                "matchingRecords": actual["records"].as_array().unwrap().len(),
                "reportCheck": "passed",
            }))
            .unwrap(),
        )
        .unwrap();
    }

    // A kit shipped without its fixed schema closure must not appear healthy.
    std::fs::write(
        work.path().join("kit/spec/mck/vocabulary.schema.json"),
        "{}",
    )
    .unwrap();
    let corrupted = run(&["mck", "schema", "check", "--kit", "kit"]);
    assert_eq!(corrupted.status.code(), Some(1));
    assert!(
        stderr(&corrupted).contains("altered"),
        "{}",
        stderr(&corrupted)
    );
}

fn a_full_run_against_recorded_answers_reproduces_the_typescript_report() {
    let work = tempfile::tempdir().unwrap();
    let report = work.path().join("out").join("report.json");
    let exe = std::env::current_exe().unwrap();
    let transcript = transcript();
    let output = morphir(&[
        "mck",
        "run",
        "--adapter",
        exe.to_str().unwrap(),
        "--adapter-arg",
        ADAPTER_FLAG,
        "--adapter-arg",
        "replay",
        "--adapter-arg",
        transcript.to_str().unwrap(),
        "--kit",
        repo().join("spec/ir/mck").to_str().unwrap(),
        "--report",
        report.to_str().unwrap(),
    ]);
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    assert!(
        stderr(&output).contains("morphir-typescript supports IR format versions [4.0.0,4.1.0) (4.0.0 up to but not including 4.1.0)"),
        "the header goes to stderr: {}",
        stderr(&output)
    );
    let lines: Vec<String> = stdout(&output).lines().map(str::to_owned).collect();
    assert_eq!(lines[0], "722 pass, 0 fail, 0 kit-error, 80 skipped");
    assert_eq!(
        lines[1],
        "skipped distributions-0011 fence 0 [current]: version 3 not in capabilities"
    );
    assert_eq!(
        lines.len(),
        81,
        "the summary and one line per non-pass record, nothing else"
    );

    let produced = read_json(&report);
    assert_eq!(produced["contractVersion"], "2.0.0-draft.1");
    assert_eq!(produced["selection"]["kind"], "all");
    assert_eq!(produced["execution"]["session"]["status"], "finished");
    assert!(
        !report
            .with_file_name("report.json.provenance.json")
            .exists()
    );
    let mut expected = read_json(&repo().join("spec/mck/baseline/reports/morphir-typescript.json"));
    // A --kit checkout reports its own revision, as the first driver did.
    expected["kitVersion"] = produced["kit"]["version"].clone();
    let caps = &produced["adapter"]["negotiation"]["capabilities"];
    let projected = serde_json::json!({
        "contractVersion":1, "binding":caps["binding"], "language":caps["language"],
        "formatVersions":caps["formatVersions"], "kitVersion":produced["kit"]["version"],
        "records":produced["records"]
    });
    assert_eq!(without_volatile(projected), without_volatile(expected));
    assert_eq!(produced["kit"]["source"], "local");
    assert_eq!(caps["binding"], "morphir-typescript");
    assert_eq!(produced["adapter"]["command"][1], ADAPTER_FLAG);
    let allowed = work.path().join("allowed.json");
    std::fs::write(&allowed, "{\"cases\":[]}").unwrap();
    let checked = morphir(&[
        "mck",
        "report",
        "check",
        report.to_str().unwrap(),
        allowed.to_str().unwrap(),
        "--kit",
        repo().join("spec/ir/mck").to_str().unwrap(),
    ]);
    assert!(checked.status.success(), "{}", stderr(&checked));
}

/// The frozen transcript for `binding`, replayed by this test binary itself
/// (`ADAPTER_FLAG replay <transcript>`).
fn transcript_for(binding: &str) -> PathBuf {
    repo().join(format!("spec/mck/baseline/transcripts/{binding}.ndjson"))
}

/// The frozen consolidated-v1-shaped report `binding` recorded.
fn baseline_report(binding: &str) -> Value {
    read_json(&repo().join(format!("spec/mck/baseline/reports/{binding}.json")))
}

/// Runs `morphir mck run` against this test binary as a replay adapter for
/// `transcript`, with the kit checkout `spec/ir/mck`, and writes the report to `report`.
fn replay_run(transcript: &Path, report: &Path) -> Output {
    let exe = std::env::current_exe().unwrap();
    morphir(&[
        "mck",
        "run",
        "--adapter",
        exe.to_str().unwrap(),
        "--adapter-arg",
        ADAPTER_FLAG,
        "--adapter-arg",
        "replay",
        "--adapter-arg",
        transcript.to_str().unwrap(),
        "--kit",
        repo().join("spec/ir/mck").to_str().unwrap(),
        "--report",
        report.to_str().unwrap(),
    ])
}

/// The Gherkin kit replays each frozen transcript and preserves its records.
fn a_run_against_recorded_answers_reproduces_each_frozen_report() {
    for binding in ["morphir-typescript", "morphir-rust"] {
        let work = tempfile::tempdir().unwrap();
        let report = work.path().join("report.json");
        let transcript = transcript_for(binding);
        let output = replay_run(&transcript, &report);
        assert_eq!(
            output.status.code(),
            Some(0),
            "{binding}: {}",
            stderr(&output)
        );

        let produced = read_json(&report);
        assert_eq!(produced["execution"]["session"]["status"], "finished");
        let mut expected = baseline_report(binding);
        // A --kit checkout reports its own revision, as the legacy engine does.
        expected["kitVersion"] = produced["kit"]["version"].clone();
        let caps = &produced["adapter"]["negotiation"]["capabilities"];
        assert_eq!(caps["binding"], binding);
        let projected = serde_json::json!({
            "contractVersion":1, "binding":caps["binding"], "language":caps["language"],
            "formatVersions":caps["formatVersions"], "kitVersion":produced["kit"]["version"],
            "records":produced["records"]
        });
        assert_eq!(
            without_volatile(projected),
            without_volatile(expected),
            "{binding}: the report does not match its frozen baseline"
        );
    }
}

/// An adapter that stops answering partway through the kit produces kit errors.
fn a_transcript_cut_partway_reports_kit_errors() {
    let work = tempfile::tempdir().unwrap();
    let full = std::fs::read_to_string(transcript()).unwrap();
    let mut kept = String::new();
    let mut requests = 0;
    for line in full.lines() {
        if line.starts_with("{\"dir\":\"request\"") {
            requests += 1;
            if requests == 150 {
                break;
            }
        }
        kept.push_str(line);
        kept.push('\n');
    }
    assert_eq!(requests, 150, "the transcript has at least 150 requests");
    let cut = work.path().join("cut.ndjson");
    std::fs::write(&cut, kept).unwrap();

    let report = work.path().join("report.json");
    let output = replay_run(&cut, &report);
    assert_ne!(output.status.code(), Some(0), "{}", stderr(&output));
    let records = without_volatile(read_json(&report))["records"].clone();
    assert!(
        records
            .as_array()
            .unwrap()
            .iter()
            .any(|r| r["result"] == "kit-error"),
        "the cut transcript makes later fences fail"
    );
}

/// With no `--kit`, the CLI runs the kit embedded in this binary,
/// materializing its `.feature` files into a temp dir (`write_feature_files`
/// in `commands/mck.rs`) before the `Suite` scans them. The other replay
/// tests always pass `--kit spec/ir/mck` (the checkout), so this is the only
/// test that exercises that materialization against a real adapter exchange.
///
/// The embedded kit is built from the same `spec/ir/mck` checkout
/// (`crates/morphir-mck`'s `the_embedded_kit_is_the_checkout_kit_with_its_fixtures`
/// test pins this), so it must replay the frozen transcript identically to
/// the `--kit` checkout run above, once `kitVersion` (which differs: the
/// embedded kit reports its own build-time revision, not `git rev-parse
/// HEAD` of a checkout) is normalized away the same way.
fn a_gherkin_run_with_no_kit_replays_the_embedded_kit_against_one_frozen_transcript() {
    let binding = "morphir-typescript";
    let work = tempfile::tempdir().unwrap();
    let report = work.path().join("report.json");
    let exe = std::env::current_exe().unwrap();
    let transcript = transcript_for(binding);
    let output = morphir(&[
        "mck",
        "run",
        "--adapter",
        exe.to_str().unwrap(),
        "--adapter-arg",
        ADAPTER_FLAG,
        "--adapter-arg",
        "replay",
        "--adapter-arg",
        transcript.to_str().unwrap(),
        "--report",
        report.to_str().unwrap(),
    ]);
    assert_eq!(
        output.status.code(),
        Some(0),
        "the embedded kit could not replay {binding}'s frozen transcript with no --kit; \
         if the embedded kit has drifted from the spec/ir/mck checkout \
         that recorded the transcript, that is the reason, not a defect in this test: {}",
        stderr(&output)
    );

    let produced = read_json(&report);
    assert_eq!(produced["execution"]["session"]["status"], "finished");
    assert_eq!(produced["kit"]["source"], "embedded");
    let mut expected = baseline_report(binding);
    // The embedded kit reports its own build-time revision, not a checkout's `git rev-parse
    // HEAD`; the other replay test above normalizes this the same way.
    expected["kitVersion"] = produced["kit"]["version"].clone();
    let caps = &produced["adapter"]["negotiation"]["capabilities"];
    assert_eq!(caps["binding"], binding);
    let projected = serde_json::json!({
        "contractVersion":1, "binding":caps["binding"], "language":caps["language"],
        "formatVersions":caps["formatVersions"], "kitVersion":produced["kit"]["version"],
        "records":produced["records"]
    });
    assert_eq!(
        without_volatile(projected),
        without_volatile(expected),
        "the embedded kit's gherkin report does not match {binding}'s frozen baseline; if the \
         embedded kit has drifted from the checkout that recorded the transcript, the diff above \
         is that drift, not a bug in the gherkin engine"
    );
}

/// A filter matching no case is an error, rather than a passing empty suite.
fn a_filter_matching_nothing_is_an_error() {
    let output = morphir(&[
        "mck",
        "run",
        "--adapter",
        "definitely-not-an-mck-adapter",
        "--filter",
        "^nothing-0000$",
    ]);
    assert_eq!(output.status.code(), Some(1), "{}", stderr(&output));
    assert!(stderr(&output).contains("no cases"), "{}", stderr(&output));
}

fn a_run_without_an_adapter_is_a_usage_error_that_writes_nothing() {
    let work = tempfile::tempdir().unwrap();
    let report = work.path().join("report.json");
    for args in [
        vec!["mck", "run", "--report", report.to_str().unwrap()],
        vec![
            "mck",
            "run",
            "--adapter-arg",
            "x",
            "--report",
            report.to_str().unwrap(),
        ],
    ] {
        let output = morphir(&args);
        assert_eq!(
            output.status.code(),
            Some(2),
            "{args:?}: {}",
            stderr(&output)
        );
        assert!(stderr(&output).contains("--adapter"), "{}", stderr(&output));
        assert_eq!(stdout(&output), "");
    }
    assert!(!report.exists(), "no report without an adapter");
}

fn an_unsupported_filter_is_a_usage_error() {
    let output = morphir(&[
        "mck",
        "run",
        "--adapter",
        "unused",
        "--filter",
        "types-(?=0001)",
    ]);
    assert_eq!(output.status.code(), Some(2));
    assert!(
        stderr(&output).contains("invalid --filter regex:"),
        "{}",
        stderr(&output)
    );
    let output = morphir(&["mck", "run", "--adapter", "unused", "--only", "("]);
    assert_eq!(
        output.status.code(),
        Some(2),
        "--only is an alias of --filter"
    );
}

fn a_missing_adapter_program_fails_every_fence_and_still_reports() {
    let work = tempfile::tempdir().unwrap();
    let report = work.path().join("report.json");
    let output = morphir(&[
        "mck",
        "run",
        "--adapter",
        "definitely-not-an-mck-adapter",
        "--filter",
        "^types-0001$",
        "--report",
        report.to_str().unwrap(),
    ]);
    assert_eq!(output.status.code(), Some(1));
    let produced = read_json(&report);
    assert_eq!(produced["adapter"]["negotiation"]["status"], "failed");
    assert_eq!(
        produced["execution"]["session"]["errors"][0]["phase"],
        "spawn"
    );
    assert_eq!(produced["selection"]["pattern"], "^types-0001$");
    let records = produced["records"].as_array().unwrap();
    assert!(!records.is_empty());
    assert!(records.iter().all(|r| {
        r["result"] == "kit-error"
            && r["message"]
                .as_str()
                .unwrap()
                .starts_with("failed to start adapter: ")
    }));
}

fn an_empty_selection_is_never_a_success() {
    let work = tempfile::tempdir().unwrap();
    let report = work.path().join("report.json");
    let output = morphir(&[
        "mck",
        "run",
        "--adapter",
        "definitely-not-an-mck-adapter",
        "--filter",
        "^nothing-0000$",
        "--report",
        report.to_str().unwrap(),
    ]);
    assert_eq!(output.status.code(), Some(1));
    assert!(
        stderr(&output).contains("error: no cases selected"),
        "{}",
        stderr(&output)
    );
    assert_eq!(
        stdout(&output).trim_end(),
        "0 pass, 0 fail, 0 kit-error, 0 skipped"
    );
    assert_eq!(
        read_json(&report)["records"],
        Value::Array(vec![]),
        "the empty report is still written"
    );
}

/// The frozen v1-shaped TypeScript report: `mck report compare` must read it
/// without requiring the draft v2 format's other members.
fn frozen_v1_report_path() -> PathBuf {
    repo().join("spec/mck/baseline/reports/morphir-typescript.json")
}

fn mck_report_compare_accepts_two_copies_of_a_frozen_report() {
    let work = tempfile::tempdir().unwrap();
    let text = std::fs::read_to_string(frozen_v1_report_path()).unwrap();
    let a = work.path().join("a.json");
    let b = work.path().join("b.json");
    std::fs::write(&a, &text).unwrap();
    std::fs::write(&b, &text).unwrap();
    let output = morphir(&[
        "mck",
        "report",
        "compare",
        a.to_str().unwrap(),
        b.to_str().unwrap(),
    ]);
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
}

fn mck_report_compare_treats_implicit_semantic_check_as_explicit() {
    let work = tempfile::tempdir().unwrap();
    let mut report = read_json(&frozen_v1_report_path());
    let a = work.path().join("implicit.json");
    std::fs::write(&a, serde_json::to_vec(&report).unwrap()).unwrap();
    report["records"][0]["check"] = Value::String("semantic".into());
    let b = work.path().join("explicit.json");
    std::fs::write(&b, serde_json::to_vec(&report).unwrap()).unwrap();
    let output = morphir(&[
        "mck",
        "report",
        "compare",
        a.to_str().unwrap(),
        b.to_str().unwrap(),
    ]);
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    report["records"][0]["check"] = Value::String("spelling".into());
    std::fs::write(&b, serde_json::to_vec(&report).unwrap()).unwrap();
    let output = morphir(&[
        "mck",
        "report",
        "compare",
        a.to_str().unwrap(),
        b.to_str().unwrap(),
    ]);
    assert_eq!(output.status.code(), Some(1), "{}", stdout(&output));
}

fn mck_report_compare_rejects_a_changed_record_result_and_names_its_index() {
    let work = tempfile::tempdir().unwrap();
    let mut report = read_json(&frozen_v1_report_path());
    let a = work.path().join("a.json");
    std::fs::write(&a, serde_json::to_vec(&report).unwrap()).unwrap();
    let records = report["records"].as_array_mut().unwrap();
    assert!(
        records.len() > 1,
        "the frozen report has more than one record"
    );
    assert_eq!(records[1]["result"], "pass");
    records[1]["result"] = Value::String("fail".into());
    let b = work.path().join("b.json");
    std::fs::write(&b, serde_json::to_vec(&report).unwrap()).unwrap();
    let output = morphir(&[
        "mck",
        "report",
        "compare",
        a.to_str().unwrap(),
        b.to_str().unwrap(),
    ]);
    assert_eq!(output.status.code(), Some(1), "{}", stdout(&output));
    assert!(
        stderr(&output).contains("index 1"),
        "the differing record's index is named: {}",
        stderr(&output)
    );
}

fn mck_report_compare_rejects_a_record_count_mismatch() {
    let work = tempfile::tempdir().unwrap();
    let mut report = read_json(&frozen_v1_report_path());
    let a = work.path().join("a.json");
    std::fs::write(&a, serde_json::to_vec(&report).unwrap()).unwrap();
    report["records"].as_array_mut().unwrap().pop();
    let b = work.path().join("b.json");
    std::fs::write(&b, serde_json::to_vec(&report).unwrap()).unwrap();
    let output = morphir(&[
        "mck",
        "report",
        "compare",
        a.to_str().unwrap(),
        b.to_str().unwrap(),
    ]);
    assert_eq!(output.status.code(), Some(1), "{}", stdout(&output));
    assert!(
        stderr(&output).contains("counts differ"),
        "the count mismatch is reported: {}",
        stderr(&output)
    );
}

/// A report with no `records` member is an error, not a report with zero
/// records, so `mck report compare` cannot pass two such files.
fn mck_report_compare_rejects_a_report_without_records() {
    let work = tempfile::tempdir().unwrap();
    let mut report = read_json(&frozen_v1_report_path());
    report.as_object_mut().unwrap().remove("records");
    let a = work.path().join("a.json");
    std::fs::write(&a, serde_json::to_vec(&report).unwrap()).unwrap();
    let output = morphir(&[
        "mck",
        "report",
        "compare",
        a.to_str().unwrap(),
        a.to_str().unwrap(),
    ]);
    assert_eq!(output.status.code(), Some(1), "{}", stdout(&output));
    assert!(
        stderr(&output).contains("missing field `records`"),
        "the missing member is named: {}",
        stderr(&output)
    );
}

/// A kit with no `.feature` cases is a usage error, not an empty run.
fn a_run_on_a_kit_without_feature_files_is_a_usage_error() {
    let work = tempfile::tempdir().unwrap();
    let kit = work.path().join("mck");
    copy_tree(&repo().join("spec/ir/mck"), &kit);
    for entry in std::fs::read_dir(&kit).unwrap() {
        let path = entry.unwrap().path();
        if path.extension().is_some_and(|e| e == "feature") {
            std::fs::remove_file(path).unwrap();
        }
    }
    let report = work.path().join("report.json");
    let output = morphir(&[
        "mck",
        "run",
        "--adapter",
        "definitely-not-an-mck-adapter",
        "--kit",
        kit.to_str().unwrap(),
        "--repo-root",
        repo().to_str().unwrap(),
        "--report",
        report.to_str().unwrap(),
    ]);
    assert_eq!(output.status.code(), Some(2), "{}", stderr(&output));
    assert!(
        stderr(&output).contains("error: the kit has no .feature files"),
        "{}",
        stderr(&output)
    );
    assert_eq!(stdout(&output), "");
    assert!(!report.exists(), "no report for a usage error");
}

/// Copies the directory tree `from` to `to`.
fn copy_tree(from: &Path, to: &Path) {
    std::fs::create_dir_all(to).unwrap();
    for entry in std::fs::read_dir(from).unwrap() {
        let entry = entry.unwrap();
        let target = to.join(entry.file_name());
        if entry.file_type().unwrap().is_dir() {
            copy_tree(&entry.path(), &target);
        } else {
            std::fs::copy(entry.path(), target).unwrap();
        }
    }
}

fn a_shutdown_failure_is_in_the_report_even_when_records_pass() {
    let work = tempfile::tempdir().unwrap();
    let report = work.path().join("report.json");
    let exe = std::env::current_exe().unwrap();
    let output = morphir(&[
        "mck",
        "run",
        "--adapter",
        exe.to_str().unwrap(),
        "--adapter-arg",
        ADAPTER_FLAG,
        "--adapter-arg",
        "shutdown-failure",
        "--adapter-arg",
        transcript().to_str().unwrap(),
        "--kit",
        repo().join("spec/ir/mck").to_str().unwrap(),
        "--report",
        report.to_str().unwrap(),
    ]);
    assert_eq!(output.status.code(), Some(1), "{}", stderr(&output));
    let produced = read_json(&report);
    assert_eq!(produced["execution"]["session"]["status"], "failed");
    assert_eq!(
        produced["execution"]["session"]["errors"][0]["phase"],
        "shutdown"
    );
    assert!(
        produced["records"]
            .as_array()
            .unwrap()
            .iter()
            .any(|r| r["result"] == "pass")
    );
}

// ---------------------------------------------------------------- runner

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.get(1).map(String::as_str) == Some(ADAPTER_FLAG) {
        if let Some(mode @ ("old" | "pass" | "reordered-facts")) = args.get(2).map(String::as_str) {
            metadata_adapter(mode);
            return;
        }
        let exit_code = match args.get(2).map(String::as_str) {
            Some("replay") => 0,
            Some("shutdown-failure") => 7,
            other => panic!("unexpected adapter mode: {other:?}"),
        };
        replay_adapter(Path::new(&args[3]), exit_code);
        return;
    }
    let tests: &[(&str, fn())] = &[
        (
            "the_legacy_engine_option_is_rejected_after_cutover",
            the_legacy_engine_option_is_rejected_after_cutover,
        ),
        (
            "metadata_cli_accepts_reordered_fact_object_members",
            metadata_cli_accepts_reordered_fact_object_members,
        ),
        (
            "metadata_cli_runs_and_checks_one_fixed_case",
            metadata_cli_runs_and_checks_one_fixed_case,
        ),
        (
            "old_capabilities_skip_metadata_and_fail_strict_qualification",
            old_capabilities_skip_metadata_and_fail_strict_qualification,
        ),
        (
            "missing_prepared_adapter_fails_closed",
            mvp_acceptance::missing_prepared_adapter_fails_closed,
        ),
        (
            "installed_cli_qualification_requires_package_evidence",
            package_acceptance::installed_cli_qualification_requires_package_evidence,
        ),
        (
            "missing_package_corpus_fails_qualification",
            package_acceptance::missing_package_corpus_fails_qualification,
        ),
        (
            "malformed_package_corpus_fails_qualification",
            package_acceptance::malformed_package_corpus_fails_qualification,
        ),
        (
            "altered_package_replay_fails_qualification",
            package_acceptance::altered_package_replay_fails_qualification,
        ),
        (
            "altered_expected_package_report_fails_qualification",
            package_acceptance::altered_expected_package_report_fails_qualification,
        ),
        (
            "copied_snapshots_preserve_unexpected_inputs_for_verification",
            copied_snapshots_preserve_unexpected_inputs_for_verification,
        ),
        (
            "required_network_denial_fails_when_tcp_is_available",
            required_network_denial_fails_when_tcp_is_available,
        ),
        (
            "a_missing_preacquired_kit_does_not_fall_back_to_embedded",
            a_missing_preacquired_kit_does_not_fall_back_to_embedded,
        ),
        (
            "installed_cli_runs_vendored_kit_without_tool_runtimes",
            installed_cli_runs_vendored_kit_without_tool_runtimes,
        ),
        (
            "a_shutdown_failure_is_in_the_report_even_when_records_pass",
            a_shutdown_failure_is_in_the_report_even_when_records_pass,
        ),
        (
            "a_full_run_against_recorded_answers_reproduces_the_typescript_report",
            a_full_run_against_recorded_answers_reproduces_the_typescript_report,
        ),
        (
            "a_run_against_recorded_answers_reproduces_each_frozen_report",
            a_run_against_recorded_answers_reproduces_each_frozen_report,
        ),
        (
            "a_transcript_cut_partway_reports_kit_errors",
            a_transcript_cut_partway_reports_kit_errors,
        ),
        (
            "a_gherkin_run_with_no_kit_replays_the_embedded_kit_against_one_frozen_transcript",
            a_gherkin_run_with_no_kit_replays_the_embedded_kit_against_one_frozen_transcript,
        ),
        (
            "a_filter_matching_nothing_is_an_error",
            a_filter_matching_nothing_is_an_error,
        ),
        (
            "a_run_without_an_adapter_is_a_usage_error_that_writes_nothing",
            a_run_without_an_adapter_is_a_usage_error_that_writes_nothing,
        ),
        (
            "an_unsupported_filter_is_a_usage_error",
            an_unsupported_filter_is_a_usage_error,
        ),
        (
            "a_missing_adapter_program_fails_every_fence_and_still_reports",
            a_missing_adapter_program_fails_every_fence_and_still_reports,
        ),
        (
            "an_empty_selection_is_never_a_success",
            an_empty_selection_is_never_a_success,
        ),
        (
            "mck_report_compare_accepts_two_copies_of_a_frozen_report",
            mck_report_compare_accepts_two_copies_of_a_frozen_report,
        ),
        (
            "mck_report_compare_treats_implicit_semantic_check_as_explicit",
            mck_report_compare_treats_implicit_semantic_check_as_explicit,
        ),
        (
            "mck_report_compare_rejects_a_changed_record_result_and_names_its_index",
            mck_report_compare_rejects_a_changed_record_result_and_names_its_index,
        ),
        (
            "mck_report_compare_rejects_a_record_count_mismatch",
            mck_report_compare_rejects_a_record_count_mismatch,
        ),
        (
            "mck_report_compare_rejects_a_report_without_records",
            mck_report_compare_rejects_a_report_without_records,
        ),
        (
            "a_run_on_a_kit_without_feature_files_is_a_usage_error",
            a_run_on_a_kit_without_feature_files_is_a_usage_error,
        ),
    ];
    let filter = args.iter().skip(1).find(|a| !a.starts_with('-')).cloned();
    let mut failed = Vec::new();
    let mut ran = 0;
    for (name, test) in tests {
        if filter.as_ref().is_some_and(|f| !name.contains(f.as_str())) {
            continue;
        }
        ran += 1;
        let outcome = std::panic::catch_unwind(test);
        println!(
            "test {name} ... {}",
            if outcome.is_ok() { "ok" } else { "FAILED" }
        );
        if outcome.is_err() {
            failed.push(*name);
        }
    }
    println!(
        "\ntest result: {}. {} passed; {} failed",
        if failed.is_empty() { "ok" } else { "FAILED" },
        ran - failed.len(),
        failed.len()
    );
    if !failed.is_empty() {
        std::process::exit(101);
    }
}
