//! Installed MEP process extensions for tests.
//!
//! A test that asks how the CLI treats an installed provider needs a real
//! install: the registry and the activation read what the installer
//! persisted, not a fabricated snapshot. The guest is a small Python program
//! that speaks MEP over stdio and answers each method with a reply the test
//! chooses.

use crate::home::MorphirHome;
use morphir_distribution::{
    Channel, ExtensionId, ExtensionInstaller, InstalledExtensionSnapshot, LocalIndex, Platform,
    Selection, Sha256Digest, list_installed,
};
use serde_json::Value;
use std::path::Path;

/// A Python MEP guest over stdio.
///
/// `initialize` is the `morphir.initialize` result. `answers` maps a method
/// name to the members of its reply, `{"result": ...}` or `{"error": ...}`.
/// `morphir.shutdown` answers with an empty result, and any other method
/// with a method-not-found error.
#[cfg(unix)]
pub(crate) fn mep_guest(initialize: &Value, answers: &Value) -> Vec<u8> {
    let python = std::process::Command::new("sh")
        .args(["-c", "command -v python3"])
        .output()
        .expect("sh runs");
    assert!(python.status.success(), "python3 is required for this test");
    let python = String::from_utf8(python.stdout).expect("the python3 path is UTF-8");
    let literal = |value: &Value| {
        serde_json::to_string(&value.to_string()).expect("a JSON text encodes as a string")
    };
    format!(
        r#"#!{python}
import json
import sys

INITIALIZE = json.loads({initialize})
ANSWERS = json.loads({answers})

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

def send(message):
    message["jsonrpc"] = "2.0"
    body = json.dumps(message, separators=(",", ":")).encode()
    sys.stdout.buffer.write(
        b"Content-Length: " + str(len(body)).encode() + b"\r\n\r\n" + body
    )
    sys.stdout.buffer.flush()

while True:
    request = receive()
    method = request["method"]
    if "id" not in request:
        if method == "morphir.exit":
            raise SystemExit(0)
        continue
    identifier = request["id"]
    if method == "morphir.initialize":
        send({{"id": identifier, "result": INITIALIZE}})
    elif method == "morphir.shutdown":
        send({{"id": identifier, "result": {{}}}})
    elif method in ANSWERS:
        reply = dict(ANSWERS[method])
        reply["id"] = identifier
        send(reply)
    else:
        send({{"id": identifier, "error": {{"code": -32601, "message": "unknown"}}}})
"#,
        python = python.trim(),
        initialize = literal(initialize),
        answers = literal(answers),
    )
    .into_bytes()
}

/// Install `guest` as a process extension described by `record`, a schema
/// `"1.0"` index record without its `artifacts`, into a Morphir home below
/// `root`.
pub(crate) fn install_process(
    root: &Path,
    mut record: Value,
    guest: &[u8],
) -> (MorphirHome, InstalledExtensionSnapshot) {
    let extension_id = record["id"]
        .as_str()
        .expect("the record names its extension")
        .to_owned();
    let index = root.join("index");
    let artifact = index.join("artifacts").join(&extension_id);
    std::fs::create_dir_all(artifact.parent().expect("the artifact has a parent"))
        .expect("the artifact directory is created");
    std::fs::create_dir_all(index.join("extensions")).expect("the index directory is created");
    std::fs::write(&artifact, guest).expect("the artifact is written");
    let platform = Platform::current();
    record["artifacts"] = serde_json::json!([{
        "runtime": "process",
        "platform": {"os": platform.os(), "arch": platform.arch()},
        "source": {"kind": "local-file", "path": format!("artifacts/{extension_id}")},
        "sha256": Sha256Digest::of_bytes(guest),
        "filename": extension_id,
        "args": [],
        "executable": true
    }]);
    std::fs::write(
        index
            .join("extensions")
            .join(format!("{extension_id}.jsonl")),
        format!("{record}\n"),
    )
    .expect("the index record is written");

    let home = MorphirHome::resolve_from(Some(root.join("home").as_os_str()), None)
        .expect("an explicit Morphir home resolves");
    let id = ExtensionId::parse(&extension_id).expect("the extension ID parses");
    let host: morphir_workspace::Version = env!("CARGO_PKG_VERSION")
        .parse()
        .expect("the CLI version is SemVer");
    let selected = LocalIndex::open(&index)
        .expect("the local index opens")
        .resolve(&id, Selection::Channel(Channel::Stable), &platform, &host)
        .expect("the index resolves the extension");
    ExtensionInstaller::new(&home)
        .install(selected, &host)
        .expect("the extension installs");
    let snapshot = list_installed(&home)
        .expect("the installed catalog is readable")
        .pop()
        .expect("exactly one extension was installed");
    (home, snapshot)
}

/// A `gleam` frontend at IR `4.0.0`, id `fixture`, that refuses every
/// compile with RPC error -32001 `does not compile`: the guest program and
/// its index record.
#[cfg(unix)]
pub(crate) fn rejecting_frontend() -> (Vec<u8>, Value) {
    let language = serde_json::json!([{"id": "gleam", "fileExtensions": [".gleam"]}]);
    let guest = mep_guest(
        &serde_json::json!({
            "protocolVersion": "0.1",
            "extension": {
                "id": "fixture",
                "name": "Rejecting fixture",
                "version": "1.0.0",
                "types": ["frontend"],
            },
            "capabilities": {"frontend": {
                "languages": language,
                "irVersions": ["4.0.0"],
                "compile": true,
                "incremental": false,
                "fragments": false,
            }},
        }),
        &serde_json::json!({
            morphir_extension_sdk::protocol::methods::COMPILE: {
                "error": {"code": -32001, "message": "does not compile"}
            }
        }),
    );
    let record = serde_json::json!({
        "schemaVersion": "1.0",
        "id": "fixture",
        "name": "Rejecting fixture",
        "version": "1.0.0",
        "channels": ["stable"],
        "mepVersions": ["0.1"],
        "capabilities": ["frontend"],
        "frontend": {
            "languages": language,
            "irVersions": ["4.0.0"],
            "compile": true,
        },
    });
    (guest, record)
}

/// Overwrite an installed artifact in the store, so that it no longer
/// matches the digest its lock recorded.
pub(crate) fn tamper(home: &MorphirHome, snapshot: &InstalledExtensionSnapshot) {
    std::fs::write(
        home.root().join(snapshot.installed().store_path()),
        b"corrupted after installation",
    )
    .expect("the installed artifact is overwritten");
}
