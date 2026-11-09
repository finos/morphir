//! Deterministic generator for the TEST-ONLY signed toolchain repository.
//!
//! Every signing key is derived from a public label, so anyone can recompute
//! it. That is the point: these keys authenticate nothing outside the tests
//! and can never be mistaken for a production root. The generated repository
//! follows the tool release metadata v1 profile (TUF 1.0.36, Ed25519,
//! consistent snapshots, SHA-256 target hashes).
//!
//! Regenerate the committed fixture with
//! `MORPHIR_TOOLCHAIN_FIXTURES=write cargo test -p morphir-toolchain-contract --test signed_repository`.

#![allow(dead_code)]

use ed25519_dalek::{Signer, SigningKey};
use morphir_toolchain_contract::{PlatformId, Sha256};
use serde::Serialize;
use serde_json::{Value, json};
use std::collections::BTreeMap;

pub const KEY_LABEL_PREFIX: &str = "morphir-toolchain-contract TEST-ONLY fixture key: ";
pub const SPEC_VERSION: &str = "1.0.36";
pub const NEVER: &str = "2999-01-01T00:00:00Z";
pub const REFERENCE_TIME: &str = "2030-01-01T00:00:00Z";
pub const HOST_VERSION: &str = "1.2.3";

/// Encode TUF canonical JSON.
pub fn canonical(value: &Value) -> Vec<u8> {
    let mut bytes = Vec::new();
    let mut serializer =
        serde_json::Serializer::with_formatter(&mut bytes, olpc_cjson::CanonicalFormatter::new());
    value
        .serialize(&mut serializer)
        .expect("fixture JSON is canonical");
    bytes
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

pub struct FixtureKey {
    pub role: &'static str,
    pub label: String,
    signing: SigningKey,
}

impl FixtureKey {
    pub fn derive(role: &'static str, name: &str) -> Self {
        let label = format!("{KEY_LABEL_PREFIX}{name}");
        let seed = Sha256::of_bytes(label.as_bytes());
        Self {
            role,
            label,
            signing: SigningKey::from_bytes(seed.digest().as_bytes()),
        }
    }

    pub fn public_hex(&self) -> String {
        hex(self.signing.verifying_key().as_bytes())
    }

    pub fn tuf_key(&self) -> Value {
        json!({
            "keytype": "ed25519",
            "scheme": "ed25519",
            "keyval": { "public": self.public_hex() }
        })
    }

    pub fn key_id(&self) -> String {
        Sha256::of_bytes(&canonical(&self.tuf_key())).to_string()
    }
}

pub struct Keys {
    pub root: Vec<FixtureKey>,
    pub targets: FixtureKey,
    pub snapshot: FixtureKey,
    pub timestamp: FixtureKey,
}

impl Keys {
    pub fn derive() -> Self {
        Self {
            root: vec![
                FixtureKey::derive("root", "root-1"),
                FixtureKey::derive("root", "root-2"),
            ],
            targets: FixtureKey::derive("targets", "targets-1"),
            snapshot: FixtureKey::derive("snapshot", "snapshot-1"),
            timestamp: FixtureKey::derive("timestamp", "timestamp-1"),
        }
    }

    pub fn all(&self) -> Vec<&FixtureKey> {
        self.root
            .iter()
            .chain([&self.targets, &self.snapshot, &self.timestamp])
            .collect()
    }
}

pub fn sign(signed: Value, keys: &[&FixtureKey]) -> Value {
    let message = canonical(&signed);
    let signatures = keys
        .iter()
        .map(|key| {
            json!({
                "keyid": key.key_id(),
                "sig": hex(&key.signing.sign(&message).to_bytes())
            })
        })
        .collect::<Vec<_>>();
    json!({ "signatures": signatures, "signed": signed })
}

fn role(keys: &[&FixtureKey], threshold: u64) -> Value {
    json!({
        "keyids": keys.iter().map(|key| key.key_id()).collect::<Vec<_>>(),
        "threshold": threshold
    })
}

pub fn root(keys: &Keys) -> Value {
    let mut tuf_keys = serde_json::Map::new();
    for key in keys.all() {
        tuf_keys.insert(key.key_id(), key.tuf_key());
    }
    let signed = json!({
        "_type": "root",
        "spec_version": SPEC_VERSION,
        "version": 1,
        "expires": NEVER,
        "consistent_snapshot": true,
        "keys": tuf_keys,
        "roles": {
            "root": role(&keys.root.iter().collect::<Vec<_>>(), 2),
            "targets": role(&[&keys.targets], 1),
            "snapshot": role(&[&keys.snapshot], 1),
            "timestamp": role(&[&keys.timestamp], 1)
        }
    });
    sign(signed, &keys.root.iter().collect::<Vec<_>>())
}

fn meta(envelope: &Value) -> Value {
    let bytes = canonical(envelope);
    json!({
        "version": envelope["signed"]["version"],
        "length": bytes.len(),
        "hashes": { "sha256": Sha256::of_bytes(&bytes).to_string() }
    })
}

/// One published target: its bytes and optional `custom.morphir` metadata.
#[derive(Clone)]
pub struct Target {
    pub bytes: String,
    pub custom: Option<Value>,
}

pub type Targets = BTreeMap<String, Target>;

/// Sign a complete metadata set (targets, snapshot, timestamp) at `version`.
pub fn metadata(keys: &Keys, targets: &Targets, version: u64, timestamp_expires: &str) -> Value {
    let entries = targets
        .iter()
        .map(|(path, target)| {
            let mut entry = json!({
                "length": target.bytes.len(),
                "hashes": { "sha256": Sha256::of_bytes(target.bytes.as_bytes()).to_string() }
            });
            if let Some(custom) = &target.custom {
                entry["custom"] = json!({ "morphir": custom });
            }
            (path.clone(), entry)
        })
        .collect::<serde_json::Map<_, _>>();
    let targets = sign(
        json!({
            "_type": "targets",
            "spec_version": SPEC_VERSION,
            "version": version,
            "expires": NEVER,
            "targets": entries
        }),
        &[&keys.targets],
    );
    let snapshot = sign(
        json!({
            "_type": "snapshot",
            "spec_version": SPEC_VERSION,
            "version": version,
            "expires": NEVER,
            "meta": { "targets.json": meta(&targets) }
        }),
        &[&keys.snapshot],
    );
    let timestamp = sign(
        json!({
            "_type": "timestamp",
            "spec_version": SPEC_VERSION,
            "version": version,
            "expires": timestamp_expires,
            "meta": { "snapshot.json": meta(&snapshot) }
        }),
        &[&keys.timestamp],
    );
    json!({ "timestamp": timestamp, "snapshot": snapshot, "targets": targets })
}

// ----- published content ----------------------------------------------------

pub struct Offering {
    pub deployment: &'static str,
    pub tool_id: &'static str,
    pub name: &'static str,
}

/// The three separately published archive offerings. `dotnet-tool` is
/// published as a NuGet package, not as a v1 tool release.
pub const ARCHIVE_OFFERINGS: [Offering; 3] = [
    Offering {
        deployment: "native-aot",
        tool_id: "morphir-dotnet-native-aot",
        name: "Morphir .NET Native AOT (TEST-ONLY fixture)",
    },
    Offering {
        deployment: "self-contained",
        tool_id: "morphir-dotnet-self-contained",
        name: "Morphir .NET self-contained (TEST-ONLY fixture)",
    },
    Offering {
        deployment: "framework-dependent",
        tool_id: "morphir-dotnet-framework-dependent",
        name: "Morphir .NET framework-dependent (TEST-ONLY fixture)",
    },
];

pub const TOOL_PACKAGE: &str = "packages/nuget/morphir.tool/1.2.3/morphir.tool.1.2.3.nupkg";

pub fn platforms() -> Vec<PlatformId> {
    PlatformId::FIRST_DELIVERY
        .iter()
        .map(|name| PlatformId::parse(name).unwrap())
        .collect()
}

pub fn host_target(tool_id: &str, platform: PlatformId) -> String {
    let extension = if platform.is_windows() {
        "zip"
    } else {
        "tar.gz"
    };
    format!("artifacts/{tool_id}/{HOST_VERSION}/{platform}.{extension}")
}

fn synthetic(what: &str) -> String {
    format!("TEST-ONLY synthetic {what}. Not a released download.\n")
}

fn v1_platform(platform: PlatformId) -> Value {
    let tool = platform
        .tool_platform()
        .expect("first-delivery platforms have v1 spellings");
    json!({ "os": tool.os(), "arch": tool.arch() })
}

/// Add one v1 tool release with an artifact per first-delivery platform.
pub fn add_tool_release(
    targets: &mut Targets,
    offering: &Offering,
    status: &str,
    channels: &[&str],
) {
    let artifacts = platforms()
        .into_iter()
        .map(|platform| {
            let executable = if platform.is_windows() {
                "morphir.exe"
            } else {
                "morphir"
            };
            json!({
                "targetPath": host_target(offering.tool_id, platform),
                "platform": v1_platform(platform),
                "archive": {
                    "format": if platform.is_windows() { "zip" } else { "tar-gzip" },
                    "entryPoint": executable
                },
                "launch": { "kind": "executable", "path": executable, "args": [] }
            })
        })
        .collect::<Vec<_>>();
    // Release descriptors record the state at initial publication.
    let descriptor = json!({
        "schemaVersion": 1,
        "kind": "morphir-tool-release",
        "tool": { "id": offering.tool_id, "name": offering.name },
        "version": HOST_VERSION,
        "channels": ["stable"],
        "status": "active",
        "compatibility": { "morphirCli": ">=0.0.0" },
        "artifacts": artifacts
    });
    targets.insert(
        format!("releases/{}/{HOST_VERSION}.json", offering.tool_id),
        Target {
            bytes: String::from_utf8(canonical(&descriptor)).unwrap(),
            custom: Some(json!({
                "schemaVersion": 1,
                "kind": "tool-release",
                "toolId": offering.tool_id,
                "version": HOST_VERSION,
                "channels": channels,
                "status": status,
                "compatibility": { "morphirCli": ">=0.0.0" },
                "platforms": platforms().into_iter().map(v1_platform).collect::<Vec<_>>()
            })),
        },
    );
    for platform in platforms() {
        targets.insert(
            host_target(offering.tool_id, platform),
            Target {
                bytes: synthetic(&format!(
                    "{} {HOST_VERSION} {platform} archive",
                    offering.tool_id
                )),
                custom: Some(json!({
                    "schemaVersion": 1,
                    "kind": "tool-artifact",
                    "toolId": offering.tool_id,
                    "version": HOST_VERSION,
                    "platform": v1_platform(platform)
                })),
            },
        );
    }
}

pub fn digest_of(targets: &Targets, path: &str) -> String {
    Sha256::of_bytes(targets[path].bytes.as_bytes()).to_string()
}

fn model_input() -> Value {
    json!({ "profile": "morphir-ir", "codec": "morphir-json", "irVersion": "4.0.0" })
}

fn built_in_generate() -> Value {
    json!({
        "operation": "generate",
        "target": "fsharp",
        "extensionId": "morphir.fsharp",
        "version": HOST_VERSION,
        "modelInput": model_input()
    })
}

/// The recipe host offerings, bound to the targets already in `targets`.
pub fn host_offerings(targets: &Targets) -> Vec<Value> {
    let glibc = json!({
        "kind": "native", "name": "glibc", "versions": [">=2.28.0"],
        "platforms": ["linux-x64", "linux-arm64"]
    });
    let runtime = json!({
        "kind": "runtime", "name": "Microsoft.NETCore.App", "versions": [">=10.0.0", "<11.0.0"]
    });
    let sdk = json!({
        "kind": "sdk", "name": "Microsoft.NET.Sdk", "versions": [">=10.0.100"], "phase": "install"
    });
    let mut hosts = ARCHIVE_OFFERINGS
        .iter()
        .map(|offering| {
            let platforms = platforms()
                .into_iter()
                .map(|platform| {
                    let target = host_target(offering.tool_id, platform);
                    (
                        platform.to_string(),
                        json!({ "target": target, "sha256": digest_of(targets, &target) }),
                    )
                })
                .collect::<serde_json::Map<_, _>>();
            let prerequisites = if offering.deployment == "framework-dependent" {
                json!([runtime, glibc])
            } else {
                json!([glibc])
            };
            json!({
                "implementation": "dotnet",
                "version": HOST_VERSION,
                "deployment": offering.deployment,
                "execution": if offering.deployment == "native-aot" { "native-aot" } else { "jit" },
                "source": { "kind": "tool-release", "toolId": offering.tool_id },
                "protocolVersions": ["0.1", "0.2.0-draft.1"],
                "wasmAbis": [],
                "prerequisites": prerequisites,
                "builtIns": [built_in_generate()],
                "platforms": platforms
            })
        })
        .collect::<Vec<_>>();
    let package_digest = digest_of(targets, TOOL_PACKAGE);
    hosts.push(json!({
        "implementation": "dotnet",
        "version": HOST_VERSION,
        "deployment": "dotnet-tool",
        "execution": "jit",
        "source": { "kind": "dotnet-tool", "packageId": "Morphir.Tool", "command": "dotnet-morphir" },
        "protocolVersions": ["0.1", "0.2.0-draft.1"],
        "wasmAbis": [],
        "prerequisites": [runtime, sdk],
        "builtIns": [built_in_generate()],
        "platforms": platforms()
            .into_iter()
            .map(|platform| (platform.to_string(), json!({ "target": TOOL_PACKAGE, "sha256": package_digest })))
            .collect::<serde_json::Map<_, _>>()
    }));
    hosts
}

pub fn recipe_path(preset: &str, version: &str) -> String {
    format!("toolchains/recipes/{preset}/{version}.json")
}

/// Publish a recipe document as an authenticated target.
pub fn add_recipe(targets: &mut Targets, recipe: &Value, channels: &[&str], status: &str) {
    let preset = recipe["preset"].as_str().unwrap();
    let version = recipe["version"].as_str().unwrap();
    targets.insert(
        recipe_path(preset, version),
        Target {
            bytes: String::from_utf8(canonical(recipe)).unwrap(),
            custom: Some(json!({
                "kind": "toolset-recipe",
                "schemaVersion": "0.1.0-draft.1",
                "preset": preset,
                "version": version,
                "channels": channels,
                "status": status
            })),
        },
    );
}

/// A recipe that maps the four offerings and keeps the built-in F# generator.
pub fn offering_recipe(targets: &Targets, preset: &str) -> Value {
    json!({
        "schemaVersion": "0.1.0-draft.1",
        "preset": preset,
        "version": "1.0.0",
        "operations": [{ "operation": "generate", "target": "fsharp" }],
        "hosts": host_offerings(targets),
        "providers": []
    })
}

/// The published content of the test-only repository.
pub fn published() -> Targets {
    let mut targets = Targets::new();
    for offering in &ARCHIVE_OFFERINGS {
        add_tool_release(&mut targets, offering, "active", &["stable"]);
    }
    targets.insert(
        TOOL_PACKAGE.to_owned(),
        Target {
            bytes: synthetic("Morphir.Tool 1.2.3 NuGet package"),
            custom: None,
        },
    );

    let valid = offering_recipe(&targets, "fsharp-builtin");

    // Recipes that are validly signed and still wrong. Authentication proves
    // who published the bytes; the binding checks prove what they bind.
    let bind = |preset: &str, binding: Value| {
        let mut recipe = offering_recipe(&targets, preset);
        recipe["hosts"][0]["platforms"]["win-x64"] = binding;
        recipe
    };
    let native = host_target(
        "morphir-dotnet-native-aot",
        PlatformId::parse("win-x64").unwrap(),
    );
    let arm = host_target(
        "morphir-dotnet-native-aot",
        PlatformId::parse("win-arm64").unwrap(),
    );
    let managed = host_target(
        "morphir-dotnet-self-contained",
        PlatformId::parse("win-x64").unwrap(),
    );
    let digest = bind(
        "negative-digest-substituted",
        json!({ "target": native, "sha256": "0".repeat(64) }),
    );
    let platform = bind(
        "negative-platform-substituted",
        json!({ "target": arm, "sha256": digest_of(&targets, &arm) }),
    );
    let deployment = bind(
        "negative-deployment-substituted",
        json!({ "target": managed, "sha256": digest_of(&targets, &managed) }),
    );
    let missing = bind(
        "negative-unauthenticated-target",
        json!({
            "target": "artifacts/morphir-dotnet-native-aot/1.2.3/win-x64-unpublished.zip",
            "sha256": "1".repeat(64)
        }),
    );

    add_recipe(&mut targets, &valid, &["stable"], "active");
    for negative in [digest, platform, deployment, missing] {
        add_recipe(&mut targets, &negative, &[], "active");
    }
    targets
}

/// Build the complete fixture document.
pub fn fixture() -> Value {
    let keys = Keys::derive();
    let targets = published();
    let trusted_root = root(&keys);
    let repository_id = Sha256::of_bytes(&canonical(&trusted_root["signed"])).to_string();
    json!({
        "testOnly": "TEST-ONLY. Every key in this repository is derived from the public label recorded in testOnlyKeys, so anyone can sign with it. Never trust this repository or these keys outside tests.",
        "contractVersion": "0.1.0-draft.1",
        "profile": "tool-release-metadata-v1",
        "referenceTime": REFERENCE_TIME,
        "repositoryId": repository_id,
        "testOnlyKeys": keys.all().iter().map(|key| json!({
            "role": key.role,
            "label": key.label,
            "keyId": key.key_id(),
            "public": key.public_hex()
        })).collect::<Vec<_>>(),
        "trustedRoot": trusted_root,
        "metadata": metadata(&keys, &targets, 1, NEVER),
        "targetFiles": targets
            .iter()
            .map(|(path, target)| (path.clone(), Value::String(target.bytes.clone())))
            .collect::<serde_json::Map<_, _>>()
    })
}
