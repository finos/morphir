//! A real installed SDK process, reusing this test executable as its guest.
//! The producer constructs recipes and never reads expected digests or replayed responses.
use base64::{Engine as _, engine::general_purpose::STANDARD};
use morphir::commands::ui::{
    artifacts::{ArtifactError, ArtifactGenerationInput, PreparedArtifacts},
    protocol::PlaygroundGenerateParams,
    provider::{PlaygroundCapability, playground::NativePlaygroundProvider},
};
use morphir::home::MorphirHome;
use morphir_distribution::{
    Channel, ExtensionId, ExtensionInstaller, LocalIndex, Platform, Selection, Sha256Digest,
};
use morphir_extension_sdk::{
    Artifact, Backend, BackendCapability, Extension, ExtensionCapabilities, ExtensionInfo,
    GenerateRequest, GenerateResult, NativeExtension,
    protocol::{ExtensionRequest, methods},
};
use serde_json::json;
use std::{
    io::{self, BufRead, Write},
    path::{Path, PathBuf},
    time::Duration,
};
const ID: &str = "artifact-process-qualification";
const TARGET: &str = "artifact-process-fixture";
const FILE_BYTES: usize = 16 * 1024 * 1024;
struct Producer(PathBuf);
impl Extension for Producer {
    fn info() -> ExtensionInfo {
        ExtensionInfo {
            id: ID.into(),
            name: "Artifact process qualification".into(),
            version: "0.1.0".into(),
            ..Default::default()
        }
    }
    fn capabilities() -> ExtensionCapabilities {
        ExtensionCapabilities {
            backend: Some(BackendCapability {
                targets: vec![TARGET.into()],
                ir_versions: vec!["4.0.0".into()],
                generate: true,
            }),
            ..Default::default()
        }
    }
}
fn event(directory: &Path, kind: &str) {
    let mut file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(directory.join("events"))
        .unwrap();
    writeln!(file, "{kind} {}", std::process::id()).unwrap();
}
impl Backend for Producer {
    fn target_languages() -> Vec<String> {
        vec![TARGET.into()]
    }
    fn generate(&self, request: GenerateRequest) -> morphir_extension_sdk::Result<GenerateResult> {
        event(&self.0, "generate");
        std::fs::write(self.0.join("captured.json"), serde_json::to_vec(&request)?)?;
        let mode = request.options["fixtureMode"].as_str().unwrap();
        if mode == "lost" {
            std::process::exit(17);
        }
        if mode == "hang" {
            loop {
                std::thread::park();
            }
        }
        let mut artifacts = if mode == "binary" || mode == "set-one-over" {
            [0_u8, 37, 83, 199]
                .into_iter()
                .enumerate()
                .map(|(index, seed)| Artifact {
                    path: format!("file-{index}.bin"),
                    binary: true,
                    content: STANDARD.encode(
                        (0..FILE_BYTES)
                            .map(|i| {
                                (i % 256) as u8 ^ ((i / 65536 + usize::from(seed)) % 256) as u8
                            })
                            .collect::<Vec<_>>(),
                    ),
                })
                .collect()
        } else if mode == "file-one-over" {
            vec![Artifact {
                path: "oversized.txt".into(),
                binary: false,
                content: "x".repeat(FILE_BYTES + 1),
            }]
        } else if mode == "nul-text" {
            (0..4)
                .map(|index| Artifact {
                    path: format!("file-{index}.txt"),
                    binary: false,
                    content: "\0".repeat(FILE_BYTES),
                })
                .collect()
        } else {
            vec![Artifact {
                path: "original.txt".into(),
                binary: false,
                content: "\u{feff}Original\r\nline two\r\n".into(),
            }]
        };
        if mode == "set-one-over" {
            artifacts.push(Artifact {
                path: "extra.txt".into(),
                binary: false,
                content: "x".into(),
            });
        }
        Ok(GenerateResult {
            success: true,
            artifacts,
            diagnostics: vec![],
        })
    }
}
fn serve(directory: PathBuf) -> Result<(), Box<dyn std::error::Error>> {
    event(&directory, "start");
    let guest = NativeExtension::backend_only(Producer(directory.clone()))?;
    let mut input = io::stdin().lock();
    let mut output = io::stdout().lock();
    loop {
        let mut length = None;
        loop {
            let mut line = String::new();
            if input.read_line(&mut line)? == 0 {
                return Err("EOF before exit".into());
            }
            if line == "\r\n" || line == "\n" {
                break;
            }
            let (name, value) = line.split_once(':').ok_or("invalid header")?;
            if name.eq_ignore_ascii_case("content-length") {
                length = Some(value.trim().parse::<usize>()?);
            }
        }
        let length = length.ok_or("missing length")?;
        if length > 1024 * 1024 {
            return Err("oversized fixture request".into());
        }
        let mut body = vec![0; length];
        std::io::Read::read_exact(&mut input, &mut body)?;
        #[derive(serde::Deserialize)]
        struct Probe {
            method: String,
            id: Option<u64>,
        }
        let probe: Probe = serde_json::from_slice(&body)?;
        if probe.id.is_none() {
            if probe.method == methods::EXIT {
                event(&directory, "exit");
                return Ok(());
            }
            assert_eq!(probe.method, methods::INITIALIZED);
            continue;
        }
        if probe.method == methods::SHUTDOWN {
            event(&directory, "shutdown");
        }
        let request: ExtensionRequest = serde_json::from_slice(&body)?;
        let response = guest.protocol().handle(request);
        let encoded = serde_json::to_vec(&response)?;
        write!(output, "Content-Length: {}\r\n\r\n", encoded.len())?;
        output.write_all(&encoded)?;
        output.flush()?;
    }
}
fn install(root: &Path, state: &Path) -> MorphirHome {
    let bytes = std::fs::read(std::env::current_exe().unwrap()).unwrap();
    let index = root.join("index");
    std::fs::create_dir_all(index.join("artifacts")).unwrap();
    std::fs::create_dir_all(index.join("extensions")).unwrap();
    let filename = if cfg!(windows) {
        "artifact-process.exe"
    } else {
        "artifact-process"
    };
    std::fs::write(index.join("artifacts").join(filename), &bytes).unwrap();
    let platform = Platform::current();
    let record = json!({"schemaVersion":"1.0","id":ID,"name":"Artifact process qualification","version":"0.1.0","channels":["stable"],"mepVersions":["0.1"],"capabilities":["backend"],"backend":{"targets":[TARGET],"irVersions":["4.0.0"],"generate":true},"artifacts":[{"runtime":"process","platform":{"os":platform.os(),"arch":platform.arch()},"source":{"kind":"local-file","path":format!("artifacts/{filename}")},"sha256":Sha256Digest::of_bytes(&bytes),"filename":filename,"args":["--artifact-process-fixture",state],"executable":true}]});
    std::fs::write(
        index.join("extensions").join(format!("{ID}.jsonl")),
        format!("{record}\n"),
    )
    .unwrap();
    let home = MorphirHome::resolve_from(Some(root.join("home").as_os_str()), None).unwrap();
    let host = env!("CARGO_PKG_VERSION").parse().unwrap();
    let selected = LocalIndex::open(&index)
        .unwrap()
        .resolve(
            &ExtensionId::parse(ID).unwrap(),
            Selection::Channel(Channel::Stable),
            &platform,
            &host,
        )
        .unwrap();
    ExtensionInstaller::new(&home)
        .install(selected, &host)
        .unwrap();
    home
}
fn params(mode: &str) -> PlaygroundGenerateParams {
    PlaygroundGenerateParams {
        target: TARGET.into(),
        ir_version: "4.0.0".into(),
        ir: json!({"formatVersion":4,"nested":[{"$serde_json::private::Number":"1"},{"$serde_json::private::RawValue":"{\"x\":1,\"x\":2}"}]}),
        options: json!({"fixtureMode":mode,"literal":{"$serde_json::private::RawValue":"true"}}),
    }
}
fn events(state: &Path, kind: &str) -> Vec<u32> {
    std::fs::read_to_string(state.join("events"))
        .unwrap_or_default()
        .lines()
        .filter_map(|line| {
            let (event, pid) = line.split_once(' ')?;
            (event == kind).then(|| pid.parse().unwrap())
        })
        .collect()
}
async fn stopped(state: &Path) {
    // Process IDs are measured from the guest, never inferred from a successful call.
    for _ in 0..100 {
        #[cfg(unix)]
        let running = events(state, "start").iter().any(|pid| {
            std::process::Command::new("kill")
                .args(["-0", &pid.to_string()])
                .stderr(std::process::Stdio::null())
                .status()
                .unwrap()
                .success()
        });
        #[cfg(windows)]
        let running = events(state, "start").iter().any(|pid| {
            let output = std::process::Command::new("tasklist")
                .args(["/FI", &format!("PID eq {pid}"), "/NH"])
                .output()
                .unwrap();
            String::from_utf8_lossy(&output.stdout)
                .split_whitespace()
                .any(|word| word == pid.to_string())
        });
        if !running {
            return;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    panic!("artifact guest remained alive");
}
async fn qualify() {
    let root = tempfile::tempdir().unwrap();
    let state = root.path().join("state");
    std::fs::create_dir(&state).unwrap();
    let home = install(root.path(), &state);
    let provider = NativePlaygroundProvider::in_workspace(home, root.path());
    // Independently authored before this process fixture; pinned in the shared
    // draft.28 independent/byte-recipes.json corpus, OpenSSL cross-checked.
    let hashes = [
        "728f52a85b49e21b090f8aab42eac87b30f1c82bdb3a3890627bc244de6756b0",
        "d42312f945214c8f55c283c08415efdddb975c664bc7ae4b129a6c37b79b87c8",
        "75e9210fb9b010ccd02fc3b824d482d6f1646aa3a5765baba3034423eb1550f7",
        "d5f3e8e4c2a22852ec5d5aa01c92f7ad149031ea896fd3fd70887f425fc30d27",
    ];
    for mode in ["binary", "nul-text", "small"] {
        let expected = params(mode);
        let ir = expected.ir.clone();
        let literal = expected.options["literal"].clone();
        let generated = provider
            .generate_artifacts(ArtifactGenerationInput::try_from(expected).unwrap())
            .await
            .unwrap()
            .unwrap();
        assert_eq!(generated.producer.id, ID);
        assert_eq!(generated.producer.version, "0.1.0");
        assert!(generated.result.success);
        let captured: GenerateRequest =
            serde_json::from_slice(&std::fs::read(state.join("captured.json")).unwrap()).unwrap();
        assert_eq!(captured.ir, ir);
        assert_eq!(captured.options["literal"], literal);
        assert_eq!(captured.options["emitParseStage"], false);
        if mode == "binary" {
            for (artifact, hash) in generated.result.artifacts.iter().zip(hashes) {
                let bytes = STANDARD.decode(&artifact.content).unwrap();
                assert_eq!(bytes.len(), FILE_BYTES);
                assert_eq!(Sha256Digest::of_bytes(&bytes).to_string(), hash);
            }
        }
        if mode == "nul-text" {
            for artifact in &generated.result.artifacts {
                assert!(!artifact.binary);
                assert_eq!(artifact.content.len(), FILE_BYTES);
                assert!(artifact.content.bytes().all(|byte| byte == 0));
            }
        }
        if mode == "small" {
            assert_eq!(
                generated.result.artifacts[0].content,
                "\u{feff}Original\r\nline two\r\n"
            );
        }
        let prepared = PreparedArtifacts::inspect(generated.result.artifacts).unwrap();
        if mode != "small" {
            assert_eq!(prepared.decoded_length(), 64 * 1024 * 1024);
        }
        stopped(&state).await;
        println!(
            "installed artifact process {mode}: byte-exact output, literal inputs, orderly close passed"
        );
    }
    assert_eq!(events(&state, "generate").len(), 3);
    assert_eq!(events(&state, "shutdown").len(), 3);
    assert_eq!(events(&state, "exit").len(), 3);
    for (mode, rejection) in [
        ("file-one-over", ArtifactError::FileSize),
        ("set-one-over", ArtifactError::SetSize),
    ] {
        let generated = provider
            .generate_artifacts(ArtifactGenerationInput::try_from(params(mode)).unwrap())
            .await
            .unwrap()
            .unwrap();
        assert!(
            generated.result.success,
            "SDK returns the actual oversized content"
        );
        assert_eq!(
            PreparedArtifacts::inspect(generated.result.artifacts).unwrap_err(),
            rejection
        );
        stopped(&state).await;
        println!(
            "installed artifact process {mode}: actual returned bytes refused by profile conversion"
        );
    }
    for mode in ["lost", "hang"] {
        let before = events(&state, "generate").len();
        let result = provider
            .generate_artifacts(ArtifactGenerationInput::try_from(params(mode)).unwrap())
            .await;
        assert!(result.is_err(), "{mode} unexpectedly succeeded");
        assert_eq!(
            events(&state, "generate").len(),
            before + 1,
            "artifact generation retried after {mode}"
        );
        stopped(&state).await;
        println!(
            "installed artifact process {mode}: exactly one invocation and child cleanup passed"
        );
    }
    // A failed artifact attempt cannot poison or widen the ordinary legacy pool.
    let ordinary = provider.generate(params("small")).await.unwrap();
    assert!(ordinary.success);
    drop(provider);
    stopped(&state).await;
    println!("ordinary generation after artifact failures passed");
}
fn main() {
    let args: Vec<_> = std::env::args_os().collect();
    if args
        .get(1)
        .is_some_and(|arg| arg == "--artifact-process-fixture")
    {
        serve(PathBuf::from(&args[2])).unwrap();
        return;
    }
    tokio::runtime::Runtime::new().unwrap().block_on(qualify());
}
