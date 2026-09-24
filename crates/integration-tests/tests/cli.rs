//! CLI integration tests for Morphir
//!
//! These tests require the morphir binary to be pre-built and available.
//! Run `mise run build:release` before running these tests.

use cucumber::{World, given, then, when};
use integration_tests::{CliTestContext, cli_tests_available};
use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpListener;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::thread::{self, JoinHandle};
use std::time::Duration;

#[derive(Debug)]
struct LocalHttpSource {
    url: String,
    requests: Arc<AtomicUsize>,
    shutdown: Arc<AtomicBool>,
    worker: Option<JoinHandle<()>>,
}

impl LocalHttpSource {
    fn serve(bytes: Vec<u8>) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind local HTTP source");
        listener
            .set_nonblocking(true)
            .expect("configure local HTTP source");
        let address = listener.local_addr().expect("local HTTP source address");
        let requests = Arc::new(AtomicUsize::new(0));
        let shutdown = Arc::new(AtomicBool::new(false));
        let request_count = Arc::clone(&requests);
        let stop = Arc::clone(&shutdown);
        let worker = thread::spawn(move || {
            while !stop.load(Ordering::Relaxed) {
                match listener.accept() {
                    Ok((mut stream, _)) => {
                        stream
                            .set_read_timeout(Some(Duration::from_secs(5)))
                            .expect("set HTTP read timeout");
                        let mut request_line = Vec::new();
                        BufReader::new((&mut stream).take(4096))
                            .read_until(b'\n', &mut request_line)
                            .expect("read HTTP request line");
                        if !request_line.ends_with(b"\r\n")
                            || !request_line.starts_with(b"GET /greeting-example.json ")
                        {
                            continue;
                        }
                        request_count.fetch_add(1, Ordering::Relaxed);
                        write!(
                            stream,
                            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                            bytes.len()
                        )
                        .expect("write HTTP response headers");
                        stream.write_all(&bytes).expect("write HTTP response body");
                    }
                    Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                        thread::sleep(Duration::from_millis(10));
                    }
                    Err(error) => panic!("accept local HTTP request: {error}"),
                }
            }
        });
        Self {
            url: format!("http://{address}/greeting-example.json"),
            requests,
            shutdown,
            worker: Some(worker),
        }
    }
}

impl Drop for LocalHttpSource {
    fn drop(&mut self) {
        self.shutdown.store(true, Ordering::Relaxed);
        if let Some(worker) = self.worker.take() {
            worker.join().expect("stop local HTTP source");
        }
    }
}

/// World state for CLI cucumber tests
#[derive(Debug, Default, World)]
pub struct CliWorld {
    context: Option<CliTestContext>,
    last_result: Option<integration_tests::CommandResult>,
    remote_source: Option<LocalHttpSource>,
}

#[given("the morphir CLI is built and available")]
fn given_morphir_cli_is_available(_world: &mut CliWorld) {
    assert!(
        CliTestContext::get_morphir_binary().is_some(),
        "build the morphir CLI before running integration tests"
    );
}

#[given("I have a temporary test directory")]
fn given_temp_directory(world: &mut CliWorld) {
    world.context = Some(CliTestContext::new().expect("create temporary test directory"));
}

#[given(regex = r#"I have a Classic IR file from fixture "([^"]+)""#)]
fn given_classic_ir_fixture(world: &mut CliWorld, name: String) {
    copy_ir_fixture(world, "v3", &name);
}

#[given(regex = r#"I have a V4 IR file from fixture "([^"]+)""#)]
fn given_v4_ir_fixture(world: &mut CliWorld, name: String) {
    copy_ir_fixture(world, "v4", &name);
}

fn copy_ir_fixture(world: &CliWorld, version: &str, name: &str) {
    let fixture = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../website/static/ir/examples")
        .join(version)
        .join(name);
    let contents = std::fs::read_to_string(&fixture)
        .unwrap_or_else(|error| panic!("read {}: {error}", fixture.display()));
    world
        .context
        .as_ref()
        .expect("temporary test directory")
        .write_source_file(name, &contents)
        .expect("copy IR fixture");
}

#[given(regex = r#"I have a Classic IR file with dependency "([^"]+)""#)]
fn given_classic_ir_with_dependency(world: &mut CliWorld, dependency: String) {
    let fixture = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../website/static/ir/examples/v3/greeting-example.json");
    let mut document: serde_json::Value =
        serde_json::from_slice(&std::fs::read(&fixture).expect("read Classic IR greeting fixture"))
            .expect("parse Classic IR greeting fixture");
    let dependency_path: Vec<Vec<&str>> = dependency
        .split('/')
        .map(|segment| segment.split('-').collect())
        .collect();
    document["distribution"][2] = serde_json::json!([[dependency_path, {"modules": []}]]);
    world
        .context
        .as_ref()
        .expect("temporary test directory")
        .write_source_file("input.json", &document.to_string())
        .expect("write Classic IR with dependency");
}

#[given("a local HTTP source serves the Classic IR greeting fixture")]
fn given_local_http_source(world: &mut CliWorld) {
    let fixture = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../website/static/ir/examples/v3/greeting-example.json");
    world.remote_source = Some(LocalHttpSource::serve(
        std::fs::read(&fixture).expect("read Classic IR greeting fixture"),
    ));
}

#[given(regex = r#"I have a file "([^"]+)" with:"#)]
fn given_file_with_contents(world: &mut CliWorld, name: String, step: &cucumber::gherkin::Step) {
    let contents = step.docstring().expect("file contents docstring");
    world
        .context
        .as_ref()
        .expect("temporary test directory")
        .write_source_file(&name, contents)
        .expect("write test file");
}

#[given(regex = r#"I have a minimal V4 (Library|Specs|Application) IR document"#)]
fn given_minimal_v4_distribution(world: &mut CliWorld, variant: String) {
    let distribution = match variant.as_str() {
        "Library" => serde_json::json!({"Library": {
            "packageName": "acme/shop",
            "dependencies": {},
            "def": {"modules": {"main": {"Public": {"types": {}, "values": {}}}}}
        }}),
        "Specs" => serde_json::json!({"Specs": {
            "packageName": "acme/shop",
            "dependencies": {},
            "spec": {"modules": {"pricing": {"types": {}, "values": {}}}}
        }}),
        "Application" => serde_json::json!({"Application": {
            "packageName": "acme/shop",
            "dependencies": {},
            "def": {"modules": {"main": {"Public": {"types": {}, "values": {}}}}},
            "entryPoints": {"start": {"target": "acme/shop:main#run", "kind": "main"}}
        }}),
        _ => unreachable!("the step expression admits only three variants"),
    };
    let document = serde_json::json!({"formatVersion": 4, "distribution": distribution});
    world
        .context
        .as_ref()
        .expect("temporary test directory")
        .write_source_file("input.json", &document.to_string())
        .expect("write V4 IR document");
}

#[when(regex = r#"I run "([^"]+)""#)]
fn when_run_morphir(world: &mut CliWorld, command: String) {
    let args: Vec<&str> = command.split_whitespace().collect();
    assert_eq!(args.first(), Some(&"morphir"), "expected a morphir command");
    world.last_result = Some(
        world
            .context
            .as_ref()
            .expect("temporary test directory")
            .execute_cli_command(&args[1..])
            .expect("execute morphir command"),
    );
}

#[when(regex = r#"^I migrate the HTTP fixture to "([^"]+)"$"#)]
fn when_migrate_http_fixture(world: &mut CliWorld, output: String) {
    run_http_migration(world, &output, None);
}

#[when(regex = r#"^I migrate the HTTP fixture to "([^"]+)" with "([^"]+)"$"#)]
fn when_migrate_http_fixture_with_option(world: &mut CliWorld, output: String, option: String) {
    assert!(matches!(option.as_str(), "--force-refresh" | "--no-cache"));
    run_http_migration(world, &output, Some(&option));
}

fn run_http_migration(world: &mut CliWorld, output: &str, option: Option<&str>) {
    let url = world
        .remote_source
        .as_ref()
        .expect("local HTTP source")
        .url
        .clone();
    let option = option.unwrap_or("");
    when_run_morphir(
        world,
        format!("morphir migrate {url} --output {output} --target-version v4 {option}"),
    );
}

#[then("the command should succeed")]
fn then_command_should_succeed(world: &mut CliWorld) {
    world
        .last_result
        .as_ref()
        .expect("CLI result")
        .assert_success();
}

#[then("the command should fail")]
fn then_command_should_fail(world: &mut CliWorld) {
    world
        .last_result
        .as_ref()
        .expect("CLI result")
        .assert_failure();
}

#[then(regex = r#"the file "([^"]+)" should have V4 Library package "([^"]+)""#)]
fn then_file_has_v4_library_package(world: &mut CliWorld, file: String, package: String) {
    assert_v4_library_package(&read_json_file(world, &file), &package);
}

#[then(regex = r#"the file "([^"]+)" should have V4 dependency "([^"]+)""#)]
fn then_file_has_v4_dependency(world: &mut CliWorld, file: String, dependency: String) {
    let document = read_json_file(world, &file);
    assert!(
        document["distribution"]["Library"]["dependencies"][&dependency]["modules"].is_object(),
        "missing V4 dependency {dependency}"
    );
}

#[then(regex = r#"the HTTP source should have received (\d+) requests?"#)]
fn then_http_request_count(world: &mut CliWorld, expected: usize) {
    let actual = world
        .remote_source
        .as_ref()
        .expect("local HTTP source")
        .requests
        .load(Ordering::Relaxed);
    assert_eq!(actual, expected);
}

#[then(regex = r#"the file "([^"]+)" should use the canonical V4 Library wrapper"#)]
fn then_file_uses_v4_library_wrapper(world: &mut CliWorld, file: String) {
    let document = read_json_file(world, &file);
    assert_eq!(document["formatVersion"], 4);
    let distribution = document["distribution"]
        .as_object()
        .expect("V4 distribution must be an object");
    assert_eq!(distribution.len(), 1);
    let library = distribution["Library"]
        .as_object()
        .expect("Library wrapper must be an object");
    assert_eq!(library["packageName"], "elm-compat");
    assert!(library["dependencies"].is_object());
    assert!(library["def"]["modules"]["api"].is_object());
    assert!(library["def"]["modules"]["main"].is_object());
}

#[then(regex = r#"the file "([^"]+)" should preserve the V4 (Library|Specs|Application) wrapper"#)]
fn then_file_preserves_v4_wrapper(world: &mut CliWorld, file: String, variant: String) {
    let document = read_json_file(world, &file);
    assert_eq!(document["formatVersion"], 4);
    let distribution = document["distribution"]
        .as_object()
        .expect("V4 distribution must be an object");
    assert_eq!(distribution.len(), 1);
    let payload = distribution[&variant]
        .as_object()
        .expect("variant wrapper must be an object");
    assert_eq!(payload["packageName"], "acme/shop");
    assert!(payload["dependencies"].is_object());
    match variant.as_str() {
        "Library" => assert!(payload["def"]["modules"]["main"].is_object()),
        "Specs" => assert!(payload["spec"]["modules"]["pricing"].is_object()),
        "Application" => {
            assert!(payload["def"]["modules"]["main"].is_object());
            assert_eq!(
                payload["entryPoints"]["start"]["target"],
                "acme/shop:main#run"
            );
            assert_eq!(payload["entryPoints"]["start"]["kind"], "main");
        }
        _ => unreachable!("the step expression admits only three variants"),
    }
}

#[then(regex = r#"the file "([^"]+)" should have Classic Library package "([^"]+)""#)]
fn then_file_has_classic_library_package(world: &mut CliWorld, file: String, package: String) {
    let document = read_json_file(world, &file);
    assert_eq!(document["formatVersion"], 3);
    assert_eq!(document["distribution"][0], "Library");
    assert_eq!(
        document["distribution"][1],
        serde_json::json!([package.split('-').collect::<Vec<_>>()])
    );
    assert_eq!(
        document["distribution"][3]["modules"]
            .as_array()
            .map(Vec::len),
        Some(2)
    );
}

#[then(regex = r#"stdout should have V4 Library package "([^"]+)""#)]
fn then_stdout_has_v4_library_package(world: &mut CliWorld, package: String) {
    let stdout = &world.last_result.as_ref().expect("CLI result").stdout;
    let document: serde_json::Value = serde_json::from_str(stdout).expect("stdout must be JSON IR");
    assert_v4_library_package(&document, &package);
}

#[then(regex = r#"stdout should report a V3 to V4 JSON migration from "([^"]+)" to "([^"]+)""#)]
fn then_stdout_reports_migration(world: &mut CliWorld, input: String, output: String) {
    let stdout = &world.last_result.as_ref().expect("CLI result").stdout;
    let report: serde_json::Value = serde_json::from_str(stdout).expect("stdout must be JSON");
    assert_eq!(report["success"], true);
    assert_eq!(report["input"], input);
    assert_eq!(report["output"], output);
    assert_eq!(report["source"], "v3/json/single-file");
    assert_eq!(report["target"], "v4/json/single-file");
    assert!(report.get("error").is_none());
}

#[then(regex = r#"the file "([^"]+)" should contain V4 modules "([^"]+)" and "([^"]+)""#)]
fn then_file_contains_v4_modules(
    world: &mut CliWorld,
    file: String,
    first: String,
    second: String,
) {
    let document = read_json_file(world, &file);
    let modules = &document["distribution"]["Library"]["def"]["modules"];
    for name in [&first, &second] {
        assert!(
            modules[name]["Public"].is_object(),
            "missing V4 module {name}"
        );
    }
}

#[then(regex = r#"the file "([^"]+)" should contain V4 types "([^"]+)" and "([^"]+)""#)]
fn then_file_contains_v4_types(world: &mut CliWorld, file: String, first: String, second: String) {
    assert_v4_definitions(world, &file, "types", [&first, &second]);
}

#[then(regex = r#"the file "([^"]+)" should contain V4 values "([^"]+)" and "([^"]+)""#)]
fn then_file_contains_v4_values(world: &mut CliWorld, file: String, first: String, second: String) {
    assert_v4_definitions(world, &file, "values", [&first, &second]);
}

fn assert_v4_definitions(world: &CliWorld, file: &str, kind: &str, names: [&str; 2]) {
    let document = read_json_file(world, file);
    let modules = &document["distribution"]["Library"]["def"]["modules"];
    for name in names {
        let (module, definition) = name.split_once('/').expect("module/definition name");
        assert!(
            modules[module]["Public"][kind][definition].is_object(),
            "missing V4 {kind} definition {name}"
        );
    }
}

#[then(regex = r#"the file "([^"]+)" should use expanded type references"#)]
fn then_file_uses_expanded_type_references(world: &mut CliWorld, file: String) {
    let document = read_json_file(world, &file);
    assert_eq!(
        document
            .pointer("/distribution/Library/def/modules/api/Public/types/request/Public/TypeAliasDefinition/typeExp/Record/fields/action/Reference/fqname")
            .and_then(serde_json::Value::as_str),
        Some("morphir/SDK:string#string")
    );
}

fn read_json_file(world: &CliWorld, file: &str) -> serde_json::Value {
    let path = world
        .context
        .as_ref()
        .expect("temporary test directory")
        .project_root
        .join(file);
    serde_json::from_slice(
        &std::fs::read(&path).unwrap_or_else(|error| panic!("read {}: {error}", path.display())),
    )
    .expect("output must be valid JSON")
}

fn assert_v4_library_package(document: &serde_json::Value, package: &str) {
    assert_eq!(document["formatVersion"], 4);
    assert_eq!(document["distribution"]["Library"]["packageName"], package);
    assert!(document["distribution"]["Library"]["def"]["modules"].is_object());
}

#[then(regex = r#"the stderr should contain "([^"]+)""#)]
fn then_stderr_contains(world: &mut CliWorld, expected: String) {
    let stderr = &world.last_result.as_ref().expect("CLI result").stderr;
    assert!(
        stderr.contains(&expected),
        "stderr did not contain {expected:?}: {stderr}"
    );
}

// Background step
#[given("I have a temporary test project")]
fn given_temp_project(world: &mut CliWorld) {
    if !cli_tests_available() {
        // Skip test if CLI binary not available
        return;
    }

    let context = CliTestContext::new().expect("Failed to create test context");
    context
        .create_test_project()
        .expect("Failed to create test project");
    world.context = Some(context);
}

// Source file step
#[given(regex = r#"I have a Gleam source file "([^"]+)" with:"#)]
fn given_gleam_source_file(world: &mut CliWorld, path: String, step: &cucumber::gherkin::Step) {
    if let Some(context) = &world.context {
        let content = step
            .docstring()
            .expect("Expected docstring with file content");
        context
            .write_source_file(&path, content)
            .expect("Failed to write source file");
    }
}

// CLI command step
#[when(regex = r#"I run CLI command "([^"]+)""#)]
fn when_run_cli_command(world: &mut CliWorld, command: String) {
    if let Some(context) = &world.context {
        // Parse the command string into args
        let args: Vec<&str> = command.split_whitespace().collect();
        // Skip the "morphir" part if present
        let args = if args.first() == Some(&"morphir") {
            &args[1..]
        } else {
            &args[..]
        };

        match context.execute_cli_command(args) {
            Ok(result) => world.last_result = Some(result),
            Err(e) => panic!("Failed to execute CLI command: {}", e),
        }
    }
}

// Success assertion
#[then("the CLI command should succeed")]
fn then_cli_should_succeed(world: &mut CliWorld) {
    if let Some(result) = &world.last_result {
        result.assert_success();
    }
}

// Failure assertion
#[then("the CLI command should fail")]
fn then_cli_should_fail(world: &mut CliWorld) {
    if let Some(result) = &world.last_result {
        result.assert_failure();
    }
}

// Output contains assertion
#[then(regex = r#"the output should contain "([^"]+)""#)]
fn then_output_contains(world: &mut CliWorld, text: String) {
    if let Some(result) = &world.last_result {
        result.assert_output_contains(&text);
    }
}

#[tokio::main]
async fn main() {
    CliWorld::cucumber()
        .fail_on_skipped()
        .filter_run_and_exit("tests/features", |feature, rule, scenario| {
            !feature.tags.iter().any(|tag| tag == "wip")
                && !rule.is_some_and(|rule| rule.tags.iter().any(|tag| tag == "wip"))
                && !scenario.tags.iter().any(|tag| tag == "wip")
        })
        .await;
}
