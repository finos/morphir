//! Integration tests for CLI commands

use std::path::PathBuf;
use tempfile::TempDir;

struct TestIndex {
    root: PathBuf,
    source: PathBuf,
    digest: String,
    filename: String,
}

fn morphir_command() -> std::process::Command {
    let mut command = std::process::Command::new(env!("CARGO_BIN_EXE_morphir"));
    command.env("MORPHIR_LOG_FILE", "false");
    command.env_remove("MORPHIR_LOG_DIR");
    command
}

fn write_local_desktop_package(directory: &std::path::Path, version: &str) -> PathBuf {
    #[cfg(target_os = "linux")]
    {
        let package = directory.join(format!("morphir-desktop-{version}-linux.AppImage"));
        std::fs::write(&package, format!("desktop-{version}")).unwrap();
        package
    }
    #[cfg(any(windows, target_os = "macos"))]
    {
        let executable = if cfg!(windows) {
            "morphir-desktop.exe"
        } else {
            "Morphir Desktop.app/Contents/MacOS/morphir-desktop"
        };
        let package = directory.join(format!("morphir-desktop-{version}.zip"));
        let file = std::fs::File::create(&package).unwrap();
        let mut archive = zip::ZipWriter::new(file);
        archive
            .start_file(executable, zip::write::SimpleFileOptions::default())
            .unwrap();
        std::io::Write::write_all(&mut archive, format!("desktop-{version}").as_bytes()).unwrap();
        archive.finish().unwrap();
        package
    }
}

#[test]
fn desktop_command_exposes_workspace_wait_and_offline_contract() {
    let output = morphir_command()
        .args(["desktop", "--help"])
        .output()
        .expect("failed to run morphir desktop --help");

    assert!(
        output.status.success(),
        "stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let help = String::from_utf8_lossy(&output.stdout);
    assert!(help.contains("[PATH]"), "{help}");
    assert!(help.contains("--wait"), "{help}");
    assert!(help.contains("--offline"), "{help}");
}

#[test]
fn desktop_offline_reports_how_to_install_when_no_active_release_exists() {
    let temp = TempDir::new().unwrap();
    let workspace = temp.path().join("workspace");
    std::fs::create_dir(&workspace).unwrap();

    let output = morphir_command()
        .args(["desktop", "--offline", workspace.to_str().unwrap()])
        .env("MORPHIR_HOME", temp.path().join("home"))
        .output()
        .expect("failed to run morphir desktop");

    assert!(!output.status.success());
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("Morphir Desktop is not installed"),
        "{stderr}"
    );
    assert!(stderr.contains("morphir tool install desktop"), "{stderr}");
}

fn build_desktop_launch_fixture(fixture_root: &std::path::Path) -> PathBuf {
    let executable_name = if cfg!(windows) {
        "morphir-desktop.exe"
    } else {
        "morphir-desktop"
    };
    let compiled_executable = fixture_root.join(executable_name);
    let fixture_source =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/desktop_launch_fixture.rs");
    let rustc = std::env::var_os("RUSTC").unwrap_or_else(|| "rustc".into());
    let compilation = std::process::Command::new(rustc)
        .arg(&fixture_source)
        .arg("-o")
        .arg(&compiled_executable)
        .output()
        .expect("failed to compile Desktop launch fixture");
    assert!(
        compilation.status.success(),
        "{}",
        String::from_utf8_lossy(&compilation.stderr)
    );

    if cfg!(any(windows, target_os = "macos")) {
        let package = fixture_root.join("morphir-desktop-fixture.zip");
        let file = std::fs::File::create(&package).unwrap();
        let mut archive = zip::ZipWriter::new(file);
        archive
            .start_file(
                if cfg!(target_os = "macos") {
                    "Morphir Desktop.app/Contents/MacOS/morphir-desktop"
                } else {
                    "morphir-desktop.exe"
                },
                zip::write::SimpleFileOptions::default().unix_permissions(0o755),
            )
            .unwrap();
        let bytes = std::fs::read(&compiled_executable).unwrap();
        std::io::Write::write_all(&mut archive, &bytes).unwrap();
        archive.finish().unwrap();
        std::fs::remove_file(compiled_executable).unwrap();
        package
    } else if cfg!(target_os = "linux") {
        let arch = match std::env::consts::ARCH {
            "aarch64" => "arm64",
            "x86_64" => "x64",
            other => panic!("Unsupported Desktop fixture architecture: {other}"),
        };
        let archive_root = format!("morphir-desktop-0.1.0-linux-{arch}");
        let contents = fixture_root.join(&archive_root);
        std::fs::create_dir(&contents).unwrap();
        std::fs::rename(&compiled_executable, contents.join(executable_name)).unwrap();
        // Match electron-builder's tar layout, including a renamed download.
        let package = fixture_root.join("renamed-desktop-fixture.tar.gz");
        let packed = std::process::Command::new("tar")
            .arg("-czf")
            .arg(&package)
            .arg("-C")
            .arg(fixture_root)
            .arg(&archive_root)
            .output()
            .expect("failed to package Linux Desktop fixture with tar");
        assert!(
            packed.status.success(),
            "{}",
            String::from_utf8_lossy(&packed.stderr)
        );
        std::fs::remove_dir_all(contents).unwrap();
        package
    } else {
        compiled_executable
    }
}

fn install_desktop_launch_fixture(
    home: &std::path::Path,
    fixture_root: &std::path::Path,
) -> PathBuf {
    let package = build_desktop_launch_fixture(fixture_root);
    let install = morphir_command()
        .args([
            "tool",
            "install",
            "desktop",
            "--source",
            package.to_str().unwrap(),
            "--channel",
            "developer",
            "--version",
            "0.1.0",
        ])
        .env("MORPHIR_HOME", home)
        .output()
        .expect("failed to install Desktop launch fixture");
    assert!(
        install.status.success(),
        "stdout={} stderr={}",
        String::from_utf8_lossy(&install.stdout),
        String::from_utf8_lossy(&install.stderr)
    );
    package
}

#[test]
fn desktop_launches_the_installed_release_twice_after_its_package_source_is_removed() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let workspace = temp.path().join("sample-workspace");
    std::fs::create_dir(&workspace).unwrap();
    let package_source = install_desktop_launch_fixture(&home, temp.path());
    std::fs::remove_file(&package_source).unwrap();

    for _ in 0..2 {
        let output = morphir_command()
            .args([
                "desktop",
                "--offline",
                "--wait",
                workspace.to_str().unwrap(),
            ])
            .env("MORPHIR_HOME", &home)
            .env("HTTP_PROXY", "http://127.0.0.1:1")
            .env("HTTPS_PROXY", "http://127.0.0.1:1")
            .output()
            .expect("failed to launch installed Desktop fixture");
        assert!(
            output.status.success(),
            "stdout={} stderr={}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }

    assert!(!package_source.exists());
    let ready_events = std::fs::read_to_string(home.join("logs/desktop/fixture.jsonl")).unwrap();
    let ready_events = ready_events
        .lines()
        .map(|line| serde_json::from_str::<serde_json::Value>(line).unwrap())
        .collect::<Vec<_>>();
    assert_eq!(ready_events.len(), 2);
    let first_launch = ready_events[0]["fields"]["launch_id"].as_str().unwrap();
    let second_launch = ready_events[1]["fields"]["launch_id"].as_str().unwrap();
    assert!(first_launch.starts_with("launch-"));
    assert!(
        ready_events[0]["fields"]["parent_operation_id"]
            .as_str()
            .unwrap()
            .starts_with("op-")
    );
    assert_ne!(first_launch, second_launch);

    let captures = std::fs::read_to_string(home.join("launches.txt")).unwrap();
    let expected = format!(
        "{}|{}|1",
        workspace.canonicalize().unwrap().display(),
        home.display()
    );
    assert_eq!(
        captures.lines().collect::<Vec<_>>(),
        vec![expected.as_str(), expected.as_str()]
    );
}

#[test]
fn desktop_preserves_absolute_and_relative_log_directory_overrides() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let workspace = temp.path().join("workspace");
    std::fs::create_dir(&workspace).unwrap();
    install_desktop_launch_fixture(&home, temp.path());

    for configured in [
        temp.path().join("absolute-logs"),
        PathBuf::from("relative-logs"),
    ] {
        let expected = temp.path().join(&configured);
        let output = morphir_command()
            .args([
                "desktop",
                "--offline",
                "--wait",
                workspace.to_str().unwrap(),
            ])
            .env("MORPHIR_HOME", &home)
            .env("MORPHIR_LOG_DIR", &configured)
            .current_dir(temp.path())
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let events = std::fs::read_to_string(expected.join("fixture.jsonl"))
            .expect("Desktop must write readiness in the configured log directory");
        assert!(events.contains("desktop.ready"));
        assert!(!home.join("logs/desktop/fixture.jsonl").exists());
        assert!(!workspace.join("relative-logs").exists());
    }
}

#[test]
fn desktop_wait_returns_the_desktop_process_exit_status() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let workspace = temp.path().join("sample-workspace");
    std::fs::create_dir(&workspace).unwrap();
    let package_source = install_desktop_launch_fixture(&home, temp.path());
    std::fs::remove_file(package_source).unwrap();
    std::fs::write(home.join("fixture-exit-code"), "23").unwrap();

    let output = morphir_command()
        .args([
            "desktop",
            "--offline",
            "--wait",
            workspace.to_str().unwrap(),
        ])
        .env("MORPHIR_HOME", &home)
        .output()
        .expect("failed to launch installed Desktop fixture");

    assert_eq!(
        output.status.code(),
        Some(23),
        "stderr={}",
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn desktop_wait_preserves_exits_before_readiness() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let workspace = temp.path().join("sample-workspace");
    std::fs::create_dir(&workspace).unwrap();
    install_desktop_launch_fixture(&home, temp.path());
    std::fs::write(home.join("fixture-exit-code"), "23").unwrap();
    for readiness in ["silent", "exit"] {
        std::fs::write(home.join("fixture-readiness"), readiness).unwrap();
        let output = morphir_command()
            .args([
                "desktop",
                "--offline",
                "--wait",
                workspace.to_str().unwrap(),
            ])
            .env("MORPHIR_HOME", &home)
            .output()
            .expect("failed to launch installed Desktop fixture");
        assert_eq!(
            output.status.code(),
            Some(23),
            "readiness={readiness}, stderr={}",
            String::from_utf8_lossy(&output.stderr)
        );
    }
}

#[test]
fn local_developer_desktop_uses_verified_tool_lifecycle() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let first = write_local_desktop_package(temp.path(), "0.1.0");
    let install = morphir_command()
        .args([
            "tool",
            "install",
            "desktop",
            "--source",
            first.to_str().unwrap(),
            "--channel",
            "developer",
            "--version",
            "0.1.0",
        ])
        .env("MORPHIR_HOME", &home)
        .output()
        .unwrap();
    assert!(
        install.status.success(),
        "{}",
        String::from_utf8_lossy(&install.stderr)
    );
    assert!(home.join("catalog/tools.json").exists());
    assert!(!home.join("tools.json").exists());

    let list = morphir_command()
        .args(["tool", "list", "--json"])
        .env("MORPHIR_HOME", &home)
        .output()
        .unwrap();
    assert!(list.status.success());
    let listed: serde_json::Value = serde_json::from_slice(&list.stdout).unwrap();
    assert_eq!(listed[0]["id"], "desktop");
    assert_eq!(listed[0]["version"], "0.1.0");
    assert_eq!(listed[0]["channel"], "developer");
    assert_eq!(listed[0]["trustPolicy"], "local-unsigned");
    assert!(listed[0]["digest"].as_str().unwrap().len() == 64);

    let catalog: serde_json::Value =
        serde_json::from_slice(&std::fs::read(home.join("catalog/tools.json")).unwrap()).unwrap();
    let launch_path = catalog["tools"][0]["active"]["storePath"].as_str().unwrap();
    std::fs::write(home.join(launch_path), b"corrupt").unwrap();
    let repair = morphir_command()
        .args([
            "tool",
            "repair",
            "desktop",
            "--source",
            first.to_str().unwrap(),
        ])
        .env("MORPHIR_HOME", &home)
        .output()
        .unwrap();
    assert!(
        repair.status.success(),
        "{}",
        String::from_utf8_lossy(&repair.stderr)
    );

    let second = write_local_desktop_package(temp.path(), "0.2.0");
    let update = morphir_command()
        .args([
            "tool",
            "update",
            "desktop",
            "--source",
            second.to_str().unwrap(),
            "--channel",
            "developer",
            "--version",
            "0.2.0",
        ])
        .env("MORPHIR_HOME", &home)
        .output()
        .unwrap();
    assert!(
        update.status.success(),
        "{}",
        String::from_utf8_lossy(&update.stderr)
    );

    let rollback = morphir_command()
        .args(["tool", "rollback", "desktop"])
        .env("MORPHIR_HOME", &home)
        .output()
        .unwrap();
    assert!(
        rollback.status.success(),
        "{}",
        String::from_utf8_lossy(&rollback.stderr)
    );
    assert!(String::from_utf8_lossy(&rollback.stdout).contains("0.1.0"));

    let uninstall = morphir_command()
        .args(["tool", "uninstall", "desktop"])
        .env("MORPHIR_HOME", &home)
        .output()
        .unwrap();
    assert!(
        uninstall.status.success(),
        "{}",
        String::from_utf8_lossy(&uninstall.stderr)
    );
    let catalog: serde_json::Value =
        serde_json::from_slice(&std::fs::read(home.join("catalog/tools.json")).unwrap()).unwrap();
    assert!(catalog["tools"].as_array().unwrap().is_empty());
}

#[test]
fn local_desktop_source_requires_explicit_developer_trust_policy() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let package = write_local_desktop_package(temp.path(), "0.1.0");
    let rejected = morphir_command()
        .args([
            "tool",
            "install",
            "desktop",
            "--source",
            package.to_str().unwrap(),
            "--channel",
            "stable",
            "--version",
            "0.1.0",
        ])
        .env("MORPHIR_HOME", &home)
        .output()
        .unwrap();

    assert!(!rejected.status.success());
    assert!(String::from_utf8_lossy(&rejected.stderr).contains("--channel developer"));
    assert!(!home.join("catalog/tools.json").exists());
}

#[test]
fn local_desktop_install_and_update_enforce_distinct_preconditions() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let package = write_local_desktop_package(temp.path(), "0.1.0");
    let local_args = [
        "desktop",
        "--source",
        package.to_str().unwrap(),
        "--channel",
        "developer",
        "--version",
        "0.1.0",
    ];

    let update_missing = morphir_command()
        .arg("tool")
        .arg("update")
        .args(local_args)
        .env("MORPHIR_HOME", &home)
        .output()
        .unwrap();
    assert!(!update_missing.status.success());
    assert!(String::from_utf8_lossy(&update_missing.stderr).contains("not installed"));

    let install = morphir_command()
        .arg("tool")
        .arg("install")
        .args(local_args)
        .env("MORPHIR_HOME", &home)
        .output()
        .unwrap();
    assert!(install.status.success());

    let install_again = morphir_command()
        .arg("tool")
        .arg("install")
        .args(local_args)
        .env("MORPHIR_HOME", &home)
        .output()
        .unwrap();
    assert!(!install_again.status.success());
    assert!(String::from_utf8_lossy(&install_again.stderr).contains("already installed"));
}

fn write_test_index(
    directory: &std::path::Path,
    id: &str,
    name: &str,
    version: &str,
    bytes: &[u8],
) -> TestIndex {
    write_test_index_with_frontend(directory, id, name, version, bytes, ("test", ".test", "4"))
}

fn write_elm_test_index(
    directory: &std::path::Path,
    id: &str,
    name: &str,
    version: &str,
    bytes: &[u8],
) -> TestIndex {
    write_test_index_with_frontend(directory, id, name, version, bytes, ("elm", ".elm", "3"))
}

fn write_test_index_with_frontend(
    directory: &std::path::Path,
    id: &str,
    name: &str,
    version: &str,
    bytes: &[u8],
    frontend: (&str, &str, &str),
) -> TestIndex {
    let (language, file_extension, ir_version) = frontend;
    let root = directory.join("index");
    let filename = if cfg!(windows) {
        format!("{id}.exe")
    } else {
        id.to_owned()
    };
    let relative_source = format!("artifacts/{filename}");
    let source = root.join(&relative_source);
    std::fs::create_dir_all(source.parent().unwrap()).unwrap();
    std::fs::create_dir_all(root.join("extensions")).unwrap();
    std::fs::write(&source, bytes).unwrap();
    let digest = morphir_distribution::Sha256Digest::of_bytes(bytes).to_string();
    let record = serde_json::json!({
        "schemaVersion": "1.0",
        "id": id,
        "name": name,
        "version": version,
        "channels": ["stable"],
        "mepVersions": ["0.1"],
        "capabilities": ["frontend"],
        "frontend": {
            "languages": [{"id": language, "fileExtensions": [file_extension]}],
            "irVersions": [ir_version],
            "compile": true,
        },
        "artifacts": [{
            "runtime": "process",
            "platform": {
                "os": std::env::consts::OS,
                "arch": std::env::consts::ARCH,
            },
            "source": {"kind": "local-file", "path": relative_source},
            "sha256": digest,
            "filename": filename,
            "args": [],
            "executable": true,
        }],
    });
    std::fs::write(
        root.join("extensions").join(format!("{id}.jsonl")),
        format!("{record}\n"),
    )
    .unwrap();
    TestIndex {
        root,
        source,
        digest,
        filename,
    }
}

fn write_test_release_bundle(directory: &std::path::Path) -> PathBuf {
    let bundle = directory.join("release-bundle");
    let artifact = "morphir-avro.wasm";
    let bytes = b"verified avro wasm bytes";
    let digest = morphir_distribution::Sha256Digest::of_bytes(bytes).to_string();
    std::fs::create_dir_all(&bundle).unwrap();
    std::fs::write(bundle.join(artifact), bytes).unwrap();
    std::fs::write(
        bundle.join(format!("{artifact}.sha256")),
        format!("{digest}  {artifact}\n"),
    )
    .unwrap();
    std::fs::write(
        bundle.join("release.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "schemaVersion": 1,
            "shortId": "avro",
            "extensionId": "morphir-avro",
            "package": "morphir-avro",
            "version": "0.1.0",
            "mepVersions": ["0.1"],
            "runtime": "wasm",
            "targets": ["avro"],
            "irVersions": ["3"],
            "artifact": artifact,
            "sha256": digest,
            "gitCommit": "test-commit"
        }))
        .unwrap(),
    )
    .unwrap();
    bundle
}

#[cfg(unix)]
fn write_backend_test_index(directory: &std::path::Path, bytes: &[u8]) -> TestIndex {
    let root = directory.join("backend-index");
    let filename = "morphir-avro".to_owned();
    let relative_source = format!("artifacts/{filename}");
    let source = root.join(&relative_source);
    std::fs::create_dir_all(source.parent().unwrap()).unwrap();
    std::fs::create_dir_all(root.join("extensions")).unwrap();
    std::fs::write(&source, bytes).unwrap();
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(&source, std::fs::Permissions::from_mode(0o700)).unwrap();
    let digest = morphir_distribution::Sha256Digest::of_bytes(bytes).to_string();
    let record = serde_json::json!({
        "schemaVersion": "1.0",
        "id": "morphir-avro",
        "name": "Morphir Avro",
        "version": "1.2.3",
        "channels": ["stable"],
        "mepVersions": ["0.1"],
        "capabilities": ["backend"],
        "backend": {
            "targets": ["avro"],
            "irVersions": ["3"]
        },
        "artifacts": [{
            "runtime": "process",
            "platform": {
                "os": std::env::consts::OS,
                "arch": std::env::consts::ARCH,
            },
            "source": {"kind": "local-file", "path": relative_source},
            "sha256": digest,
            "filename": filename,
            "args": [],
            "executable": true,
        }],
    });
    std::fs::write(
        root.join("extensions/morphir-avro.jsonl"),
        format!("{record}\n"),
    )
    .unwrap();
    TestIndex {
        root,
        source,
        digest,
        filename,
    }
}

#[cfg(unix)]
fn write_gleam_frontend_test_index(directory: &std::path::Path, bytes: &[u8]) -> TestIndex {
    let root = directory.join("gleam-frontend-index");
    let filename = "morphir-installed-gleam".to_owned();
    let relative_source = format!("artifacts/{filename}");
    let source = root.join(&relative_source);
    std::fs::create_dir_all(source.parent().unwrap()).unwrap();
    std::fs::create_dir_all(root.join("extensions")).unwrap();
    std::fs::write(&source, bytes).unwrap();
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(&source, std::fs::Permissions::from_mode(0o700)).unwrap();
    let digest = morphir_distribution::Sha256Digest::of_bytes(bytes).to_string();
    let record = serde_json::json!({
        "schemaVersion": "1.0",
        "id": "morphir-installed-gleam",
        "name": "Installed Gleam override",
        "version": "1.2.3",
        "channels": ["stable"],
        "mepVersions": ["0.1"],
        "capabilities": ["frontend"],
        "frontend": {
            "languages": [{"id": "gleam", "fileExtensions": [".gleam"]}],
            "irVersions": ["4.0.0"]
        },
        "artifacts": [{
            "runtime": "process",
            "platform": {
                "os": std::env::consts::OS,
                "arch": std::env::consts::ARCH,
            },
            "source": {"kind": "local-file", "path": relative_source},
            "sha256": digest,
            "filename": filename,
            "args": [],
            "executable": true,
        }],
    });
    std::fs::write(
        root.join("extensions/morphir-installed-gleam.jsonl"),
        format!("{record}\n"),
    )
    .unwrap();
    TestIndex {
        root,
        source,
        digest,
        filename,
    }
}

fn run_morphir(
    arguments: &[&str],
    morphir_home: &std::path::Path,
    working_directory: &std::path::Path,
) -> std::process::Output {
    morphir_command()
        .args(arguments)
        .env("MORPHIR_HOME", morphir_home)
        .current_dir(working_directory)
        .output()
        .expect("failed to run morphir binary")
}

fn write_gleam_project(project_root: &std::path::Path) -> PathBuf {
    // Pin project outputs locally; discovery otherwise inherits an ancestor's
    // .morphir directory, including one in the developer's home directory.
    std::fs::create_dir_all(project_root.join(".morphir")).unwrap();
    let src_dir = project_root.join("src");
    std::fs::create_dir_all(&src_dir).unwrap();
    std::fs::write(
        src_dir.join("main.gleam"),
        "pub fn hello() {\n  \"world\"\n}\n",
    )
    .unwrap();
    std::fs::write(
        project_root.join("morphir.toml"),
        r#"[project]
name = "example/hello"
version = "1.0.0"
source_directory = "src"

[frontend]
language = "gleam"

[codegen]
targets = ["gleam"]
"#,
    )
    .unwrap();
    src_dir
}

fn v4_module_with_hello_value() -> serde_json::Value {
    use indexmap::IndexMap;
    use morphir_core::ir::v4::{
        Access, AccessControlled, Documented, Literal, ModuleDefinition, Type, TypeAttributes,
        Value, ValueAttributes, ValueDefinition,
    };

    serde_json::to_value(AccessControlled {
        access: Access::Public,
        value: ModuleDefinition {
            types: IndexMap::new(),
            values: IndexMap::from([(
                "hello".into(),
                AccessControlled {
                    access: Access::Public,
                    value: Documented::new(
                        None,
                        ValueDefinition::new(
                            vec![],
                            Type::unit(TypeAttributes::default()),
                            Value::literal(
                                ValueAttributes::default(),
                                Literal::String("world".into()),
                            ),
                        ),
                    ),
                },
            )]),
            doc: None,
        },
    })
    .unwrap()
}

fn add_test_repository(
    name: &str,
    index: &std::path::Path,
    morphir_home: &std::path::Path,
    working_directory: &std::path::Path,
) -> std::process::Output {
    run_morphir(
        &[
            "extension",
            "repository",
            "add",
            name,
            "--directory",
            index.to_str().unwrap(),
        ],
        morphir_home,
        working_directory,
    )
}

fn read_cli_log_events(morphir_home: &std::path::Path) -> Vec<serde_json::Value> {
    std::fs::read_dir(morphir_home.join("logs/cli"))
        .unwrap()
        .filter_map(Result::ok)
        .flat_map(|entry| std::fs::read_dir(entry.path()).into_iter().flatten())
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| {
            path.extension()
                .is_some_and(|extension| extension == "jsonl")
        })
        .flat_map(|path| {
            std::fs::read_to_string(path)
                .unwrap()
                .lines()
                .filter_map(|line| serde_json::from_str::<serde_json::Value>(line).ok())
                .collect::<Vec<_>>()
        })
        .collect()
}

#[test]
fn ui_help_documents_workspace_and_host_options() {
    let temp = TempDir::new().unwrap();
    let output = run_morphir(&["ui", "--help"], &temp.path().join("home"), temp.path());
    let help = String::from_utf8_lossy(&output.stdout);
    let executable = if cfg!(windows) {
        "morphir.exe"
    } else {
        "morphir"
    };

    assert!(output.status.success());
    assert!(help.contains(&format!("Usage: {executable} ui [OPTIONS] [WORKSPACE]")));
    assert!(help.contains("--workspace-extension <ID>"));
    assert!(help.contains("--no-open"));
}

#[test]
fn ui_rejects_files_before_printing_a_launch_url() {
    let temp = TempDir::new().unwrap();
    let file = temp.path().join("morphir.json");
    std::fs::write(&file, "{}").unwrap();
    let output = run_morphir(
        &["ui", file.to_str().unwrap(), "--no-open"],
        &temp.path().join("home"),
        temp.path(),
    );
    let stderr = String::from_utf8_lossy(&output.stderr);

    assert!(!output.status.success());
    assert!(stderr.contains("must be an existing directory"));
    assert!(!stderr.contains("/launch?token="));
}

#[test]
fn cache_status_reports_registered_namespaces_and_default_policy() {
    let temp = TempDir::new().unwrap();
    let morphir_home = temp.path().join("home");

    let output = run_morphir(&["cache", "status", "--json"], &morphir_home, temp.path());

    assert!(
        output.status.success(),
        "cache status failed: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let status: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(status["policy"]["maxAgeSeconds"], 30 * 24 * 60 * 60);
    assert_eq!(status["policy"]["maxSizeBytes"], 2_u64 * 1024 * 1024 * 1024);
    assert_eq!(
        status["namespaces"]
            .as_array()
            .unwrap()
            .iter()
            .map(|namespace| namespace["name"].as_str().unwrap())
            .collect::<Vec<_>>(),
        ["desktop", "downloads", "extensions", "indexes"]
    );
    assert_eq!(status["totals"]["knownBytes"], 0);
    assert_eq!(status["totals"]["unclassifiedBytes"], 0);
}

#[test]
fn cache_clean_dry_run_preserves_and_explains_unclassified_content() {
    let temp = TempDir::new().unwrap();
    let morphir_home = temp.path().join("home");
    let unknown = morphir_home
        .join("cache")
        .join("downloads")
        .join("unknown.pkg");
    std::fs::create_dir_all(unknown.parent().unwrap()).unwrap();
    std::fs::write(&unknown, b"unknown").unwrap();

    let output = run_morphir(
        &[
            "cache",
            "clean",
            "--dry-run",
            "--all",
            "--component",
            "downloads",
            "--json",
        ],
        &morphir_home,
        temp.path(),
    );

    assert!(
        output.status.success(),
        "cache clean failed: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(unknown.exists(), "dry-run must not remove unknown content");
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(report["dryRun"], true);
    assert_eq!(report["plan"]["mode"], "all");
    assert_eq!(report["plan"]["unclassifiedBytes"], 7);
    assert_eq!(report["plan"]["reclaimableBytes"], 0);
    assert_eq!(report["plan"]["decisions"][0]["reason"], "unclassified");
}

#[test]
fn cache_clean_reclaims_durably_registered_content() {
    let temp = TempDir::new().unwrap();
    let morphir_home = temp.path().join("home");
    let home =
        morphir_common::home::MorphirHome::resolve_from(Some(morphir_home.as_os_str()), None)
            .unwrap();
    let owned = home.downloads_cache_dir().join("owned.pkg");
    std::fs::create_dir_all(owned.parent().unwrap()).unwrap();
    let mutation = morphir_common::cache_maintenance::CacheOwnershipMutationGuard::begin(
        &home,
        "downloads",
        "owned.pkg",
    )
    .unwrap();
    std::fs::write(&owned, b"owned").unwrap();
    mutation.finish(1).unwrap();

    let output = run_morphir(
        &[
            "cache",
            "clean",
            "--all",
            "--component",
            "downloads",
            "--json",
        ],
        &morphir_home,
        temp.path(),
    );

    assert!(
        output.status.success(),
        "cache clean failed: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(!owned.exists());
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(report["plan"]["reclaimableBytes"], 5);
    assert_eq!(report["execution"]["removedBytes"], 5);
    assert_eq!(report["execution"]["items"][0]["disposition"], "removed");
    assert!(
        morphir_common::cache_maintenance::load_cache_ownership_registry(&home)
            .unwrap()
            .is_empty()
    );
}

#[test]
fn compile_help_documents_explicit_extension_selection() {
    let temp = TempDir::new().unwrap();
    let output = run_morphir(
        &["compile", "--help"],
        &temp.path().join("home"),
        temp.path(),
    );

    assert!(output.status.success());
    let stdout = String::from_utf8(output.stdout).unwrap();
    assert!(stdout.contains("--extension <EXTENSION>"), "{stdout}");
    assert!(stdout.contains("single-file Elm compilation"), "{stdout}");
    // Clap wraps help to the terminal width, so compare against text with its
    // whitespace collapsed rather than against the wrapped lines.
    let flowed = stdout.split_whitespace().collect::<Vec<_>>().join(" ");
    assert!(
        flowed.contains("Defaults to morphir- followed by the language name"),
        "{stdout}"
    );
    // Deliberately not `morphir-{language}`. Help text is copied verbatim into
    // docs/cli/compile.md, which Docusaurus parses as MDX, where a brace opens a
    // JSX expression and the page fails to render.
    assert!(
        !flowed.contains("morphir-{"),
        "braces in prose help become a JSX expression in the generated docs: {stdout}"
    );
}

#[test]
fn generate_help_documents_repeated_backend_options() {
    let temp = TempDir::new().unwrap();
    let output = run_morphir(
        &["generate", "--help"],
        &temp.path().join("home"),
        temp.path(),
    );

    assert!(output.status.success());
    let stdout = String::from_utf8(output.stdout).unwrap();
    assert!(stdout.contains("--option <KEY=VALUE>"), "{stdout}");
    let flowed = stdout.split_whitespace().collect::<Vec<_>>().join(" ");
    assert!(
        flowed.contains("Override a backend option as KEY=VALUE. May be repeated"),
        "{stdout}"
    );
}

#[test]
fn compile_rejects_an_invalid_explicit_extension_id() {
    let temp = TempDir::new().unwrap();
    let source = temp.path().join("Example.elm");
    std::fs::write(&source, "module Example exposing (value)\n\nvalue = 1\n").unwrap();

    let output = run_morphir(
        &[
            "compile",
            "--input",
            source.to_str().unwrap(),
            "--extension",
            "Morphir Scala Elm",
        ],
        &temp.path().join("home"),
        temp.path(),
    );

    assert!(!output.status.success());
    let stderr = String::from_utf8(output.stderr).unwrap();
    assert!(stderr.contains("Invalid extension id"), "{stderr}");
}

#[test]
fn compile_reports_the_selected_extension_when_it_is_not_installed() {
    let temp = TempDir::new().unwrap();
    let source = temp.path().join("Example.elm");
    std::fs::write(&source, "module Example exposing (value)\n\nvalue = 1\n").unwrap();

    let output = run_morphir(
        &[
            "compile",
            "--input",
            source.to_str().unwrap(),
            "--extension",
            "morphir-scala-elm",
        ],
        &temp.path().join("home"),
        temp.path(),
    );

    assert!(!output.status.success());
    let stderr = String::from_utf8(output.stderr).unwrap();
    let compact_stderr = stderr.split_whitespace().collect::<String>();
    assert!(
        compact_stderr.contains("extensionmorphir-scala-elmisnotinstalled"),
        "{stderr}"
    );
}

#[test]
fn compile_rejects_explicit_extension_selection_on_the_legacy_path() {
    let temp = TempDir::new().unwrap();
    let source = temp.path().join("Example.gleam");
    std::fs::write(&source, "pub fn value() { 1 }\n").unwrap();

    let output = run_morphir(
        &[
            "compile",
            "--language",
            "gleam",
            "--input",
            source.to_str().unwrap(),
            "--extension",
            "morphir-other-gleam",
        ],
        &temp.path().join("home"),
        temp.path(),
    );

    assert!(!output.status.success());
    let stderr = String::from_utf8(output.stderr).unwrap();
    assert!(
        stderr.contains("Explicit extension selection currently requires"),
        "{stderr}"
    );
}

#[test]
fn extension_install_uses_verified_repository_and_list_reports_the_exact_version() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let index = write_test_index(
        temp.path(),
        "morphir-test",
        "Morphir test frontend",
        "1.2.3",
        b"verified executable bytes",
    );
    assert!(
        add_test_repository("local-dev", &index.root, &home, temp.path())
            .status
            .success()
    );

    let install = run_morphir(
        &[
            "extension",
            "install",
            "morphir-test",
            "--repository",
            "local-dev",
        ],
        &home,
        temp.path(),
    );
    assert!(
        install.status.success(),
        "install failed: stdout={} stderr={}",
        String::from_utf8_lossy(&install.stdout),
        String::from_utf8_lossy(&install.stderr)
    );
    assert!(
        home.join("store/extensions/sha256")
            .join(&index.digest)
            .join(&index.filename)
            .exists()
    );
    assert!(home.join("catalog/extensions.json").exists());
    assert!(home.join("locks/extensions/morphir-test.json").exists());
    assert!(!home.join("extensions.json").exists());

    let list = run_morphir(&["extension", "list"], &home, temp.path());
    assert!(list.status.success());
    let stdout = String::from_utf8_lossy(&list.stdout);
    assert!(stdout.contains("morphir-test"), "{stdout}");
    assert!(stdout.contains("1.2.3"), "{stdout}");
    assert!(stdout.contains("stable"), "{stdout}");
}

#[test]
fn extension_repository_lifecycle_is_persisted_in_morphir_home() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let index = write_test_index(
        temp.path(),
        "morphir-test",
        "Morphir test frontend",
        "1.2.3",
        b"verified executable bytes",
    );

    let add = run_morphir(
        &[
            "extension",
            "repository",
            "add",
            "local-dev",
            "--directory",
            index.root.to_str().unwrap(),
        ],
        &home,
        temp.path(),
    );
    assert!(
        add.status.success(),
        "add failed: stdout={} stderr={}",
        String::from_utf8_lossy(&add.stdout),
        String::from_utf8_lossy(&add.stderr)
    );
    assert!(home.join("config/extensions/repositories.json").is_file());

    let list = run_morphir(&["extension", "repository", "list"], &home, temp.path());
    let stdout = String::from_utf8_lossy(&list.stdout);
    assert!(list.status.success());
    assert!(stdout.contains("local-dev"), "{stdout}");
    assert!(stdout.contains("enabled"), "{stdout}");
    assert!(stdout.contains("local-directory"), "{stdout}");

    let verify = run_morphir(
        &["extension", "repository", "verify", "local-dev"],
        &home,
        temp.path(),
    );
    assert!(
        verify.status.success(),
        "verify failed: stdout={} stderr={}",
        String::from_utf8_lossy(&verify.stdout),
        String::from_utf8_lossy(&verify.stderr)
    );
    assert!(String::from_utf8_lossy(&verify.stdout).contains("1 release"));

    for action in ["disable", "enable"] {
        let output = run_morphir(
            &["extension", "repository", action, "local-dev"],
            &home,
            temp.path(),
        );
        assert!(output.status.success(), "{action} failed");
    }

    std::fs::remove_dir_all(&index.root).unwrap();
    let inspect = run_morphir(
        &["extension", "repository", "inspect", "local-dev"],
        &home,
        temp.path(),
    );
    assert!(
        inspect.status.success(),
        "inspect should be offline: {}",
        String::from_utf8_lossy(&inspect.stderr)
    );
    assert!(String::from_utf8_lossy(&inspect.stdout).contains("local-dev"));

    let remove = run_morphir(
        &["extension", "repository", "remove", "local-dev"],
        &home,
        temp.path(),
    );
    assert!(remove.status.success());
    assert!(
        !index.root.exists(),
        "remove must not recreate endpoint content"
    );
}

#[test]
fn extension_repository_authoring_and_search_form_a_complete_local_workflow() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let repository = temp.path().join("repository");
    let bundle = write_test_release_bundle(temp.path());

    let init = run_morphir(
        &[
            "extension",
            "repository",
            "init",
            repository.to_str().unwrap(),
        ],
        &home,
        temp.path(),
    );
    assert!(
        init.status.success(),
        "init failed: stdout={} stderr={}",
        String::from_utf8_lossy(&init.stdout),
        String::from_utf8_lossy(&init.stderr)
    );
    assert!(repository.join("artifacts").is_dir());
    assert!(repository.join("extensions").is_dir());

    assert!(
        add_test_repository("local-dev", &repository, &home, temp.path())
            .status
            .success()
    );

    for expected in ["Published", "Already present"] {
        let publish = run_morphir(
            &[
                "extension",
                "repository",
                "publish",
                "local-dev",
                "--bundle",
                bundle.to_str().unwrap(),
            ],
            &home,
            temp.path(),
        );
        assert!(
            publish.status.success(),
            "publish failed: stdout={} stderr={}",
            String::from_utf8_lossy(&publish.stdout),
            String::from_utf8_lossy(&publish.stderr)
        );
        let stdout = String::from_utf8_lossy(&publish.stdout);
        assert!(stdout.contains(expected), "{stdout}");
        assert!(stdout.contains("local-dev/morphir-avro 0.1.0"), "{stdout}");
    }

    let history =
        std::fs::read_to_string(repository.join("extensions/morphir-avro.jsonl")).unwrap();
    assert_eq!(
        history.lines().count(),
        1,
        "repeat publication must be idempotent"
    );
    assert!(repository.join("artifacts/morphir-avro.wasm").is_file());

    let search = run_morphir(&["extension", "search", "avro"], &home, temp.path());
    assert!(
        search.status.success(),
        "search failed: stdout={} stderr={}",
        String::from_utf8_lossy(&search.stdout),
        String::from_utf8_lossy(&search.stderr)
    );
    let stdout = String::from_utf8_lossy(&search.stdout);
    assert!(stdout.contains("local-dev/morphir-avro"), "{stdout}");
    assert!(stdout.contains("Morphir Avro"), "{stdout}");
    assert!(stdout.contains("0.1.0"), "{stdout}");

    let verify = run_morphir(
        &["extension", "repository", "verify", "local-dev"],
        &home,
        temp.path(),
    );
    assert!(verify.status.success());
    assert!(String::from_utf8_lossy(&verify.stdout).contains("1 release"));
}

#[test]
fn extension_search_ignores_disabled_repositories() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let repository = temp.path().join("repository");
    let bundle = write_test_release_bundle(temp.path());

    assert!(
        run_morphir(
            &[
                "extension",
                "repository",
                "init",
                repository.to_str().unwrap(),
            ],
            &home,
            temp.path(),
        )
        .status
        .success()
    );
    assert!(
        add_test_repository("local-dev", &repository, &home, temp.path())
            .status
            .success()
    );
    assert!(
        run_morphir(
            &[
                "extension",
                "repository",
                "publish",
                "local-dev",
                "--bundle",
                bundle.to_str().unwrap(),
            ],
            &home,
            temp.path(),
        )
        .status
        .success()
    );
    assert!(
        run_morphir(
            &["extension", "repository", "disable", "local-dev"],
            &home,
            temp.path(),
        )
        .status
        .success()
    );

    let search = run_morphir(&["extension", "search", "avro"], &home, temp.path());
    assert!(search.status.success());
    assert_eq!(
        String::from_utf8_lossy(&search.stdout),
        "No extensions found for 'avro'.\n"
    );
}

#[test]
fn extension_repository_publication_and_search_write_correlated_events() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let repository = temp.path().join("repository");
    let bundle = write_test_release_bundle(temp.path());

    assert!(
        run_morphir(
            &[
                "extension",
                "repository",
                "init",
                repository.to_str().unwrap(),
            ],
            &home,
            temp.path(),
        )
        .status
        .success()
    );
    assert!(
        add_test_repository("local-dev", &repository, &home, temp.path())
            .status
            .success()
    );

    for arguments in [
        vec![
            "extension",
            "repository",
            "publish",
            "local-dev",
            "--bundle",
            bundle.to_str().unwrap(),
        ],
        vec!["extension", "search", "avro"],
    ] {
        let output = morphir_command()
            .args(arguments)
            .env("MORPHIR_HOME", &home)
            .env("MORPHIR_LOG_FILE", "true")
            .env("MORPHIR_LOGGING__FILE_LEVEL", "info")
            .current_dir(temp.path())
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "command failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    let events = read_cli_log_events(&home);
    let publication = events
        .iter()
        .find(|event| {
            event["fields"]["event_name"] == "extension.repository.publish"
                && event["fields"]["operation_id"].is_string()
        })
        .expect("publication should emit a correlated structured event");
    assert_eq!(publication["fields"]["repository"], "local-dev");
    assert_eq!(publication["fields"]["extension"], "morphir-avro");
    assert_eq!(publication["fields"]["status"], "published");

    let search = events
        .iter()
        .find(|event| {
            event["fields"]["event_name"] == "extension.catalog.search"
                && event["fields"]["operation_id"].is_string()
        })
        .expect("search should emit a correlated structured event");
    assert_eq!(search["fields"]["query"], "avro");
    assert_eq!(search["fields"]["result_count"], 1);
}

#[test]
fn extension_repository_operations_write_correlated_structured_events() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let index = write_test_index(
        temp.path(),
        "morphir-test",
        "Morphir test frontend",
        "1.2.3",
        b"verified executable bytes",
    );
    let output = morphir_command()
        .args([
            "extension",
            "repository",
            "add",
            "local-dev",
            "--directory",
            index.root.to_str().unwrap(),
        ])
        .env("MORPHIR_HOME", &home)
        .env("MORPHIR_LOG_FILE", "true")
        .env("MORPHIR_LOGGING__FILE_LEVEL", "info")
        .current_dir(temp.path())
        .output()
        .unwrap();
    assert!(output.status.success());

    let event = read_cli_log_events(&home)
        .into_iter()
        .find(|event| {
            event["fields"]["event_name"] == "extension.repository.add"
                && event["fields"]["operation_id"].is_string()
        })
        .expect("repository add should emit a structured event");
    assert_eq!(event["fields"]["repository"], "local-dev");
    assert_eq!(event["fields"]["endpoint_kind"], "local-directory");
    assert_eq!(event["fields"]["state"], "enabled");
    assert!(event["fields"]["operation_id"].is_string());
}

#[test]
fn extension_install_resolves_from_a_named_repository() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let index = write_test_index(
        temp.path(),
        "morphir-test",
        "Morphir test frontend",
        "1.2.3",
        b"verified executable bytes",
    );
    let add = run_morphir(
        &[
            "extension",
            "repository",
            "add",
            "local-dev",
            "--directory",
            index.root.to_str().unwrap(),
        ],
        &home,
        temp.path(),
    );
    assert!(add.status.success());

    let install = run_morphir(
        &[
            "extension",
            "install",
            "morphir-test",
            "--repository",
            "local-dev",
        ],
        &home,
        temp.path(),
    );

    assert!(
        install.status.success(),
        "install failed: stdout={} stderr={}",
        String::from_utf8_lossy(&install.stdout),
        String::from_utf8_lossy(&install.stderr)
    );
    assert!(home.join("catalog/extensions.json").is_file());
}

#[test]
fn extension_install_requires_one_unambiguous_source() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let no_source = run_morphir(
        &["extension", "install", "morphir-test"],
        &home,
        temp.path(),
    );
    assert!(!no_source.status.success());
    assert!(
        String::from_utf8_lossy(&no_source.stderr).contains("--repository"),
        "{}",
        String::from_utf8_lossy(&no_source.stderr)
    );
}

#[test]
fn extension_list_reports_the_native_gleam_frontend_and_backend() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");

    let list = run_morphir(&["extension", "list"], &home, temp.path());

    assert!(list.status.success());
    let stdout = String::from_utf8_lossy(&list.stdout);
    assert!(stdout.contains("Builtin Extensions"), "{stdout}");
    assert!(stdout.contains("morphir-gleam-binding"), "{stdout}");
    assert!(stdout.contains("Morphir Gleam Binding"), "{stdout}");
    assert!(stdout.contains("frontend: gleam"), "{stdout}");
    assert!(stdout.contains("backend: gleam"), "{stdout}");
    assert!(stdout.contains("native-direct"), "{stdout}");
    assert!(
        stdout.contains("No verified extensions installed"),
        "{stdout}"
    );
}

#[test]
fn extension_install_rejects_source_tampering_without_activating_a_catalog_entry() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let index = write_test_index(
        temp.path(),
        "morphir-test",
        "Morphir test frontend",
        "1.2.3",
        b"original bytes",
    );
    std::fs::write(&index.source, b"tampered bytes").unwrap();
    assert!(
        add_test_repository("local-dev", &index.root, &home, temp.path())
            .status
            .success()
    );

    let install = run_morphir(
        &[
            "extension",
            "install",
            "morphir-test",
            "--repository",
            "local-dev",
        ],
        &home,
        temp.path(),
    );
    assert!(!install.status.success());
    assert!(!home.join("catalog/extensions.json").exists());
    let stderr = String::from_utf8_lossy(&install.stderr);
    assert!(stderr.contains("digest"), "{stderr}");
}

#[test]
fn extension_selection_flags_are_mutually_exclusive() {
    let temp = TempDir::new().unwrap();
    let index = write_test_index(
        temp.path(),
        "morphir-test",
        "Morphir test frontend",
        "1.0.0",
        b"extension bytes",
    );
    let home = temp.path().join("home");
    assert!(
        add_test_repository("local-dev", &index.root, &home, temp.path())
            .status
            .success()
    );
    let output = run_morphir(
        &[
            "extension",
            "install",
            "morphir-test",
            "--repository",
            "local-dev",
            "--channel",
            "preview",
            "--version",
            "1.0.0",
        ],
        &home,
        temp.path(),
    );
    assert!(!output.status.success());
    assert!(
        String::from_utf8_lossy(&output.stderr).contains("cannot be used with"),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn extension_update_re_resolves_to_an_exact_version() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let first = write_test_index(
        &temp.path().join("first"),
        "morphir-test",
        "Morphir test frontend",
        "1.2.3",
        b"version one",
    );
    let second = write_test_index(
        &temp.path().join("second"),
        "morphir-test",
        "Morphir test frontend",
        "2.0.0",
        b"version two",
    );
    assert!(
        add_test_repository("first", &first.root, &home, temp.path())
            .status
            .success()
    );
    assert!(
        add_test_repository("second", &second.root, &home, temp.path())
            .status
            .success()
    );
    let install = run_morphir(
        &[
            "extension",
            "install",
            "morphir-test",
            "--repository",
            "first",
            "--version",
            "1.2.3",
        ],
        &home,
        temp.path(),
    );
    assert!(install.status.success());

    let update = run_morphir(
        &[
            "extension",
            "update",
            "morphir-test",
            "--repository",
            "second",
            "--version",
            "2.0.0",
        ],
        &home,
        temp.path(),
    );
    assert!(
        update.status.success(),
        "update failed: stdout={} stderr={}",
        String::from_utf8_lossy(&update.stdout),
        String::from_utf8_lossy(&update.stderr)
    );
    let list = run_morphir(&["extension", "list"], &home, temp.path());
    let stdout = String::from_utf8_lossy(&list.stdout);
    assert!(stdout.contains("2.0.0"), "{stdout}");
    assert!(stdout.contains("version 2.0.0"), "{stdout}");
    assert!(!stdout.contains("1.2.3"), "{stdout}");
}

#[test]
fn extension_uninstall_removes_active_state_but_retains_store_bytes() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let index = write_test_index(
        temp.path(),
        "morphir-test",
        "Morphir test frontend",
        "1.2.3",
        b"verified executable bytes",
    );
    assert!(
        add_test_repository("local-dev", &index.root, &home, temp.path())
            .status
            .success()
    );
    let install = run_morphir(
        &[
            "extension",
            "install",
            "morphir-test",
            "--repository",
            "local-dev",
        ],
        &home,
        temp.path(),
    );
    assert!(install.status.success());
    let stored = home
        .join("store/extensions/sha256")
        .join(&index.digest)
        .join(&index.filename);
    assert!(stored.exists());

    let uninstall = run_morphir(
        &["extension", "uninstall", "morphir-test"],
        &home,
        temp.path(),
    );

    assert!(
        uninstall.status.success(),
        "uninstall failed: stdout={} stderr={}",
        String::from_utf8_lossy(&uninstall.stdout),
        String::from_utf8_lossy(&uninstall.stderr)
    );
    let catalog = std::fs::read_to_string(home.join("catalog/extensions.json")).unwrap();
    assert!(!catalog.contains("morphir-test"), "{catalog}");
    assert!(!home.join("locks/extensions/morphir-test.json").exists());
    assert!(stored.exists());
}

#[test]
#[ignore = "requires the real Bun-built morphir-elm-extension executable"]
fn real_installed_morphir_elm_is_verified_and_activates_offline() {
    verify_real_installed_elm_provider(
        "MORPHIR_ELM_EXTENSION_BIN",
        "morphir-elm",
        "Morphir Elm frontend",
        "2.100.0",
        false,
    );
}

#[test]
#[ignore = "requires the real GraalVM-built morphir-scala-elm executable"]
fn real_installed_morphir_scala_elm_is_selected_and_activates_offline() {
    let version = std::env::var("MORPHIR_SCALA_ELM_EXTENSION_VERSION")
        .expect("set MORPHIR_SCALA_ELM_EXTENSION_VERSION to the packaged extension version");
    verify_real_installed_elm_provider(
        "MORPHIR_SCALA_ELM_EXTENSION_BIN",
        "morphir-scala-elm",
        "Morphir Scala Elm frontend",
        &version,
        true,
    );
}

fn verify_real_installed_elm_provider(
    executable_environment_variable: &str,
    extension_id: &str,
    extension_name: &str,
    version: &str,
    select_explicitly: bool,
) {
    let executable = std::env::var_os(executable_environment_variable)
        .map(PathBuf::from)
        .unwrap_or_else(|| panic!("set {executable_environment_variable} to the extension"));
    let bytes = std::fs::read(&executable).unwrap();
    let temp = TempDir::new().unwrap();

    let tamper_case = temp.path().join("source-tamper");
    let tampered_home = tamper_case.join("home");
    let tampered_index =
        write_elm_test_index(&tamper_case, extension_id, extension_name, version, &bytes);
    std::fs::write(&tampered_index.source, b"tampered source bytes").unwrap();
    assert!(
        add_test_repository(
            "tampered",
            &tampered_index.root,
            &tampered_home,
            &tamper_case,
        )
        .status
        .success()
    );
    let rejected = run_morphir(
        &[
            "extension",
            "install",
            extension_id,
            "--repository",
            "tampered",
            "--version",
            version,
        ],
        &tampered_home,
        &tamper_case,
    );
    assert!(!rejected.status.success());
    assert!(!tampered_home.join("catalog/extensions.json").exists());

    let project = temp.path().join("offline-project");
    let home = project.join("home");
    std::fs::create_dir_all(&project).unwrap();
    let index = write_elm_test_index(&project, extension_id, extension_name, version, &bytes);
    assert!(
        add_test_repository("local-dev", &index.root, &home, &project)
            .status
            .success()
    );
    let install = run_morphir(
        &[
            "extension",
            "install",
            extension_id,
            "--repository",
            "local-dev",
            "--version",
            version,
        ],
        &home,
        &project,
    );
    assert!(
        install.status.success(),
        "install failed: {}",
        String::from_utf8_lossy(&install.stderr)
    );
    let catalog = std::fs::read_to_string(home.join("catalog/extensions.json")).unwrap();
    let lock = std::fs::read_to_string(
        home.join("locks/extensions")
            .join(format!("{extension_id}.json")),
    )
    .unwrap();
    assert!(catalog.contains(version));
    assert!(catalog.contains(&index.digest));
    assert!(lock.contains(version));
    assert!(lock.contains(r#""kind": "exact""#), "{lock}");
    let installed_path = home
        .join("store/extensions/sha256")
        .join(&index.digest)
        .join(&index.filename);
    assert_eq!(std::fs::read(&installed_path).unwrap(), bytes);

    std::fs::remove_dir_all(&index.root).unwrap();
    let source = project.join("Example.elm");
    let output_path = project.join("morphir-ir.json");
    std::fs::write(
        &source,
        "module Example exposing (add)\n\nadd : Int -> Int -> Int\nadd left right = left + right\n",
    )
    .unwrap();
    let mut compile_arguments = vec![
        "compile",
        "--language",
        "elm",
        "--input",
        source.to_str().unwrap(),
        "--output",
        output_path.to_str().unwrap(),
    ];
    if select_explicitly {
        compile_arguments.extend_from_slice(&["--extension", extension_id]);
    }
    let compile = run_morphir(&compile_arguments, &home, &project);
    assert!(
        compile.status.success(),
        "offline compile failed: stdout={} stderr={}",
        String::from_utf8_lossy(&compile.stdout),
        String::from_utf8_lossy(&compile.stderr)
    );
    assert!(output_path.exists());
    let ir: serde_json::Value =
        serde_json::from_slice(&std::fs::read(&output_path).unwrap()).unwrap();
    assert_eq!(ir["formatVersion"], 3, "{ir}");

    std::fs::write(&installed_path, b"tampered installed bytes").unwrap();
    let rejected = run_morphir(&compile_arguments, &home, &project);
    assert!(!rejected.status.success());
    assert!(
        String::from_utf8_lossy(&rejected.stderr).contains("digest"),
        "{}",
        String::from_utf8_lossy(&rejected.stderr)
    );
}

#[test]
fn gleam_compile_uses_the_native_frontend_and_writes_valid_v4_ir() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let project = temp.path().join("project");
    // Reproduce the developer-home layout without relying on the host machine.
    let ancestor_morphir = temp.path().join(".morphir");
    std::fs::create_dir(&ancestor_morphir).unwrap();
    write_gleam_project(&project);

    let compile = run_morphir(&["gleam", "compile"], &home, &project);

    assert!(
        compile.status.success(),
        "compile failed: stdout={} stderr={}",
        String::from_utf8_lossy(&compile.stdout),
        String::from_utf8_lossy(&compile.stderr)
    );
    let output = project.join(".morphir/out/example-hello/compile/gleam/morphir-ir.json");
    let bytes = std::fs::read(&output).expect("host should write morphir-ir.json");
    let json: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(json["formatVersion"], 4);
    serde_json::from_slice::<morphir_core::ir::v4::IRFile>(&bytes).unwrap();
    assert!(ancestor_morphir.read_dir().unwrap().next().is_none());
}

#[test]
fn gleam_compile_rejects_a_missing_input_path() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    write_gleam_project(temp.path());
    let missing = temp.path().join("missing");

    let compile = run_morphir(
        &["gleam", "compile", "--input", missing.to_str().unwrap()],
        &home,
        temp.path(),
    );

    assert!(!compile.status.success());
    let stderr = String::from_utf8_lossy(&compile.stderr);
    assert!(
        stderr.contains("Source input") && stderr.contains("does not exist"),
        "{stderr}"
    );
    assert!(stderr.contains("missing"), "{stderr}");
}

#[test]
fn gleam_compile_rejects_an_empty_source_directory() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let src = write_gleam_project(temp.path());
    std::fs::remove_file(src.join("main.gleam")).unwrap();

    let compile = run_morphir(&["gleam", "compile"], &home, temp.path());

    assert!(!compile.status.success());
    let stderr = String::from_utf8_lossy(&compile.stderr);
    let normalized = stderr.to_ascii_lowercase();
    assert!(normalized.contains("gleam source"), "{stderr}");
    assert!(normalized.contains("empty"), "{stderr}");
}

#[test]
#[cfg(unix)]
fn installed_gleam_frontend_overrides_the_native_provider() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    write_gleam_project(temp.path());
    let index = write_gleam_frontend_test_index(
        temp.path(),
        installed_gleam_frontend_process_script().as_bytes(),
    );
    assert!(
        add_test_repository("local-dev", &index.root, &home, temp.path())
            .status
            .success()
    );
    let install = run_morphir(
        &[
            "extension",
            "install",
            "morphir-installed-gleam",
            "--repository",
            "local-dev",
        ],
        &home,
        temp.path(),
    );
    assert!(
        install.status.success(),
        "install failed: stdout={} stderr={}",
        String::from_utf8_lossy(&install.stdout),
        String::from_utf8_lossy(&install.stderr)
    );

    let compile = run_morphir(&["gleam", "compile"], &home, temp.path());

    assert!(
        compile.status.success(),
        "compile failed: stdout={} stderr={}",
        String::from_utf8_lossy(&compile.stdout),
        String::from_utf8_lossy(&compile.stderr)
    );
    let ir: serde_json::Value = serde_json::from_slice(
        &std::fs::read(
            temp.path()
                .join(".morphir/out/example-hello/compile/gleam/morphir-ir.json"),
        )
        .unwrap(),
    )
    .unwrap();
    assert!(
        ir["distribution"]["Library"]["def"]["modules"]
            .get("installed-sentinel")
            .is_some(),
        "installed provider sentinel missing from {ir}"
    );
}

#[test]
fn gleam_generate_accepts_the_compile_output_directory() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    write_gleam_project(temp.path());
    let compile = run_morphir(&["gleam", "compile"], &home, temp.path());
    assert!(
        compile.status.success(),
        "compile failed: {}",
        String::from_utf8_lossy(&compile.stderr)
    );
    let compile_dir = temp.path().join(".morphir/out/example-hello/compile/gleam");

    let generate = run_morphir(
        &[
            "gleam",
            "generate",
            "--input",
            compile_dir.to_str().unwrap(),
        ],
        &home,
        temp.path(),
    );

    assert!(
        generate.status.success(),
        "generate failed: stdout={} stderr={}",
        String::from_utf8_lossy(&generate.stdout),
        String::from_utf8_lossy(&generate.stderr)
    );
    let generated = temp
        .path()
        .join(".morphir/out/example-hello/generate/gleam");
    assert!(
        walkdir::WalkDir::new(&generated)
            .into_iter()
            .filter_map(Result::ok)
            .any(|entry| entry.path().extension().is_some_and(|ext| ext == "gleam")),
        "no Gleam artifact found below {}",
        generated.display()
    );
    assert!(
        !temp.path().join("main.gleam").exists(),
        "the backend published main.gleam outside the host output directory"
    );
}

#[test]
fn gleam_generate_accepts_a_v4_document_tree_directory() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    write_gleam_project(temp.path());
    let document_tree = temp.path().join("document-tree");
    let module_dir = document_tree.join("src/example");
    std::fs::create_dir_all(&module_dir).unwrap();
    std::fs::write(
        document_tree.join("morphir.json"),
        serde_json::to_vec_pretty(&serde_json::json!({"name": "example/hello"})).unwrap(),
    )
    .unwrap();
    std::fs::write(
        module_dir.join("greeting.json"),
        serde_json::to_vec_pretty(&v4_module_with_hello_value()).unwrap(),
    )
    .unwrap();
    let config = temp.path().join("morphir.toml");
    assert!(!document_tree.join("morphir-ir.json").exists());

    let generate = run_morphir(
        &[
            "gleam",
            "generate",
            "--input",
            document_tree.to_str().unwrap(),
            "--config",
            config.to_str().unwrap(),
        ],
        &home,
        &document_tree,
    );

    assert!(
        generate.status.success(),
        "generate failed: stdout={} stderr={}",
        String::from_utf8_lossy(&generate.stdout),
        String::from_utf8_lossy(&generate.stderr)
    );
    let generated = temp
        .path()
        .join(".morphir/out/example-hello/generate/gleam");
    let generated_paths = walkdir::WalkDir::new(&generated)
        .into_iter()
        .filter_map(Result::ok)
        .map(|entry| entry.path().to_path_buf())
        .collect::<Vec<_>>();
    let generated_gleam = generated_paths
        .iter()
        .find(|path| path.extension().is_some_and(|ext| ext == "gleam"));
    assert!(
        generated_gleam.is_some(),
        "no Gleam artifact found below {}; paths={generated_paths:?}; stdout={}; stderr={}",
        generated.display(),
        String::from_utf8_lossy(&generate.stdout),
        String::from_utf8_lossy(&generate.stderr)
    );
    let generated_source = std::fs::read_to_string(generated_gleam.unwrap()).unwrap();
    assert!(
        generated_source.contains("pub fn hello()"),
        "{generated_source}"
    );
    assert!(
        generated_source.contains(r#""world""#),
        "{generated_source}"
    );

    let validation_output = temp.path().join("document-tree-validation");
    let validation = run_morphir(
        &[
            "gleam",
            "compile",
            "--input",
            generated.to_str().unwrap(),
            "--output",
            validation_output.to_str().unwrap(),
        ],
        &home,
        temp.path(),
    );
    assert!(
        validation.status.success(),
        "generated Gleam did not compile: stdout={} stderr={}",
        String::from_utf8_lossy(&validation.stdout),
        String::from_utf8_lossy(&validation.stderr)
    );
    assert!(validation_output.join("morphir-ir.json").is_file());
}

#[test]
fn gleam_roundtrip_uses_project_outputs_and_emits_recompilable_gleam() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    write_gleam_project(temp.path());

    let roundtrip = run_morphir(&["gleam", "roundtrip"], &home, temp.path());

    assert!(
        roundtrip.status.success(),
        "roundtrip failed: stdout={} stderr={}",
        String::from_utf8_lossy(&roundtrip.stdout),
        String::from_utf8_lossy(&roundtrip.stderr)
    );
    let compile_dir = temp.path().join(".morphir/out/example-hello/compile/gleam");
    let generated = temp
        .path()
        .join(".morphir/out/example-hello/generate/gleam");
    assert!(compile_dir.join("morphir-ir.json").is_file());
    assert!(generated.is_dir());
    assert!(
        walkdir::WalkDir::new(&generated)
            .into_iter()
            .filter_map(Result::ok)
            .any(|entry| entry.path().extension().is_some_and(|ext| ext == "gleam"))
    );

    let validation_output = temp.path().join("validation-compile");
    let validation = run_morphir(
        &[
            "gleam",
            "compile",
            "--input",
            generated.to_str().unwrap(),
            "--output",
            validation_output.to_str().unwrap(),
        ],
        &home,
        temp.path(),
    );
    assert!(
        validation.status.success(),
        "generated Gleam did not compile: stdout={} stderr={}",
        String::from_utf8_lossy(&validation.stdout),
        String::from_utf8_lossy(&validation.stderr)
    );
    assert!(validation_output.join("morphir-ir.json").is_file());
}

#[test]
fn gleam_roundtrip_uses_the_package_override_compile_output() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    write_gleam_project(temp.path());

    let roundtrip = run_morphir(
        &["gleam", "roundtrip", "--package-name", "alternate/package"],
        &home,
        temp.path(),
    );

    assert!(
        roundtrip.status.success(),
        "roundtrip failed: stdout={} stderr={}",
        String::from_utf8_lossy(&roundtrip.stdout),
        String::from_utf8_lossy(&roundtrip.stderr)
    );
    assert!(
        temp.path()
            .join(".morphir/out/alternate-package/compile/gleam/morphir-ir.json")
            .is_file()
    );
    let generated = temp
        .path()
        .join(".morphir/out/example-hello/generate/gleam");
    assert!(
        walkdir::WalkDir::new(&generated)
            .into_iter()
            .filter_map(Result::ok)
            .any(|entry| entry.path().extension().is_some_and(|ext| ext == "gleam")),
        "no Gleam artifact found below {}",
        generated.display()
    );
}

#[test]
#[cfg(unix)]
fn generate_routes_exact_v3_string_ir_to_an_installed_provider() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let index = write_backend_test_index(temp.path(), backend_process_script().as_bytes());
    assert!(
        add_test_repository("local-dev", &index.root, &home, temp.path())
            .status
            .success()
    );
    let install = run_morphir(
        &[
            "extension",
            "install",
            "morphir-avro",
            "--repository",
            "local-dev",
        ],
        &home,
        temp.path(),
    );
    assert!(
        install.status.success(),
        "install failed: stdout={} stderr={}",
        String::from_utf8_lossy(&install.stdout),
        String::from_utf8_lossy(&install.stderr)
    );
    let mut ir: serde_json::Value = serde_json::from_str(include_str!(
        "../../../website/static/ir/examples/v3/greeting-example.json"
    ))
    .unwrap();
    ir["formatVersion"] = "3.0.0".into();
    let input = temp.path().join("morphir-ir.json");
    std::fs::write(&input, serde_json::to_vec(&ir).unwrap()).unwrap();
    let config = temp.path().join("morphir.toml");
    std::fs::write(
        &config,
        "[project]\nname = \"test-project\"\nversion = \"1.0.0\"\n\n[codegen]\ntargets = [\"avro\"]\n",
    )
    .unwrap();

    let generated = run_morphir(
        &[
            "generate",
            "--target",
            "avro",
            "--input",
            input.to_str().unwrap(),
            "--config",
            config.to_str().unwrap(),
            "--json",
        ],
        &home,
        temp.path(),
    );

    assert!(
        generated.status.success(),
        "generation failed: stdout={} stderr={}",
        String::from_utf8_lossy(&generated.stdout),
        String::from_utf8_lossy(&generated.stderr)
    );
    let output: serde_json::Value = serde_json::from_slice(&generated.stdout).unwrap();
    assert_eq!(output["success"], true);
    assert_eq!(output["artifacts"], serde_json::json!(["v3-string.avsc"]));
}

#[cfg(unix)]
fn backend_process_script() -> String {
    let python = std::process::Command::new("sh")
        .args(["-c", "command -v python3"])
        .output()
        .unwrap();
    assert!(python.status.success(), "python3 is required for this test");
    let python = String::from_utf8(python.stdout).unwrap();
    format!(
        r#"#!{python}
import json
import sys

def receive():
    length = None
    while True:
        line = sys.stdin.buffer.readline()
        if line in (b"\n", b"\r\n"):
            break
        if not line:
            raise SystemExit(0)
        name, value = line.decode("ascii").split(":", 1)
        if name.lower() == "content-length":
            length = int(value.strip())
    return json.loads(sys.stdin.buffer.read(length))

def send(identifier, result):
    body = json.dumps(
        {{"jsonrpc": "2.0", "id": identifier, "result": result}},
        separators=(",", ":"),
    ).encode()
    sys.stdout.buffer.write(
        b"Content-Length: " + str(len(body)).encode() + b"\r\n\r\n" + body
    )
    sys.stdout.buffer.flush()

while True:
    request = receive()
    method = request["method"]
    if method == "morphir.initialize":
        result = {{
            "protocolVersion": "0.1",
            "extension": {{
                "id": "morphir-avro",
                "name": "Morphir Avro",
                "version": "1.2.3",
                "types": ["backend"],
            }},
            "capabilities": {{
                "backend": {{
                    "targets": ["avro"],
                    "irVersions": ["3"],
                    "generate": True,
                }}
            }},
        }}
    elif method == "morphir.backend.generate":
        normalized = request["params"]["ir"]["formatVersion"] == 3
        result = {{
            "success": normalized,
            "artifacts": [
                {{"path": "v3-string.avsc", "content": "{{}}", "binary": False}}
            ] if normalized else [],
            "diagnostics": [],
        }}
    elif method == "morphir.shutdown":
        result = {{}}
    elif method == "morphir.exit":
        break
    else:
        raise RuntimeError("unexpected method " + method)
    if "id" in request:
        send(request["id"], result)
"#,
        python = python.trim()
    )
}

#[cfg(unix)]
fn installed_gleam_frontend_process_script() -> String {
    let python = std::process::Command::new("sh")
        .args(["-c", "command -v python3"])
        .output()
        .unwrap();
    assert!(python.status.success(), "python3 is required for this test");
    let python = String::from_utf8(python.stdout).unwrap();
    format!(
        r#"#!{python}
import json
import sys

def receive():
    length = None
    while True:
        line = sys.stdin.buffer.readline()
        if line in (b"\n", b"\r\n"):
            break
        if not line:
            raise SystemExit(0)
        name, value = line.decode("ascii").split(":", 1)
        if name.lower() == "content-length":
            length = int(value.strip())
    return json.loads(sys.stdin.buffer.read(length))

def send(identifier, result):
    body = json.dumps(
        {{"jsonrpc": "2.0", "id": identifier, "result": result}},
        separators=(",", ":"),
    ).encode()
    sys.stdout.buffer.write(
        b"Content-Length: " + str(len(body)).encode() + b"\r\n\r\n" + body
    )
    sys.stdout.buffer.flush()

while True:
    request = receive()
    method = request["method"]
    if method == "morphir.initialize":
        result = {{
            "protocolVersion": "0.1",
            "extension": {{
                "id": "morphir-installed-gleam",
                "name": "Installed Gleam override",
                "version": "1.2.3",
                "types": ["frontend"],
            }},
            "capabilities": {{
                "frontend": {{
                    "languages": [{{
                        "id": "gleam",
                        "fileExtensions": [".gleam"],
                    }}],
                    "irVersions": ["4.0.0"],
                    "compile": True,
                    "incremental": False,
                    "fragments": False,
                }}
            }},
        }}
    elif method == "morphir.frontend.compile":
        package_name = request["params"]["package"]["name"]
        result = {{
            "success": True,
            "irVersion": "4.0.0",
            "ir": {{
                "formatVersion": 4,
                "distribution": {{
                    "Library": {{
                        "packageName": package_name,
                        "dependencies": {{}},
                        "def": {{
                            "modules": {{
                                "installed-sentinel": {{
                                    "access": "Public",
                                    "value": {{"types": {{}}, "values": {{}}}},
                                }}
                            }}
                        }},
                    }}
                }},
            }},
            "diagnostics": [{{
                "severity": "warning",
                "code": "INSTALLED_SENTINEL",
                "message": "installed provider invoked",
            }}],
            "modules": ["installed-sentinel"],
        }}
    elif method == "morphir.shutdown":
        result = {{}}
    elif method == "morphir.exit":
        break
    else:
        raise RuntimeError("unexpected method " + method)
    if "id" in request:
        send(request["id"], result)
"#,
        python = python.trim()
    )
}

#[test]
fn test_config_discovery() {
    use morphir_devkit::discover_config;

    let temp_dir = TempDir::new().unwrap();
    let project_root = temp_dir.path();

    // Create morphir.toml
    std::fs::write(
        project_root.join("morphir.toml"),
        "[project]\nname = \"test\"",
    )
    .unwrap();

    // Test discovery from subdirectory
    let subdir = project_root.join("subdir");
    std::fs::create_dir_all(&subdir).unwrap();

    let config_path = discover_config(&subdir).unwrap();
    assert!(config_path.is_some());
    assert_eq!(config_path.unwrap(), project_root.join("morphir.toml"));
}

#[test]
fn test_morphir_dir_discovery() {
    use morphir_devkit::discover_morphir_dir;

    let temp_dir = TempDir::new().unwrap();
    let project_root = temp_dir.path();

    // Create .morphir directory
    let morphir_dir = project_root.join(".morphir");
    std::fs::create_dir_all(&morphir_dir).unwrap();

    // Test discovery from subdirectory
    let subdir = project_root.join("subdir");
    std::fs::create_dir_all(&subdir).unwrap();

    let discovered = discover_morphir_dir(&subdir);
    assert!(discovered.is_some());
    assert_eq!(discovered.unwrap(), morphir_dir);
}

#[test]
fn test_path_resolution() {
    use morphir_devkit::{resolve_compile_output, resolve_generate_output, sanitize_project_name};

    let morphir_dir = PathBuf::from(".morphir");

    // Test compile output resolution
    let compile_path = resolve_compile_output("My.Project", "gleam", &morphir_dir);
    assert!(compile_path.to_string_lossy().contains("out"));
    assert!(compile_path.to_string_lossy().contains("My.Project"));
    assert!(compile_path.to_string_lossy().contains("compile"));
    assert!(compile_path.to_string_lossy().contains("gleam"));

    // Test generate output resolution
    let generate_path = resolve_generate_output("My.Project", "gleam", &morphir_dir);
    assert!(generate_path.to_string_lossy().contains("out"));
    assert!(generate_path.to_string_lossy().contains("My.Project"));
    assert!(generate_path.to_string_lossy().contains("generate"));
    assert!(generate_path.to_string_lossy().contains("gleam"));

    // Test project name sanitization
    let sanitized = sanitize_project_name("My/Project");
    assert_eq!(sanitized, "My-Project");
}

#[test]
fn test_output_format() {
    use morphir::output::OutputFormat;

    // Test format detection from flags
    assert_eq!(OutputFormat::from_flags(false, false), OutputFormat::Human);
    assert_eq!(OutputFormat::from_flags(true, false), OutputFormat::Json);
    assert_eq!(
        OutputFormat::from_flags(false, true),
        OutputFormat::JsonLines
    );
    assert_eq!(
        OutputFormat::from_flags(true, true),
        OutputFormat::JsonLines // json_lines takes precedence
    );
}

#[test]
fn test_morphir_home_env_var_relocates_home_directory() {
    let temp_dir = TempDir::new().unwrap();
    let morphir_home = temp_dir.path().join("relocated-home");

    let package = write_local_desktop_package(temp_dir.path(), "0.1.0");
    let output = morphir_command()
        .args([
            "tool",
            "install",
            "desktop",
            "--source",
            package.to_str().unwrap(),
            "--channel",
            "developer",
            "--version",
            "0.1.0",
        ])
        .env("MORPHIR_HOME", &morphir_home)
        .env_remove("MORPHIR_LOG_DIR")
        .env("MORPHIR_LOG_FILE", "true")
        .env_remove("MORPHIR_LOGGING__FILE_LEVEL")
        .env_remove("MORPHIR_LOG_FILE_LEVEL")
        .current_dir(temp_dir.path())
        .output()
        .expect("failed to run morphir binary");

    assert!(
        output.status.success(),
        "tool install failed: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        morphir_home.join("catalog/tools.json").exists(),
        "expected verified tool catalog at MORPHIR_HOME ({})",
        morphir_home.display()
    );
    let cli_log_root = morphir_home.join("logs/cli");
    let session_log = std::fs::read_dir(&cli_log_root)
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .filter(|entry| entry.path().is_dir())
        .flat_map(|entry| std::fs::read_dir(entry.path()).into_iter().flatten())
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .find(|path| path.extension().is_some_and(|ext| ext == "jsonl"))
        .unwrap_or_else(|| {
            panic!(
                "expected a CLI JSONL session log beneath {}",
                cli_log_root.display()
            )
        });
    let log = std::fs::read_to_string(&session_log).unwrap();
    let events = log
        .lines()
        .filter_map(|line| serde_json::from_str::<serde_json::Value>(line).ok())
        .collect::<Vec<_>>();
    let first_record = log
        .lines()
        .next()
        .map(str::to_owned)
        .expect("session log should contain its startup event");
    let event: serde_json::Value = serde_json::from_str(&first_record).unwrap();
    assert_eq!(event["fields"]["schema_version"], 1);
    assert_eq!(event["fields"]["component"], "cli");
    assert_eq!(event["fields"]["event_name"], "cli.session.start");
    assert!(event["fields"]["process_id"].is_number());
    assert!(event["fields"]["session_id"].is_string());
    let operation_id = event["fields"]["operation_id"].as_str().unwrap();
    let dispatch = events
        .iter()
        .find(|event| event["fields"]["event_name"] == "cli.command.dispatch")
        .expect("session log should contain an ordinary command event");
    assert!(dispatch["fields"].get("operation_id").is_none());
    assert_eq!(dispatch["span"]["operation_id"], operation_id);

    let shown = morphir_command()
        .args(["diagnostics", "show", "--operation", operation_id, "--json"])
        .env("MORPHIR_HOME", &morphir_home)
        .env("MORPHIR_LOG_FILE", "false")
        .output()
        .expect("failed to query correlated diagnostic events");
    assert!(shown.status.success());
    let shown: serde_json::Value = serde_json::from_slice(&shown.stdout).unwrap();
    assert!(shown["events"].as_array().unwrap().iter().any(|event| {
        event["fields"]["event_name"] == "cli.command.dispatch"
            && event["span"]["operation_id"] == operation_id
    }));
}

#[test]
fn diagnostics_path_reports_shared_log_locations() {
    let temp_dir = TempDir::new().unwrap();
    let morphir_home = temp_dir.path().join("relocated-home");

    let output = morphir_command()
        .args(["diagnostics", "path", "--json"])
        .env("MORPHIR_HOME", &morphir_home)
        .output()
        .expect("failed to run morphir binary");

    assert!(
        output.status.success(),
        "diagnostics path failed: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let paths: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        paths["morphirHome"],
        morphir_home.to_string_lossy().as_ref()
    );
    assert_eq!(
        paths["logs"],
        morphir_home.join("logs").to_string_lossy().as_ref()
    );
    assert_eq!(
        paths["cliLogs"],
        morphir_home
            .join("logs")
            .join("cli")
            .to_string_lossy()
            .as_ref()
    );
    assert_eq!(
        paths["desktopLogs"],
        morphir_home
            .join("logs")
            .join("desktop")
            .to_string_lossy()
            .as_ref()
    );
}

#[test]
fn diagnostics_path_reports_the_effective_cli_log_directory() {
    let temp_dir = TempDir::new().unwrap();
    let morphir_home = temp_dir.path().join("relocated-home");
    let cli_logs = temp_dir.path().join("managed-cli-logs");

    let output = morphir_command()
        .args(["diagnostics", "path", "--json"])
        .env("MORPHIR_HOME", &morphir_home)
        .env("MORPHIR_LOG_DIR", &cli_logs)
        .output()
        .expect("failed to run morphir binary");

    assert!(output.status.success());
    let paths: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(paths["cliLogs"], cli_logs.to_string_lossy().as_ref());
}

#[test]
fn diagnostics_show_finds_correlated_events_and_redacts_legacy_secrets() {
    let temp_dir = TempDir::new().unwrap();
    let morphir_home = temp_dir.path().join("relocated-home");
    let log_dir = morphir_home.join("logs").join("desktop").join("2026-08-30");
    std::fs::create_dir_all(&log_dir).unwrap();
    let operation_id = "op-123e4567-e89b-42d3-a456-426614174000";
    let launch_id = "launch-123e4567-e89b-42d3-a456-426614174001";
    let events = [
        serde_json::json!({
            "timestamp": "2026-08-30T03:04:05Z",
            "level": "INFO",
            "fields": {
                "operation_id": "op-123e4567-e89b-42d3-a456-426614174002",
                "parent_operation_id": operation_id,
                "launch_id": launch_id,
                "event_name": "desktop.ready",
                "authorization": "Bearer SHOULD_NOT_ESCAPE",
                "apiKey": "CAMEL_API_KEY_SHOULD_NOT_ESCAPE",
                "api_key": "SNAKE_API_KEY_SHOULD_NOT_ESCAPE",
                "accessKey": "ACCESS_KEY_SHOULD_NOT_ESCAPE",
                "credential": "CREDENTIAL_SHOULD_NOT_ESCAPE",
                "message": "retry failed? see https://example.com/status",
                "urls": "https://public.example/status then https://alice:hunter2@private.example/artifact",
                "punctuated_urls": "https://public.example/status,https://bob:password@private.example/artifact",
                "auth_message": "Authorization: Basic dXNlcjpwYXNz"
            }
        }),
        serde_json::json!({
            "timestamp": "2026-08-30T03:04:06Z",
            "level": "ERROR",
            "fields": {
                "operation_id": "op-123e4567-e89b-42d3-a456-426614174002",
                "parent_operation_id": operation_id,
                "launch_id": launch_id,
                "event_name": "desktop.crash",
                "error_code": "MORPHIR_DESKTOP_RENDERER_CRASHED",
                "sourceCode": "PRIVATE_PROJECT_CONTENTS"
            }
        }),
        serde_json::json!({
            "timestamp": "2026-08-30T03:04:07Z",
            "level": "INFO",
            "fields": {
                "operation_id": "op-123e4567-e89b-42d3-a456-426614174999",
                "event_name": "unrelated"
            }
        }),
    ];
    std::fs::write(
        log_dir.join("fixture.jsonl"),
        events
            .iter()
            .map(serde_json::Value::to_string)
            .collect::<Vec<_>>()
            .join("\n"),
    )
    .unwrap();

    let output = morphir_command()
        .args(["diagnostics", "show", "--operation", operation_id, "--json"])
        .env("MORPHIR_HOME", &morphir_home)
        .output()
        .expect("failed to run morphir binary");

    assert!(
        output.status.success(),
        "diagnostics show failed: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let shown: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(shown["operationId"], operation_id);
    assert_eq!(shown["events"].as_array().unwrap().len(), 2);
    assert_eq!(shown["events"][0]["fields"]["event_name"], "desktop.ready");
    assert_eq!(shown["events"][0]["fields"]["launch_id"], launch_id);
    assert_eq!(shown["events"][1]["fields"]["event_name"], "desktop.crash");
    assert_eq!(
        shown["events"][1]["fields"]["error_code"],
        "MORPHIR_DESKTOP_RENDERER_CRASHED"
    );
    assert!(shown["events"][1]["fields"].get("sourceCode").is_none());
    assert_eq!(shown["events"][0]["fields"]["authorization"], "[REDACTED]");
    for field in ["apiKey", "api_key", "accessKey", "credential"] {
        assert_eq!(shown["events"][0]["fields"][field], "[REDACTED]");
    }
    assert_eq!(
        shown["events"][0]["fields"]["message"],
        "retry failed? see https://example.com"
    );
    assert_eq!(
        shown["events"][0]["fields"]["urls"],
        "https://public.example then https://[REDACTED]@private.example"
    );
    assert_eq!(
        shown["events"][0]["fields"]["punctuated_urls"],
        "https://public.example,https://[REDACTED]@private.example"
    );
    assert_eq!(shown["events"][0]["fields"]["auth_message"], "[REDACTED]");
    assert!(!String::from_utf8_lossy(&output.stdout).contains("SHOULD_NOT_ESCAPE"));
    assert!(!String::from_utf8_lossy(&output.stdout).contains("PRIVATE_PROJECT_CONTENTS"));
    assert!(!String::from_utf8_lossy(&output.stdout).contains("hunter2"));
    assert!(!String::from_utf8_lossy(&output.stdout).contains("dXNlcjpwYXNz"));
}

#[test]
fn diagnostics_show_honors_the_cli_log_directory_override() {
    let temp_dir = TempDir::new().unwrap();
    let morphir_home = temp_dir.path().join("relocated-home");
    let log_dir = temp_dir.path().join("managed-cli-logs");
    let session_dir = log_dir.join("2026-08-30");
    std::fs::create_dir_all(&session_dir).unwrap();
    let operation_id = "op-123e4567-e89b-42d3-a456-426614174000";
    std::fs::write(
        session_dir.join("fixture.jsonl"),
        serde_json::json!({
            "timestamp": "2026-08-30T03:04:05Z",
            "level": "INFO",
            "fields": {
                "operation_id": operation_id,
                "event_name": "cli.operation.finish"
            }
        })
        .to_string(),
    )
    .unwrap();

    let output = morphir_command()
        .args(["diagnostics", "show", "--operation", operation_id, "--json"])
        .env("MORPHIR_HOME", &morphir_home)
        .env("MORPHIR_LOG_DIR", &log_dir)
        .output()
        .expect("failed to run morphir binary");

    assert!(output.status.success());
    let shown: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(shown["events"].as_array().unwrap().len(), 1);
    assert_eq!(
        shown["events"][0]["fields"]["event_name"],
        "cli.operation.finish"
    );
}

#[test]
fn diagnostics_collect_creates_an_inspectable_sanitized_archive() {
    use std::io::Read as _;

    let temp_dir = TempDir::new().unwrap();
    let morphir_home = temp_dir.path().join("private-user-home").join(".morphir");
    let cli_log_root = temp_dir.path().join("private-user-logs");
    let private_workspace = temp_dir.path().join("private-workspace").join("model.json");
    let log_dir = cli_log_root.join("2026-08-30");
    let desktop_log_dir = morphir_home.join("logs/desktop/2026-08-30");
    std::fs::create_dir_all(&log_dir).unwrap();
    std::fs::create_dir_all(&desktop_log_dir).unwrap();
    let operation_id = "op-123e4567-e89b-42d3-a456-426614174000";
    let launch_id = "launch-123e4567-e89b-42d3-a456-426614174001";
    std::fs::write(
        log_dir.join("fixture.jsonl"),
        serde_json::json!({
            "timestamp": "2026-08-30T03:04:05Z",
            "level": "ERROR",
            "fields": {
                "operation_id": operation_id,
                "event_name": "tool.resolve",
                "path": morphir_home.join("store/tools").to_string_lossy(),
                "log_path": log_dir.join("fixture.jsonl").to_string_lossy(),
                "diagnostic": format!("failed to open {}", private_workspace.display()),
                "token": "BUNDLE_SECRET_SENTINEL",
                "source_url": "https://alice:hunter2@example.com/artifact"
            }
        })
        .to_string(),
    )
    .unwrap();
    std::fs::write(
        desktop_log_dir.join("fixture.jsonl"),
        serde_json::json!({
            "timestamp": "2026-08-30T03:04:06Z",
            "level": "ERROR",
            "fields": {
                "operation_id": "op-123e4567-e89b-42d3-a456-426614174002",
                "parent_operation_id": operation_id,
                "launch_id": launch_id,
                "event_name": "desktop.crash",
                "error_code": "MORPHIR_DESKTOP_RENDERER_CRASHED",
                "sourceCode": "PRIVATE_DESKTOP_PROJECT_CONTENTS",
                "authorization": "Bearer PRIVATE_DESKTOP_CREDENTIAL"
            }
        })
        .to_string(),
    )
    .unwrap();
    let bundle = temp_dir.path().join("diagnostics.zip");

    let output = morphir_command()
        .args([
            "diagnostics",
            "collect",
            "--operation",
            operation_id,
            "--output",
            bundle.to_str().unwrap(),
        ])
        .env("MORPHIR_HOME", &morphir_home)
        .env("MORPHIR_LOG_DIR", &cli_log_root)
        .output()
        .expect("failed to run morphir binary");

    assert!(
        output.status.success(),
        "diagnostics collect failed: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let mut archive = zip::ZipArchive::new(std::fs::File::open(&bundle).unwrap()).unwrap();
    let mut entries = std::collections::BTreeMap::new();
    for index in 0..archive.len() {
        let mut entry = archive.by_index(index).unwrap();
        let mut bytes = Vec::new();
        entry.read_to_end(&mut bytes).unwrap();
        entries.insert(entry.name().to_owned(), bytes);
    }
    assert_eq!(
        entries.keys().cloned().collect::<Vec<_>>(),
        ["events.jsonl", "manifest.json", "system.json"]
    );
    let combined = entries.values().flatten().copied().collect::<Vec<_>>();
    let combined = String::from_utf8(combined).unwrap();
    assert!(!combined.contains("BUNDLE_SECRET_SENTINEL"));
    assert!(!combined.contains("PRIVATE_DESKTOP_PROJECT_CONTENTS"));
    assert!(!combined.contains("PRIVATE_DESKTOP_CREDENTIAL"));
    assert!(!combined.contains("alice"));
    assert!(!combined.contains("hunter2"));
    assert!(combined.contains("https://[REDACTED]@example.com"));
    assert!(!combined.contains(&morphir_home.to_string_lossy().to_string()));
    assert!(combined.contains("$MORPHIR_HOME"));
    assert!(!combined.contains(&cli_log_root.to_string_lossy().to_string()));
    assert!(combined.contains("$MORPHIR_LOG_DIR"));
    assert!(!combined.contains(&private_workspace.to_string_lossy().to_string()));
    assert!(combined.contains("$ABSOLUTE_PATH"));
    assert!(combined.contains(launch_id));
    assert!(combined.contains("desktop.crash"));
    assert!(combined.contains("MORPHIR_DESKTOP_RENDERER_CRASHED"));

    let manifest: serde_json::Value = serde_json::from_slice(&entries["manifest.json"]).unwrap();
    assert_eq!(manifest["operationId"], operation_id);
    for included in manifest["includedFiles"].as_array().unwrap() {
        let path = included["path"].as_str().unwrap();
        assert_eq!(
            included["sha256"],
            morphir_distribution::Sha256Digest::of_bytes(&entries[path]).to_string()
        );
    }
    let original = std::fs::read(&bundle).unwrap();
    let second = morphir_command()
        .args([
            "diagnostics",
            "collect",
            "--operation",
            operation_id,
            "--output",
            bundle.to_str().unwrap(),
        ])
        .env("MORPHIR_HOME", &morphir_home)
        .output()
        .unwrap();
    assert!(!second.status.success());
    assert_eq!(std::fs::read(bundle).unwrap(), original);
}

#[test]
fn failed_operation_reports_correlated_id_and_exact_log_path() {
    let temp_dir = TempDir::new().unwrap();
    let morphir_home = temp_dir.path().join("relocated-home");

    let output = morphir_command()
        .args(["tool", "uninstall", "not-installed"])
        .env("MORPHIR_HOME", &morphir_home)
        .env_remove("MORPHIR_LOG_DIR")
        .env("MORPHIR_LOG_FILE", "true")
        .env("MORPHIR_LOGGING__FILE_LEVEL", "error")
        .output()
        .expect("failed to run morphir binary");

    assert!(!output.status.success());
    let stderr = String::from_utf8_lossy(&output.stderr);
    let operation_id = stderr
        .lines()
        .find_map(|line| line.strip_prefix("Operation ID: "))
        .expect("failure should report an operation ID");
    let log_path = stderr
        .lines()
        .find_map(|line| line.strip_prefix("Log: "))
        .map(PathBuf::from)
        .expect("failure should report its exact log path");

    assert!(log_path.is_file(), "reported log path should exist");
    let events = std::fs::read_to_string(log_path)
        .unwrap()
        .lines()
        .filter_map(|line| serde_json::from_str::<serde_json::Value>(line).ok())
        .collect::<Vec<_>>();
    assert!(
        events
            .iter()
            .any(|event| event["fields"]["event_name"] == "cli.session.start"),
        "session log should retain its correlation start event at error level"
    );
    let finish = events
        .into_iter()
        .find(|event| event["fields"]["event_name"] == "cli.operation.finish")
        .expect("session log should contain the operation finish event");
    assert_eq!(finish["fields"]["operation_id"], operation_id);
    assert!(finish["fields"]["session_id"].is_string());
    assert_eq!(finish["fields"]["outcome"], "failure");
    assert_eq!(finish["fields"]["exit_code"], 1);
    assert!(
        finish["fields"]["diagnostic"]
            .as_str()
            .is_some_and(|diagnostic| diagnostic.contains("not installed")),
        "finish event should retain the failure diagnostic"
    );
}

#[test]
fn clap_parse_failures_report_a_correlated_outcome() {
    let temp_dir = TempDir::new().unwrap();
    let morphir_home = temp_dir.path().join("relocated-home");

    let output = morphir_command()
        .args(["diagnostics", "show"])
        .env("MORPHIR_HOME", &morphir_home)
        .env_remove("MORPHIR_LOG_DIR")
        .env("MORPHIR_LOG_FILE", "true")
        .env("MORPHIR_LOGGING__FILE_LEVEL", "error")
        .output()
        .expect("failed to run morphir binary");

    assert_eq!(output.status.code(), Some(2));
    let stderr = String::from_utf8_lossy(&output.stderr);
    let operation_id = stderr
        .lines()
        .find_map(|line| line.strip_prefix("Operation ID: "))
        .expect("parse failure should report an operation ID");
    let log_path = stderr
        .lines()
        .find_map(|line| line.strip_prefix("Log: "))
        .map(PathBuf::from)
        .expect("parse failure should report its exact log path");

    let finish = std::fs::read_to_string(log_path)
        .unwrap()
        .lines()
        .filter_map(|line| serde_json::from_str::<serde_json::Value>(line).ok())
        .find(|event| event["fields"]["event_name"] == "cli.operation.finish")
        .expect("parse failure should record an operation finish event");
    assert_eq!(finish["fields"]["operation_id"], operation_id);
    assert_eq!(finish["fields"]["outcome"], "failure");
    assert_eq!(finish["fields"]["exit_code"], 2);
    assert!(
        finish["fields"]["diagnostic"]
            .as_str()
            .is_some_and(|diagnostic| diagnostic.contains("--operation"))
    );
}

#[test]
fn successful_fast_paths_record_a_correlated_outcome() {
    for (case, args) in [
        ("help", vec!["--help"]),
        ("version", vec!["version"]),
        ("usage", vec!["usage"]),
        ("no-command", vec![]),
    ] {
        let temp_dir = TempDir::new().unwrap();
        let morphir_home = temp_dir.path().join("morphir-home");

        let output = morphir_command()
            .args(args)
            .env("MORPHIR_HOME", &morphir_home)
            .env_remove("MORPHIR_LOG_DIR")
            .env("MORPHIR_LOG_FILE", "true")
            .env("MORPHIR_LOGGING__FILE_LEVEL", "error")
            .output()
            .unwrap_or_else(|error| panic!("failed to run {case}: {error}"));

        assert!(
            output.status.success(),
            "{case} failed: stdout={} stderr={}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        let log_path = std::fs::read_dir(morphir_home.join("logs/cli"))
            .unwrap()
            .filter_map(Result::ok)
            .flat_map(|entry| std::fs::read_dir(entry.path()).into_iter().flatten())
            .filter_map(Result::ok)
            .map(|entry| entry.path())
            .find(|path| {
                path.extension()
                    .is_some_and(|extension| extension == "jsonl")
            })
            .unwrap_or_else(|| panic!("{case} should create a JSONL session log"));
        let events = std::fs::read_to_string(log_path)
            .unwrap()
            .lines()
            .filter_map(|line| serde_json::from_str::<serde_json::Value>(line).ok())
            .collect::<Vec<_>>();
        let started = events
            .iter()
            .find(|event| event["fields"]["event_name"] == "cli.session.start")
            .unwrap_or_else(|| panic!("{case} should record session start"));
        let finished = events
            .iter()
            .find(|event| event["fields"]["event_name"] == "cli.operation.finish")
            .unwrap_or_else(|| panic!("{case} should record operation finish"));

        assert_eq!(
            finished["fields"]["operation_id"], started["fields"]["operation_id"],
            "{case} should correlate its terminal event"
        );
        assert_eq!(finished["fields"]["outcome"], "success");
        assert_eq!(finished["fields"]["exit_code"], 0);
    }
}

#[test]
fn migrate_converts_a_real_v3_file_to_concrete_v4() {
    let temp_dir = TempDir::new().unwrap();
    let input = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../website/static/ir/examples/v3/greeting-example.json");
    let output_path = temp_dir.path().join("greeting-v4.json");

    let output = morphir_command()
        .args([
            "ir",
            "migrate",
            input.to_str().unwrap(),
            "--output",
            output_path.to_str().unwrap(),
            "--target-version",
            "v4",
        ])
        .output()
        .expect("failed to run morphir binary");

    assert!(
        output.status.success(),
        "migration failed: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let migrated: morphir_core::ir::v4::IRFile =
        serde_json::from_slice(&std::fs::read(output_path).unwrap()).unwrap();
    assert_eq!(
        migrated.format_version,
        morphir_core::ir::v4::FormatVersion::Integer(4)
    );
}

#[test]
fn migrate_is_available_as_a_top_level_command() {
    let temp_dir = TempDir::new().unwrap();
    let input = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../website/static/ir/examples/v3/greeting-example.json");
    let output_path = temp_dir.path().join("greeting-v4.json");

    let output = morphir_command()
        .args([
            "migrate",
            input.to_str().unwrap(),
            "--output",
            output_path.to_str().unwrap(),
        ])
        .output()
        .expect("failed to run morphir binary");

    assert!(
        output.status.success(),
        "migration failed: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    serde_json::from_slice::<morphir_core::ir::v4::IRFile>(&std::fs::read(output_path).unwrap())
        .unwrap();
}

#[test]
fn migrate_selects_compact_or_expanded_v4_type_encoding() {
    let temp_dir = TempDir::new().unwrap();
    let input = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../website/static/ir/examples/v3/greeting-example.json");
    let compact = temp_dir.path().join("compact.json");
    let expanded = temp_dir.path().join("expanded.json");

    for (path, extra) in [(&compact, None), (&expanded, Some("--expanded"))] {
        let mut command = morphir_command();
        command.args([
            "ir",
            "migrate",
            input.to_str().unwrap(),
            "--output",
            path.to_str().unwrap(),
            "--target-version",
            "v4",
        ]);
        if let Some(extra) = extra {
            command.arg(extra);
        }
        let result = command.output().unwrap();
        assert!(result.status.success());
    }

    let type_expression = |path: &PathBuf| {
        let value: serde_json::Value =
            serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap();
        value["distribution"]["Library"]["def"]["modules"]["main"]["value"]["types"]
            ["product-id"]["value"]["value"]["TypeAliasDefinition"]["typeExp"]
            .clone()
    };
    assert!(type_expression(&compact).is_string());
    assert!(type_expression(&expanded)["Reference"].is_object());
}

#[test]
fn migrate_failure_does_not_replace_an_existing_output() {
    let temp_dir = TempDir::new().unwrap();
    let morphir_home = temp_dir.path().join("home");
    let input = temp_dir.path().join("v2.json");
    let output_path = temp_dir.path().join("result.json");
    let mut source: serde_json::Value = serde_json::from_str(include_str!(
        "../../../website/static/ir/examples/v3/greeting-example.json"
    ))
    .unwrap();
    source["formatVersion"] = 2.into();
    std::fs::write(&input, serde_json::to_vec(&source).unwrap()).unwrap();
    std::fs::write(&output_path, "unchanged").unwrap();

    let output = morphir_command()
        .args([
            "ir",
            "migrate",
            input.to_str().unwrap(),
            "--output",
            output_path.to_str().unwrap(),
            "--target-version",
            "v4",
        ])
        .env("MORPHIR_HOME", &morphir_home)
        .env_remove("MORPHIR_LOG_DIR")
        .env("MORPHIR_LOG_FILE", "true")
        .env("MORPHIR_LOGGING__FILE_LEVEL", "error")
        .output()
        .expect("failed to run morphir binary");

    assert!(!output.status.success());
    assert_eq!(std::fs::read_to_string(&output_path).unwrap(), "unchanged");
    let stderr = String::from_utf8_lossy(&output.stderr);
    let operation_id = stderr
        .lines()
        .find_map(|line| line.strip_prefix("Operation ID: "))
        .expect("migration failure should report its operation ID");
    let log_path = stderr
        .lines()
        .find_map(|line| line.strip_prefix("Log: "))
        .map(PathBuf::from)
        .expect("migration failure should report its log path");
    let events = std::fs::read_to_string(log_path).unwrap();
    assert!(events.lines().any(|line| {
        serde_json::from_str::<serde_json::Value>(line).is_ok_and(|event| {
            event["fields"]["operation_id"] == operation_id
                && event["fields"]["event_name"] == "cli.operation.finish"
                && event["fields"]["outcome"] == "failure"
                && event["fields"]["diagnostic"]
                    .as_str()
                    .is_some_and(|diagnostic| !diagnostic.is_empty())
        })
    }));
}

#[test]
fn migrate_reports_unsupported_v4_downgrade_without_replacing_output() {
    let temp_dir = TempDir::new().unwrap();
    let input = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../website/static/ir/examples/v4/complete-example.json");
    let output_path = temp_dir.path().join("result.json");
    std::fs::write(&output_path, "unchanged").unwrap();

    let output = morphir_command()
        .args([
            "ir",
            "migrate",
            input.to_str().unwrap(),
            "--output",
            output_path.to_str().unwrap(),
            "--target-version",
            "v3",
        ])
        .output()
        .expect("failed to run morphir binary");

    assert!(!output.status.success());
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert_eq!(stderr.matches("unsupported_v4_downgrade").count(), 1);
    assert_eq!(std::fs::read_to_string(&output_path).unwrap(), "unchanged");

    let json_output = morphir_command()
        .args([
            "ir",
            "migrate",
            input.to_str().unwrap(),
            "--output",
            output_path.to_str().unwrap(),
            "--target-version",
            "v3",
            "--json",
        ])
        .output()
        .expect("failed to run morphir binary in JSON mode");

    assert!(!json_output.status.success());
    let report: serde_json::Value = serde_json::from_slice(&json_output.stdout).unwrap();
    assert_eq!(report["success"], false);
    assert!(
        report["error"]
            .as_str()
            .is_some_and(|error| error.contains("unsupported_v4_downgrade"))
    );
    assert!(!String::from_utf8_lossy(&json_output.stderr).contains("unsupported_v4_downgrade"));
}

#[test]
fn migrate_writes_and_reads_a_v4_document_tree() {
    let temp_dir = TempDir::new().unwrap();
    let input = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../website/static/ir/examples/v3/greeting-example.json");
    let tree = temp_dir.path().join("greeting.morphir-dist");
    let single_file = temp_dir.path().join("round-trip.json");

    let to_tree = morphir_command()
        .args([
            "ir",
            "migrate",
            input.to_str().unwrap(),
            "--output",
            tree.to_str().unwrap(),
            "--output-layout",
            "vfs",
            "--target-version",
            "v4",
        ])
        .output()
        .expect("failed to migrate to a document tree");
    assert!(
        to_tree.status.success(),
        "migration failed: stdout={} stderr={}",
        String::from_utf8_lossy(&to_tree.stdout),
        String::from_utf8_lossy(&to_tree.stderr)
    );
    assert!(tree.join("manifest.yaml").is_file());

    let to_file = morphir_command()
        .args([
            "ir",
            "migrate",
            tree.to_str().unwrap(),
            "--output",
            single_file.to_str().unwrap(),
            "--output-layout",
            "single-file",
            "--target-version",
            "v4",
        ])
        .output()
        .expect("failed to migrate the document tree to a file");
    assert!(
        to_file.status.success(),
        "migration failed: stdout={} stderr={}",
        String::from_utf8_lossy(&to_file.stdout),
        String::from_utf8_lossy(&to_file.stderr)
    );
    serde_json::from_slice::<morphir_core::ir::v4::IRFile>(&std::fs::read(single_file).unwrap())
        .unwrap();
}

#[test]
fn migrate_infers_vfs_for_a_new_directory_path_with_a_trailing_separator() {
    let temp_dir = TempDir::new().unwrap();
    let input = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../website/static/ir/examples/v3/greeting-example.json");
    let tree = format!("{}/", temp_dir.path().join("new-tree").display());

    let output = morphir_command()
        .args(["ir", "migrate", input.to_str().unwrap(), "--output", &tree])
        .output()
        .expect("failed to migrate to an inferred document tree");

    assert!(
        output.status.success(),
        "migration failed: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(PathBuf::from(tree).join("manifest.yaml").is_file());
}

#[test]
fn migrate_accepts_partial_and_encoding_flags() {
    let output = morphir_command()
        .args(["ir", "migrate", "--help"])
        .output()
        .expect("failed to read migrate help");
    let help = String::from_utf8_lossy(&output.stdout);
    assert!(help.contains("--allow-partial"));
    assert!(help.contains("--expanded"));
    assert!(help.contains("--output-layout"));
    assert!(help.contains("--input-format"));
    assert!(help.contains("--output-format"));
}
