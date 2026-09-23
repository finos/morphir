//! Host-only release gate against the pinned, already downloaded extensions.

#[path = "support/process_bundle.rs"]
mod process_bundle;
#[path = "support/mod.rs"]
mod support;

use serde_json::Value;
use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
};
use support::assert_success;

const PINS: &str = include_str!("../../../.config/published-extension-bundles.toml");

struct HostCompatibility {
    _root: tempfile::TempDir,
    project: PathBuf,
    home: PathBuf,
    repository: PathBuf,
    /// Test scaffolding, such as an assembled bundle, kept out of the Morphir home.
    scratch: PathBuf,
}

impl HostCompatibility {
    fn new() -> Self {
        let root = tempfile::tempdir().unwrap();
        let project = root.path().join("project");
        fs::create_dir_all(project.join(".morphir")).unwrap();
        Self {
            project,
            home: root.path().join("home"),
            repository: root.path().join("repository"),
            scratch: root.path().join("scratch"),
            _root: root,
        }
    }

    fn run(&self, arguments: &[&str]) -> String {
        let output = Command::new(env!("CARGO_BIN_EXE_morphir"))
            .args(arguments)
            .env("MORPHIR_HOME", &self.home)
            .current_dir(&self.project)
            .output()
            .unwrap();
        assert_success(&output, &format!("morphir {}", arguments.join(" ")));
        String::from_utf8(output.stdout).unwrap()
    }

    fn publish_and_install(&self, bundle: &Path, id: &str, version: &str) {
        self.run(&[
            "extension",
            "repository",
            "init",
            self.repository.to_str().unwrap(),
        ]);
        self.run(&[
            "extension",
            "repository",
            "add",
            "local",
            "--directory",
            self.repository.to_str().unwrap(),
        ]);
        self.run(&[
            "extension",
            "repository",
            "publish",
            "local",
            "--bundle",
            bundle.to_str().unwrap(),
        ]);
        // No --no-probe: compatibility includes the default install gate.
        self.run(&[
            "extension",
            "install",
            id,
            "--repository",
            "local",
            "--version",
            version,
        ]);
        let catalog = self.catalog();
        let entries = catalog["extensions"].as_array().unwrap();
        assert_eq!(entries.len(), 1, "{catalog}");
        assert_eq!(entries[0]["extensionId"], id, "{catalog}");
        assert_eq!(entries[0]["version"], version, "{catalog}");
        // Installed bytes must suffice even when the local repository is gone.
        fs::remove_dir_all(&self.repository).unwrap();
    }

    fn catalog(&self) -> Value {
        serde_json::from_slice(&fs::read(self.home.join("catalog/extensions.json")).unwrap())
            .unwrap()
    }

    fn remove(&self, id: &str) {
        self.run(&["extension", "uninstall", id]);
        assert_eq!(self.catalog()["extensions"], serde_json::json!([]));
        assert!(
            self.run(&["extension", "list"])
                .contains("No verified extensions installed.")
        );
    }
}

fn pin(group: &str, short_id: &str) -> toml::Value {
    let pins: toml::Value = toml::from_str(PINS).unwrap();
    let mut names: Vec<_> = ["bundles", "executables"]
        .into_iter()
        .flat_map(|group| pins[group].as_table().unwrap().keys())
        .collect();
    names.sort();
    assert_eq!(
        names,
        ["avro", "elm", "openapi", "python", "rust", "scala-elm"],
        "update the host compatibility tests when adding or removing a pin"
    );
    pins[group][short_id].clone()
}

fn pinned_version(pin: &toml::Value) -> &str {
    pin["tag"]
        .as_str()
        .unwrap()
        .rsplit('/')
        .next()
        .unwrap()
        .strip_prefix('v')
        .unwrap()
}

fn bundles() -> PathBuf {
    let path = PathBuf::from(
        std::env::var_os("MORPHIR_PUBLISHED_BUNDLES")
            .expect("set MORPHIR_PUBLISHED_BUNDLES to the fetched bundles directory"),
    );
    // Cargo runs integration tests from the package directory; accept paths from the repo root.
    let path = if path.is_absolute() {
        path
    } else {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../..")
            .join(path)
    };
    path.canonicalize()
        .unwrap_or_else(|error| panic!("{}: {error}", path.display()))
}

fn wasm(short_id: &str, ir: Value, options: &[&str]) {
    let pin = pin("bundles", short_id);
    let bundle = bundles().join(short_id);
    let descriptor: Value = serde_json::from_slice(
        &fs::read(bundle.join("release.json"))
            .unwrap_or_else(|error| panic!("missing pinned {short_id} release.json: {error}")),
    )
    .unwrap();
    assert_eq!(descriptor["version"], pinned_version(&pin));
    let guest = bundle.join(format!("{}.wasm", pin["artifact"].as_str().unwrap()));
    let bytes = fs::read(&guest).unwrap_or_else(|error| panic!("{}: {error}", guest.display()));
    assert_eq!(
        morphir_distribution::Sha256Digest::of_bytes(&bytes).to_string(),
        pin["sha256"].as_str().unwrap()
    );
    let id = format!("morphir-{short_id}");
    let host = HostCompatibility::new();
    host.publish_and_install(&bundle, &id, pinned_version(&pin));
    let catalog = host.catalog();
    for member in ["statement", "statementSource", "probeSource"] {
        assert!(
            catalog["extensions"][0].get(member).is_none(),
            "version-1 catalog must retain its legacy shape: {catalog}"
        );
    }
    assert!(
        host.run(&["extension", "list"])
            .contains("Statement: declared")
    );
    fs::write(
        host.project.join("morphir.toml"),
        "[project]\nname = 'Acme.Example'\nversion = '1.0.0'\n",
    )
    .unwrap();
    fs::write(
        host.project.join("input.json"),
        serde_json::to_vec(&ir).unwrap(),
    )
    .unwrap();
    let mut args = vec![
        "generate",
        "--target",
        short_id,
        "--input",
        "input.json",
        "--output",
        "generated",
        "--json",
    ];
    args.extend_from_slice(options);
    let report: Value = serde_json::from_str(&host.run(&args)).unwrap();
    assert_eq!(report["success"], true, "{report}");
    let artifacts = report["artifacts"].as_array().unwrap();
    assert!(!artifacts.is_empty(), "{report}");
    for artifact in artifacts {
        let path = host
            .project
            .join("generated")
            .join(artifact.as_str().unwrap());
        assert!(path.is_file(), "missing {}", path.display());
        assert!(fs::metadata(path).unwrap().len() > 0);
    }
    host.remove(&id);
}

fn elm(short_id: &str, id: &str, override_variable: &str) {
    let pin = pin("executables", short_id);
    let downloaded = bundles()
        .join(short_id)
        .join(pin["executable"].as_str().unwrap());
    let executable = std::env::var_os(override_variable)
        .map(PathBuf::from)
        .unwrap_or(downloaded);
    let executable = executable.canonicalize().unwrap_or_else(|error| {
        panic!(
            "missing pinned {short_id} executable {} (override with {override_variable}): {error}",
            executable.display()
        )
    });
    let host = HostCompatibility::new();
    let bundle = process_bundle::from_executable(
        &host.scratch,
        &executable,
        id,
        short_id,
        pinned_version(&pin),
    );
    host.publish_and_install(&bundle, id, pinned_version(&pin));
    let catalog = host.catalog();
    assert_eq!(
        catalog["extensions"][0]["statementSource"], "probed",
        "{catalog}"
    );
    assert_eq!(
        catalog["extensions"][0]["probeSource"], "session-fallback",
        "{catalog}"
    );
    let declared: Value =
        serde_json::from_slice(&fs::read(bundle.join("release.json")).unwrap()).unwrap();
    assert_eq!(
        catalog["extensions"][0]["statement"],
        declared["artifacts"][0]["statement"]
    );
    fs::write(
        host.project.join("Example.elm"),
        "module Example exposing (add)\n\nadd : Int -> Int -> Int\nadd left right = left + right\n",
    )
    .unwrap();
    host.run(&["compile", "--input", "Example.elm", "--extension", id]);
    let ir = host
        .project
        .join(".morphir/out/compile.dest/morphir-ir.json");
    let ir: Value = serde_json::from_slice(&fs::read(ir).expect("compile must write IR")).unwrap();
    assert!(ir.get("distribution").is_some(), "{ir}");
    host.remove(id);
}

#[test]
#[ignore = "requires MORPHIR_PUBLISHED_BUNDLES"]
fn avro() {
    wasm(
        "avro",
        support::v3_library(),
        &[
            "--option",
            "representation=json",
            "--option",
            "projection=schemas",
            "--option",
            "unsupported=warn-and-skip",
        ],
    );
}

#[test]
#[ignore = "requires MORPHIR_PUBLISHED_BUNDLES"]
fn openapi() {
    wasm(
        "openapi",
        serde_json::from_str(include_str!("fixtures/openapi/classic-schema-library.json")).unwrap(),
        &[],
    );
}

#[test]
#[ignore = "requires MORPHIR_PUBLISHED_BUNDLES"]
fn python() {
    // morphir-python-binding/tests/pipeline.rs: backend_accepts_an_independently_authored_sum.
    wasm(
        "python",
        serde_json::from_str(include_str!(
            "fixtures/host-compatibility/python-sum-v4.json"
        ))
        .unwrap(),
        &[],
    );
}

#[test]
#[ignore = "requires MORPHIR_PUBLISHED_BUNDLES"]
fn rust() {
    // morphir-rust-binding/tests/backend.rs: v3_and_v4_generate_identical_types.
    wasm(
        "rust",
        serde_json::from_str(include_str!(
            "fixtures/host-compatibility/rust-count-v4.json"
        ))
        .unwrap(),
        &[],
    );
}

#[test]
#[ignore = "requires MORPHIR_PUBLISHED_BUNDLES; macOS can set MORPHIR_ELM_EXTENSION_BIN"]
fn elm_reference() {
    elm("elm", "morphir-elm", "MORPHIR_ELM_EXTENSION_BIN");
}

#[test]
#[ignore = "requires MORPHIR_PUBLISHED_BUNDLES; macOS can set MORPHIR_SCALA_ELM_EXTENSION_BIN"]
fn scala_elm() {
    elm(
        "scala-elm",
        "morphir-scala-elm",
        "MORPHIR_SCALA_ELM_EXTENSION_BIN",
    );
}
