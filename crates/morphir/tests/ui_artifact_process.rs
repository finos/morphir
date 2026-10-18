//! A real installed SDK process, reusing this test executable as its guest.
//! The producer constructs recipes and never reads expected digests or replayed responses.
use base64::{Engine as _, engine::general_purpose::STANDARD};
use futures_util::{SinkExt, StreamExt};
use morphir::commands::ui::{
    artifacts::{ArtifactError, ArtifactGenerationInput, PreparedArtifacts},
    protocol::PlaygroundGenerateParams,
    provider::{PlaygroundCapability, playground::NativePlaygroundProvider},
};
use morphir::commands::ui::{provider::SessionCapabilities, server::BoundUiHost};
use morphir::home::MorphirHome;
use morphir_distribution::{
    Channel, ExtensionId, ExtensionInstaller, LocalIndex, Platform, Selection, Sha256Digest,
};
use morphir_extension_sdk::{
    Artifact, Backend, BackendCapability, Extension, ExtensionCapabilities, ExtensionInfo,
    GenerateRequest, GenerateResult, NativeExtension,
    protocol::{ExtensionRequest, methods},
};
use serde_json::{Value, json};
use std::sync::Arc;
use std::{
    io::{self, BufRead, Write},
    path::{Path, PathBuf},
    time::Duration,
};
use tokio_tungstenite::{
    connect_async,
    tungstenite::{Message, client::IntoClientRequest},
};
const ID: &str = "artifact-process-qualification";
const TARGET: &str = "artifact-process-fixture";
const FILE_BYTES: usize = 16 * 1024 * 1024;
// Independently authored before this process fixture; pinned in draft.28
// independent/byte-recipes.json and cross-checked with OpenSSL.
const INDEXED_FILE_HASHES: [&str; 4] = [
    "728f52a85b49e21b090f8aab42eac87b30f1c82bdb3a3890627bc244de6756b0",
    "d42312f945214c8f55c283c08415efdddb975c664bc7ae4b129a6c37b79b87c8",
    "75e9210fb9b010ccd02fc3b824d482d6f1646aa3a5765baba3034423eb1550f7",
    "d5f3e8e4c2a22852ec5d5aa01c92f7ad149031ea896fd3fd70887f425fc30d27",
];
#[derive(Clone, Copy, Debug, Eq, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "kebab-case")]
enum DefaultRecipe {
    Download,
    Binary,
    NulText,
}
impl DefaultRecipe {
    fn parse(text: &str) -> Result<Self, &'static str> {
        match text {
            "download" => Ok(Self::Download),
            "binary" => Ok(Self::Binary),
            "nul-text" => Ok(Self::NulText),
            _ => Err("fixture mode must be download, binary or nul-text"),
        }
    }
    fn as_str(self) -> &'static str {
        match self {
            Self::Download => "download",
            Self::Binary => "binary",
            Self::NulText => "nul-text",
        }
    }
}
#[derive(serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct FixtureConfiguration {
    default_recipe: DefaultRecipe,
}
struct Producer(PathBuf, DefaultRecipe);
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
        // Only this explicitly installed fixture target has these recipe controls.
        // The ordinary UI generation action supplies no fixture-only option.
        let mode = match request.options.get("fixtureMode") {
            None => self.1.as_str(),
            Some(Value::String(mode))
                if [
                    "download",
                    "binary",
                    "nul-text",
                    "small",
                    "lost",
                    "hang",
                    "file-one-over",
                    "set-one-over",
                ]
                .contains(&mode.as_str()) =>
            {
                mode.as_str()
            }
            Some(_) => {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "invalid fixtureMode override",
                )
                .into());
            }
        };
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
        } else if mode == "download" {
            vec![
                Artifact {
                    path: "indexed.bin".into(),
                    binary: true,
                    content: STANDARD.encode(
                        (0..1_048_833)
                            .map(|i| (i % 256) as u8 ^ ((i / 65536) % 256) as u8)
                            .collect::<Vec<_>>(),
                    ),
                },
                Artifact {
                    path: "original.txt".into(),
                    binary: false,
                    content: "\u{feff}Original\r\nline two\r\n".into(),
                },
                Artifact {
                    path: "empty.bin".into(),
                    binary: true,
                    content: String::new(),
                },
            ]
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
    let configuration: FixtureConfiguration =
        serde_json::from_slice(&std::fs::read(directory.join("fixture-config.json"))?)?;
    // Capture the validated host recipe once; requests do not reread local state.
    let guest =
        NativeExtension::backend_only(Producer(directory.clone(), configuration.default_recipe))?;
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
fn install(root: &Path, state: &Path, default_recipe: DefaultRecipe) -> MorphirHome {
    let file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(state.join("fixture-config.json"))
        .unwrap();
    serde_json::to_writer(file, &FixtureConfiguration { default_recipe }).unwrap();
    let index = root.join("index");
    std::fs::create_dir_all(index.join("artifacts")).unwrap();
    std::fs::create_dir_all(index.join("extensions")).unwrap();
    let filename = if cfg!(windows) {
        "artifact-process.exe"
    } else {
        "artifact-process"
    };
    let payload = index.join("artifacts").join(filename);
    std::fs::copy(std::env::current_exe().unwrap(), &payload).unwrap();
    // Linux debug symbols can exceed the installer's unchanged 256 MiB limit.
    // Strip only our private copied payload, never the running test executable.
    #[cfg(unix)]
    assert!(
        std::process::Command::new("strip")
            .arg("-S")
            .arg(&payload)
            .status()
            .expect("platform strip is available")
            .success(),
        "strip the private qualification payload"
    );
    let bytes = std::fs::read(&payload).unwrap();
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
    let home = install(root.path(), &state, DefaultRecipe::Download);
    let provider = NativePlaygroundProvider::in_workspace(home, root.path());
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
            for (artifact, hash) in generated.result.artifacts.iter().zip(INDEXED_FILE_HASHES) {
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
async fn configured_process_defaults() {
    for default_recipe in [DefaultRecipe::Binary, DefaultRecipe::NulText] {
        assert_eq!(
            DefaultRecipe::parse(default_recipe.as_str()).unwrap(),
            default_recipe
        );
        let root = tempfile::tempdir().unwrap();
        let state = root.path().join("state");
        std::fs::create_dir(&state).unwrap();
        let home = install(root.path(), &state, default_recipe);
        let provider = NativePlaygroundProvider::in_workspace(home, root.path());
        let mut input = params(default_recipe.as_str());
        input.options.as_object_mut().unwrap().remove("fixtureMode");
        let generated = provider
            .generate_artifacts(input.try_into().unwrap())
            .await
            .unwrap()
            .unwrap();
        assert!(generated.result.success);
        assert_eq!(generated.result.artifacts.len(), 4);
        for (artifact, expected) in generated.result.artifacts.iter().zip(INDEXED_FILE_HASHES) {
            match default_recipe {
                DefaultRecipe::Binary => {
                    assert!(artifact.binary);
                    let bytes = STANDARD.decode(&artifact.content).unwrap();
                    assert_eq!(bytes.len(), FILE_BYTES);
                    assert_eq!(Sha256Digest::of_bytes(&bytes).to_string(), expected);
                }
                DefaultRecipe::NulText => {
                    assert!(!artifact.binary);
                    assert_eq!(artifact.content.len(), FILE_BYTES);
                    assert!(artifact.content.bytes().all(|byte| byte == 0));
                }
                DefaultRecipe::Download => unreachable!(),
            }
        }
        assert_eq!(
            PreparedArtifacts::inspect(generated.result.artifacts)
                .unwrap()
                .decoded_length(),
            64 * 1024 * 1024
        );
        let captured: GenerateRequest =
            serde_json::from_slice(&std::fs::read(state.join("captured.json")).unwrap()).unwrap();
        assert!(!captured.options.contains_key("fixtureMode"));
        assert_eq!(events(&state, "generate").len(), 1);
        stopped(&state).await;
        println!(
            "configured {} default: real SDK process64MiB with no mode override passed",
            default_recipe.as_str()
        );
    }
    for unknown in ["", "unknown", "Binary", "nul_text", "binary "] {
        assert!(DefaultRecipe::parse(unknown).is_err());
    }
}

type Socket =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;
async fn exchange(socket: &mut Socket, id: u64, method: &str, params: Value) -> Value {
    socket
        .send(Message::Text(
            json!({"jsonrpc":"2.0","id":id,"method":method,"params":params})
                .to_string()
                .into(),
        ))
        .await
        .unwrap();
    let raw = socket.next().await.unwrap().unwrap();
    let response: Value = serde_json::from_str(raw.to_text().unwrap()).unwrap();
    assert_eq!(response["jsonrpc"], "2.0");
    assert_eq!(response["id"], id);
    response
}
fn generation_params(mode: &str) -> Value {
    let input = params(mode);
    json!({"contractVersion":"0.1.0-draft.1","providerId":"playground","generation":{"ir":input.ir,"irVersion":input.ir_version,"target":input.target,"options":input.options}})
}
async fn read_artifact(
    socket: &mut Socket,
    next_id: &mut u64,
    generation: &Value,
    descriptor: &Value,
) -> Vec<u8> {
    let length = descriptor["byteLength"].as_u64().unwrap() as usize;
    assert!(
        length <= FILE_BYTES,
        "fixture reader never allocates beyond the exact per-file bound"
    );
    let mut bytes = Vec::with_capacity(length);
    while bytes.len() < length {
        let offset = bytes.len();
        let reply=exchange(socket,*next_id,"morphir.artifacts.read",json!({"contractVersion":"0.1.0-draft.1","generationId":generation,"artifactId":descriptor["id"],"offset":offset,"maxBytes":65536})).await;
        *next_id += 1;
        let chunk = &reply["result"];
        assert_eq!(chunk["generationId"], *generation);
        assert_eq!(chunk["artifactId"], descriptor["id"]);
        assert_eq!(chunk["offset"], offset);
        let next = STANDARD.decode(chunk["content"].as_str().unwrap()).unwrap();
        assert!(!next.is_empty());
        assert!(next.len() <= 65536);
        assert!(bytes.len() + next.len() <= length);
        bytes.extend(next);
        assert_eq!(chunk["nextOffset"], bytes.len());
    }
    assert_eq!(bytes.len(), length);
    assert_eq!(
        Sha256Digest::of_bytes(&bytes).to_string(),
        descriptor["sha256"]
    );
    bytes
}
async fn authenticated_process_host() {
    let root = tempfile::tempdir().unwrap();
    let state = root.path().join("state");
    std::fs::create_dir(&state).unwrap();
    let home = install(root.path(), &state, DefaultRecipe::Download);
    let host = BoundUiHost::bind(
        "installed-process-session".into(),
        SessionCapabilities {
            playground: Some(Arc::new(NativePlaygroundProvider::in_workspace(
                home,
                root.path(),
            ))),
            ..Default::default()
        },
    )
    .await
    .unwrap();
    let url = host.base_url();
    let observer = host.artifact_observer();
    let launch = host.launch_url();
    let task = tokio::spawn(host.serve());
    let client = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .unwrap();
    let response = client.get(launch).send().await.unwrap();
    let cookie = response.headers()["set-cookie"]
        .to_str()
        .unwrap()
        .split(';')
        .next()
        .unwrap();
    let mut request = (url.replacen("http://", "ws://", 1) + "/rpc")
        .into_client_request()
        .unwrap();
    request.headers_mut().insert("origin", url.parse().unwrap());
    request
        .headers_mut()
        .insert("cookie", cookie.parse().unwrap());
    let (mut socket, _) = connect_async(request.clone()).await.unwrap();
    let initialized = exchange(
        &mut socket,
        1,
        "morphir.session.initialize",
        json!({"protocolVersion":1,"sessionId":"installed-process-session"}),
    )
    .await;
    assert_eq!(initialized["result"]["protocolVersion"], 1);
    let catalog = exchange(&mut socket, 2, "morphir.playground.catalog", json!({})).await;
    assert!(
        catalog["result"]["frontends"]
            .as_array()
            .unwrap()
            .iter()
            .any(|frontend| frontend["languageId"] == "gleam" && frontend["compile"] == true)
    );
    let target = catalog["result"]["targets"]
        .as_array()
        .unwrap()
        .iter()
        .find(|entry| entry["target"] == TARGET)
        .unwrap();
    assert_eq!(target["provider"]["extensionId"], ID);
    assert_eq!(target["provider"]["origin"], "installed");
    let compiled=exchange(&mut socket,3,"morphir.playground.compile",json!({"languageId":"gleam","documents":[{"uri":"file:///src/hello.gleam","languageId":"gleam","version":1,"text":"pub fn hello() {\n  \"world\"\n}\n"}],"package":{"name":"example/hello","exposedModules":[]},"irVersion":"4.0.0","options":{}})).await;
    assert_eq!(
        compiled["result"]["success"], true,
        "actual advertised Gleam frontend compiles"
    );
    let compiled_ir = compiled["result"]["ir"].clone();
    let compiled_ir_version = compiled["result"]["irVersion"].as_str().unwrap().to_owned();
    let manifest = exchange(
        &mut socket,
        4,
        "morphir.artifacts.generate",
        json!({"contractVersion":"0.1.0-draft.1","providerId":"playground","generation":{"ir":compiled_ir,"irVersion":compiled_ir_version,"target":TARGET,"options":{"literal":{"$serde_json::private::RawValue":"true"}}}}),
    )
    .await["result"]
        .clone();
    assert_eq!(manifest["status"], "ready");
    assert_eq!(manifest["producer"]["id"], ID);
    assert_eq!(manifest["producer"]["version"], "0.1.0");
    assert_eq!(manifest["profile"], "morphir/workbench/artifacts");
    assert_eq!(manifest["contractVersion"], "0.1.0-draft.1");
    assert_eq!(manifest["sessionId"], "installed-process-session");
    assert_eq!(manifest["providerId"], "playground");
    assert_eq!(manifest["target"], TARGET);
    assert_eq!(manifest["irVersion"], compiled_ir_version);
    assert_eq!(
        manifest["artifacts"].as_array().unwrap().len(),
        3,
        "browser fixture includes binary, exact text and empty bytes"
    );
    assert_eq!(manifest["artifacts"][0]["byteLength"], 1_048_833);
    const EXPECTED: &str = "fa651153f54c6b07a3b2d6543fdd2601cf423ebe8e5a5e0d278437e6ac5565e0";
    assert_eq!(manifest["artifacts"][0]["sha256"], EXPECTED);
    assert_eq!(events(&state, "generate").len(), 1);
    let captured: GenerateRequest =
        serde_json::from_slice(&std::fs::read(state.join("captured.json")).unwrap()).unwrap();
    assert_eq!(captured.ir, compiled_ir);
    assert_eq!(
        captured.options["literal"],
        params("download").options["literal"]
    );
    stopped(&state).await;
    assert_eq!(observer.snapshot().active_invocations(), 0);
    assert_eq!(observer.snapshot().reserved_generations(), 1);
    let (mut other, _) = connect_async(request).await.unwrap();
    exchange(
        &mut other,
        1,
        "morphir.session.initialize",
        json!({"protocolVersion":1,"sessionId":"installed-process-session"}),
    )
    .await;
    let stolen=exchange(&mut other,2,"morphir.artifacts.read",json!({"contractVersion":"0.1.0-draft.1","generationId":manifest["generationId"],"artifactId":manifest["artifacts"][0]["id"],"offset":0,"maxBytes":1})).await;
    assert_eq!(stolen["error"]["data"]["code"], "artifacts.unknown_handle");
    other.close(None).await.unwrap();
    let mut id = 5;
    for (index, descriptor) in manifest["artifacts"].as_array().unwrap().iter().enumerate() {
        let bytes =
            read_artifact(&mut socket, &mut id, &manifest["generationId"], descriptor).await;
        match index {
            0 => assert_eq!(Sha256Digest::of_bytes(&bytes).to_string(), EXPECTED),
            1 => assert_eq!(bytes, "\u{feff}Original\r\nline two\r\n".as_bytes()),
            2 => assert!(bytes.is_empty()),
            _ => unreachable!(),
        }
    }
    let release = exchange(
        &mut socket,
        id,
        "morphir.artifacts.release",
        json!({"contractVersion":"0.1.0-draft.1","generationId":manifest["generationId"]}),
    )
    .await;
    id += 1;
    assert_eq!(release["result"], json!({}));
    assert_eq!(observer.snapshot().reserved_bytes(), 0);
    assert_eq!(observer.snapshot().reserved_generations(), 0);
    assert_eq!(events(&state, "generate").len(), 1);
    let released_read=exchange(&mut socket,id,"morphir.artifacts.read",json!({"contractVersion":"0.1.0-draft.1","generationId":manifest["generationId"],"artifactId":manifest["artifacts"][0]["id"],"offset":0,"maxBytes":1})).await;
    id += 1;
    assert_eq!(
        released_read["error"]["data"]["code"],
        "artifacts.unknown_handle"
    );
    assert_eq!(events(&state, "generate").len(), 1);
    // The complete process→host→socket chain carries the exact decoded
    // aggregate boundary, not just the smaller downloadable UI fixture.
    let large = exchange(
        &mut socket,
        id,
        "morphir.artifacts.generate",
        generation_params("binary"),
    )
    .await["result"]
        .clone();
    id += 1;
    assert_eq!(large["status"], "ready");
    assert_eq!(observer.snapshot().reserved_bytes(), 64 * 1024 * 1024);
    assert_eq!(large["artifacts"].as_array().unwrap().len(), 4);
    for (descriptor, expected) in large["artifacts"]
        .as_array()
        .unwrap()
        .iter()
        .zip(INDEXED_FILE_HASHES)
    {
        assert_eq!(descriptor["byteLength"], FILE_BYTES);
        assert_eq!(descriptor["sha256"], expected);
        let bytes = read_artifact(&mut socket, &mut id, &large["generationId"], descriptor).await;
        assert_eq!(bytes.len(), FILE_BYTES);
        assert_eq!(Sha256Digest::of_bytes(&bytes).to_string(), expected);
    }
    assert_eq!(events(&state, "generate").len(), 2);
    let captured: GenerateRequest =
        serde_json::from_slice(&std::fs::read(state.join("captured.json")).unwrap()).unwrap();
    assert_eq!(captured.ir, params("binary").ir);
    assert_eq!(
        captured.options["literal"],
        params("binary").options["literal"]
    );
    stopped(&state).await;
    assert_eq!(
        exchange(
            &mut socket,
            id,
            "morphir.artifacts.release",
            json!({"contractVersion":"0.1.0-draft.1","generationId":large["generationId"]})
        )
        .await["result"],
        json!({})
    );
    id += 1;
    assert_eq!(observer.snapshot().reserved_bytes(), 0);
    let next = exchange(
        &mut socket,
        id,
        "morphir.artifacts.generate",
        generation_params("download"),
    )
    .await;
    assert_eq!(next["result"]["status"], "ready");
    assert_eq!(events(&state, "generate").len(), 3);
    socket.close(None).await.unwrap();
    tokio::time::timeout(Duration::from_secs(2), async {
        while observer.snapshot().reserved_generations() != 0 {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    assert_eq!(observer.snapshot().reserved_bytes(), 0);
    assert_eq!(observer.snapshot().active_invocations(), 0);
    stopped(&state).await;
    task.abort();
    println!(
        "installed SDK process → authenticated host: independently fixed bytes, literal inputs, authority, single invocation and release/disconnect cleanup passed"
    );
}
async fn launch_installed_host(
    directory: PathBuf,
    default_recipe: DefaultRecipe,
) -> Result<(), Box<dyn std::error::Error>> {
    // Explicit new scratch ownership; never overwrite a previous run or user state.
    std::fs::create_dir(&directory)?;
    let directory = directory.canonicalize()?;
    let state = directory.join("state");
    std::fs::create_dir(&state)?;
    let home = install(&directory, &state, default_recipe);
    let provider = NativePlaygroundProvider::in_workspace(home, &directory);
    let catalog = provider.catalog().await?;
    let host = BoundUiHost::bind(
        "installed-process-session".into(),
        SessionCapabilities {
            playground: Some(Arc::new(provider)),
            ..Default::default()
        },
    )
    .await?;
    #[cfg(unix)]
    let mut termination =
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
    println!(
        "{}",
        json!({"launchUrl":host.launch_url(),"baseUrl":host.base_url(),"sessionId":"installed-process-session","providerId":"playground","producerId":ID,"producerVersion":"0.1.0","target":TARGET,"irVersion":"4.0.0","fixtureMode":default_recipe.as_str(),"stateDirectory":state,"source":"installed-sdk-process","catalog":catalog})
    );
    std::io::stdout().flush()?;
    let shutdown = async {
        #[cfg(unix)]
        {
            tokio::select! { _=tokio::signal::ctrl_c()=>{}, _=termination.recv()=>{} }
        }
        #[cfg(not(unix))]
        {
            let _ = tokio::signal::ctrl_c().await;
        }
    };
    tokio::select! { result=host.serve()=>result?, ()=shutdown=>{} }
    // Returning drops this executable's runtime and its owned connection tasks.
    Ok(())
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
    let runtime = tokio::runtime::Runtime::new().unwrap();
    if args
        .get(1)
        .is_some_and(|arg| arg == "--artifact-process-host")
    {
        let default_recipe = args
            .get(3)
            .map(|mode| DefaultRecipe::parse(mode.to_str().expect("fixture mode must be UTF-8")))
            .transpose()
            .expect("closed fixture launch mode")
            .unwrap_or(DefaultRecipe::Download);
        assert!(args.len() <= 4, "unexpected fixture launch arguments");
        runtime
            .block_on(launch_installed_host(
                PathBuf::from(
                    args.get(2)
                        .expect("explicit new scratch directory required"),
                ),
                default_recipe,
            ))
            .unwrap();
        return;
    }

    if args.get(1).is_some_and(|arg| arg == "--authenticated-only") {
        runtime.block_on(async {
            tokio::time::timeout(Duration::from_secs(120), authenticated_process_host())
                .await
                .expect("bounded authenticated process qualification");
        });
        return;
    }
    runtime.block_on(async {
        tokio::time::timeout(Duration::from_secs(240), async {
            qualify().await;
            configured_process_defaults().await;
            authenticated_process_host().await;
        })
        .await
        .expect("bounded installed process qualification");
    });
}
