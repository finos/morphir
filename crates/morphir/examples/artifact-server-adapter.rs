//! Actual SDK NativeDirect → registry/invoker → authenticated artifact host.
//! This executable reads fixture inputs only, never cases or expected results.
use base64::{Engine as _, engine::general_purpose::STANDARD};
use futures_util::{SinkExt, StreamExt};
use morphir::commands::ui::{
    protocol::{
        PlaygroundCatalog, PlaygroundCompileParams, PlaygroundCompileResult,
        PlaygroundGenerateParams, PlaygroundGenerateResult, ProviderManifest, ProviderStatus,
    },
    provider::{PlaygroundCapability, SdkGeneration},
};
use morphir::{
    commands::ui::{
        provider::{SessionCapabilities, playground::NativePlaygroundProvider},
        server::BoundUiHost,
    },
    error::CliError,
};
use morphir_distribution::Sha256Digest;
use morphir_extension_sdk::{
    Artifact, Backend, BackendCapability, Extension, ExtensionCapabilities, ExtensionInfo,
    GenerateRequest, GenerateResult, NativeExtension,
};
use morphir_host::Registry;
use morphir_host_native::NativeSource;
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    io::{BufRead, Read, Write},
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
};
use tokio_tungstenite::{
    connect_async,
    tungstenite::{Message, client::IntoClientRequest},
};
type Socket =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;
type Error = Box<dyn std::error::Error + Send + Sync>;
const MAX_FRAME: usize = 1024 * 1024 + 1024;

enum ProfileOffer {
    Exact,
    Absent,
    WrongDraft,
    Unavailable,
}
struct OfferedProvider {
    inner: NativePlaygroundProvider,
    offer: ProfileOffer,
}
#[async_trait::async_trait]
impl PlaygroundCapability for OfferedProvider {
    fn manifest(&self) -> ProviderManifest {
        let mut manifest = self.inner.manifest();
        match self.offer {
            ProfileOffer::Exact => {}
            ProfileOffer::Absent => manifest
                .capabilities
                .retain(|c| c.name != "morphir/workbench/artifacts"),
            ProfileOffer::WrongDraft => {
                for c in &mut manifest.capabilities {
                    if c.name == "morphir/workbench/artifacts" {
                        c.version = "0.1.0-draft.2".into();
                    }
                }
            }
            ProfileOffer::Unavailable => manifest.status = ProviderStatus::Disconnected,
        }
        manifest
    }
    async fn catalog(&self) -> Result<PlaygroundCatalog, CliError> {
        self.inner.catalog().await
    }
    async fn compile(
        &self,
        params: PlaygroundCompileParams,
    ) -> Result<PlaygroundCompileResult, CliError> {
        self.inner.compile(params).await
    }
    async fn generate(
        &self,
        params: PlaygroundGenerateParams,
    ) -> Result<PlaygroundGenerateResult, CliError> {
        self.inner.generate(params).await
    }
    async fn generate_artifacts(
        &self,
        params: morphir::commands::ui::artifacts::ArtifactGenerationInput,
    ) -> Result<Option<SdkGeneration>, CliError> {
        self.inner.generate_artifacts(params).await
    }
}

struct FixtureBackend {
    fixture: Value,
    invocations: Arc<AtomicUsize>,
    control: Arc<FixtureControl>,
}
#[derive(Clone, Copy)]
enum ProducerState {
    Held,
    Success,
    Failure,
}
struct FixtureControl {
    state: std::sync::Mutex<ProducerState>,
    changed: std::sync::Condvar,
}
impl FixtureControl {
    fn set(&self, state: ProducerState) {
        *self.state.lock().expect("fixture control") = state;
        self.changed.notify_all();
    }
    fn wait(&self) -> ProducerState {
        let (state, _) = self
            .changed
            .wait_timeout_while(
                self.state.lock().expect("fixture control"),
                std::time::Duration::from_secs(20),
                |state| matches!(state, ProducerState::Held),
            )
            .expect("fixture control wait");
        *state
    }
}
impl Extension for FixtureBackend {
    fn info() -> ExtensionInfo {
        ExtensionInfo {
            id: "artifact-fixture".into(),
            name: "Independent artifact byte fixture".into(),
            version: "0.1.0".into(),
            ..Default::default()
        }
    }
    fn capabilities() -> ExtensionCapabilities {
        ExtensionCapabilities {
            backend: Some(BackendCapability {
                targets: vec!["fixture".into()],
                ir_versions: vec!["4.0.0".into()],
                generate: true,
            }),
            ..Default::default()
        }
    }
}
impl Backend for FixtureBackend {
    fn target_languages() -> Vec<String> {
        vec!["fixture".into()]
    }
    fn generate(&self, _request: GenerateRequest) -> morphir_extension_sdk::Result<GenerateResult> {
        self.invocations.fetch_add(1, Ordering::SeqCst);
        let completion = self.control.wait();
        let artifacts = self.fixture["artifacts"]
            .as_array()
            .expect("validated fixture")
            .iter()
            .map(|artifact| {
                let content = &artifact["content"];
                let (content, binary) = match content["representation"]
                    .as_str()
                    .expect("fixture content")
                {
                    "utf8-text" => (
                        content["content"]
                            .as_str()
                            .expect("fixture text")
                            .to_owned(),
                        false,
                    ),
                    "literal-binary" => (
                        content["content"]
                            .as_str()
                            .expect("fixture text")
                            .to_owned(),
                        true,
                    ),
                    "binary-recipe" => {
                        let recipe = &content["recipe"];
                        let bytes = match recipe["kind"].as_str().expect("fixture recipe") {
                            "hex" => recipe["hex"]
                                .as_str()
                                .expect("hex")
                                .as_bytes()
                                .as_chunks::<2>()
                                .0
                                .iter()
                                .map(|pair| {
                                    u8::from_str_radix(
                                        std::str::from_utf8(pair).expect("ASCIIhex"),
                                        16,
                                    )
                                    .expect("validated hex")
                                })
                                .collect::<Vec<_>>(),
                            "cycle-u8" => (0..recipe["length"].as_u64().expect("fixture length"))
                                .map(|i| (i % 256) as u8)
                                .collect(),
                            "chunk-indexed-u8" => {
                                let seed = recipe["seed"].as_u64().expect("fixture seed");
                                (0..recipe["length"].as_u64().expect("fixture length"))
                                    .map(|i| (i % 256) as u8 ^ (((i / 65536) + seed) % 256) as u8)
                                    .collect()
                            }
                            _ => unreachable!("validated recipe"),
                        };
                        (STANDARD.encode(bytes), true)
                    }
                    _ => unreachable!("validated fixture content"),
                };
                Artifact {
                    path: artifact["path"].as_str().expect("fixture path").to_owned(),
                    content,
                    binary,
                }
            })
            .collect();
        let diagnostics = serde_json::from_value(self.fixture["diagnostics"].clone())
            .expect("validated typed diagnostics");
        Ok(GenerateResult {
            success: matches!(completion, ProducerState::Success),
            artifacts,
            diagnostics,
        })
    }
}
struct HostTask(tokio::task::JoinHandle<Result<(), CliError>>);
impl Drop for HostTask {
    fn drop(&mut self) {
        self.0.abort();
    }
}
async fn exchange(socket: &mut Socket, raw: String) -> Result<String, Error> {
    socket.send(Message::Text(raw.into())).await?;
    let message = tokio::time::timeout(std::time::Duration::from_secs(20), socket.next())
        .await?
        .ok_or("artifact socket closed")??;
    Ok(message.into_text()?.to_string())
}
fn frame(id: &str, method: &str, params: &str) -> String {
    format!(
        "{{\"jsonrpc\":\"2.0\",\"id\":{id},\"method\":{},\"params\":{params}}}",
        json!(method)
    )
}
fn socket_ended(error: &tokio_tungstenite::tungstenite::Error) -> bool {
    match error {
        tokio_tungstenite::tungstenite::Error::ConnectionClosed
        | tokio_tungstenite::tungstenite::Error::AlreadyClosed => true,
        tokio_tungstenite::tungstenite::Error::Io(error) => matches!(
            error.kind(),
            std::io::ErrorKind::BrokenPipe
                | std::io::ErrorKind::ConnectionReset
                | std::io::ErrorKind::ConnectionAborted
                | std::io::ErrorKind::NotConnected
        ),
        _ => false,
    }
}
fn authentication_refusal(error: &tokio_tungstenite::tungstenite::Error) -> bool {
    matches!(error,tokio_tungstenite::tungstenite::Error::Http(response) if response.status().as_u16()==403)
}
fn input_fixture(input: &Value) -> Result<(), Error> {
    if serde_json::to_vec(input)?.len() > 1024 * 1024 {
        return Err("fixture input exceeds1MiB".into());
    }
    let fixture = &input["fixture"];
    if fixture["producer"] != json!({"id":"artifact-fixture","version":"0.1.0"}) {
        return Err("fixture supports only actual native fixed producer".into());
    }
    let artifacts = fixture["artifacts"]
        .as_array()
        .ok_or("fixture artifacts absent")?;
    if artifacts.len() > 257
        || input["actions"]
            .as_array()
            .ok_or("fixture actions absent")?
            .len()
            > 512
    {
        return Err("fixture inventory/action budget".into());
    }
    let mut size = 0u64;
    for artifact in artifacts {
        let c = &artifact["content"];
        let bytes = match c["representation"].as_str() {
            Some("binary-recipe") => {
                let r = &c["recipe"];
                if r["kind"] == "hex" {
                    let hex = r["hex"].as_str().ok_or("fixture hex absent")?;
                    if !hex.len().is_multiple_of(2) || !hex.bytes().all(|c| c.is_ascii_hexdigit()) {
                        return Err("invalid fixture hex".into());
                    }
                    hex.len() as u64 / 2
                } else if r["kind"] == "cycle-u8" || r["kind"] == "chunk-indexed-u8" {
                    if r["kind"] == "chunk-indexed-u8"
                        && r["seed"].as_u64().is_none_or(|seed| seed > 255)
                    {
                        return Err("invalid seed".into());
                    }
                    r["length"].as_u64().ok_or("fixture length absent")?
                } else {
                    return Err("unknown fixture recipe".into());
                }
            }
            Some("utf8-text" | "literal-binary") => {
                c["content"].as_str().ok_or("fixture text absent")?.len() as u64
            }
            _ => return Err("unknown fixture content".into()),
        };
        if bytes > 16777217 {
            return Err("fixture file work budget".into());
        }
        size = size.checked_add(bytes).ok_or("fixture work overflow")?;
    }
    if size > 67108865 {
        return Err("fixture aggregate work budget".into());
    }
    Ok(())
}
async fn run(input: &Value) -> Result<Value, Error> {
    input_fixture(input)?;
    let invocations = Arc::new(AtomicUsize::new(0));
    let control = Arc::new(FixtureControl {
        state: std::sync::Mutex::new(if input["fixture"]["completion"] == "success" {
            ProducerState::Success
        } else {
            ProducerState::Failure
        }),
        changed: std::sync::Condvar::new(),
    });
    let mut registry = Registry::new();
    registry.register(Arc::new(NativeSource::new(NativeExtension::backend_only(
        FixtureBackend {
            fixture: input["fixture"].clone(),
            invocations: invocations.clone(),
            control: control.clone(),
        },
    )?)))?;
    let provider = NativePlaygroundProvider::from_registry(registry, std::env::current_dir()?);
    let provider = OfferedProvider {
        inner: provider,
        offer: match input["fixture"]["offer"].as_str() {
            Some("exact") => ProfileOffer::Exact,
            Some("absent") => ProfileOffer::Absent,
            Some("wrong-draft") => ProfileOffer::WrongDraft,
            Some("unavailable") => ProfileOffer::Unavailable,
            _ => return Err("unknown fixture offer".into()),
        },
    };
    let host = BoundUiHost::bind(
        "session-fixture".into(),
        SessionCapabilities {
            playground: Some(Arc::new(provider)),
            ..Default::default()
        },
    )
    .await?;
    let url = host.base_url();
    let launch = host.launch_url();
    let usage = host.artifact_observer();
    let _host = HostTask(tokio::spawn(host.serve()));
    let client = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .build()?;
    let response = client.get(launch).send().await?;
    let cookie = response.headers()["set-cookie"]
        .to_str()?
        .split(';')
        .next()
        .ok_or("missing cookie")?
        .to_owned();
    let mut sockets = BTreeMap::<String, Socket>::new();
    let mut captures = BTreeMap::<String, Value>::new();
    let mut pending = BTreeMap::<String, (String, String)>::new();
    let mut events = Vec::new();
    let mut read_id = 100000u64;
    let mut reads = 0usize;
    for action in input["actions"].as_array().ok_or("actions absent")? {
        let connection = action["connection"].as_str().unwrap_or("");
        match action["action"].as_str().ok_or("action absent")? {
            "raw-sized" | "generate-sized" => {
                let prefix = action["prefix"].as_str().ok_or("frame prefix absent")?;
                let size = action["size"]
                    .as_u64()
                    .filter(|n| *n <= 1048577)
                    .ok_or("frame size exceeds budget")? as usize;
                if prefix.len() > size {
                    return Err("frame prefix exceeds size".into());
                }
                let raw = prefix.to_owned() + &" ".repeat(size - prefix.len());
                let socket = sockets.get_mut(connection).ok_or("connection absent")?;
                if let Err(error) = socket.send(Message::Text(raw.into())).await {
                    if !socket_ended(&error) {
                        return Err(error.into());
                    }
                    sockets.remove(connection);
                    tokio::task::yield_now().await;
                    events.push(json!({"event":"connection-ended","connection":connection}));
                    continue;
                }
                let response =
                    tokio::time::timeout(std::time::Duration::from_secs(20), socket.next()).await?;
                match response {
                    Some(Ok(Message::Text(raw))) => {
                        if action["action"] == "generate-sized" {
                            let reply = morphir_mck::json::parse_exact_document(&raw)?;
                            if reply["result"]["status"] == "ready" {
                                captures.insert(
                                    action["generation"]
                                        .as_str()
                                        .ok_or("capture alias absent")?
                                        .to_owned(),
                                    reply["result"].clone(),
                                );
                            }
                            events.push(json!({"event":"generated","connection":connection,"generation":action["generation"],"requestId":action["requestId"],"reply":raw.as_str()}));
                        } else {
                            events.push(
                                json!({"event":"raw","connection":connection,"reply":raw.as_str()}),
                            );
                        }
                    }
                    None | Some(Ok(Message::Close(_))) => {
                        sockets.remove(connection);
                        tokio::task::yield_now().await;
                        events.push(json!({"event":"connection-ended","connection":connection}));
                    }
                    Some(Err(error)) if socket_ended(&error) => {
                        sockets.remove(connection);
                        tokio::task::yield_now().await;
                        events.push(json!({"event":"connection-ended","connection":connection}));
                    }
                    Some(Err(error)) => return Err(error.into()),
                    _ => return Err("unexpected artifact sized-frame response".into()),
                }
            }
            "producer" => {
                let state = match action["state"].as_str() {
                    Some("held") => ProducerState::Held,
                    Some("success") => ProducerState::Success,
                    Some("failure") => ProducerState::Failure,
                    _ => return Err("unknown producer control".into()),
                };
                control.set(state);
                events.push(json!({"event":"producer","state":action["state"]}));
            }
            "start-generate" => {
                let id = action["requestId"]
                    .as_str()
                    .ok_or("request ID absent")?
                    .to_owned();
                id.parse::<u64>()?;
                let alias = action["generation"]
                    .as_str()
                    .ok_or("generation alias absent")?
                    .to_owned();
                let before = invocations.load(Ordering::SeqCst);
                sockets
                    .get_mut(connection)
                    .ok_or("connection absent")?
                    .send(Message::Text(
                        frame(
                            &id,
                            "morphir.artifacts.generate",
                            action["params"].as_str().ok_or("params absent")?,
                        )
                        .into(),
                    ))
                    .await?;
                tokio::time::timeout(std::time::Duration::from_secs(10), async {
                    while invocations.load(Ordering::SeqCst) == before {
                        tokio::task::yield_now().await
                    }
                })
                .await?;
                if pending
                    .insert(connection.to_owned(), (alias.clone(), id))
                    .is_some()
                {
                    return Err("fixture pending invocation replaced".into());
                }
                events.push(json!({"event":"started","connection":connection,"generation":alias}));
            }
            "receive-generate" => {
                let (alias, id) = pending
                    .remove(connection)
                    .ok_or("pending invocation absent")?;
                if action["generation"] != alias {
                    return Err("pending generation differs".into());
                }
                let raw = tokio::time::timeout(
                    std::time::Duration::from_secs(20),
                    sockets
                        .get_mut(connection)
                        .ok_or("connection absent")?
                        .next(),
                )
                .await?
                .ok_or("pending socket closed")??
                .into_text()?
                .to_string();
                let reply = morphir_mck::json::parse_exact_document(&raw)?;
                if reply["result"]["status"] == "ready" {
                    captures.insert(alias.clone(), reply["result"].clone());
                }
                events.push(json!({"event":"generated","connection":connection,"generation":alias,"requestId":id,"reply":raw}));
            }
            "connect" => {
                let mut request =
                    (url.replacen("http://", "ws://", 1) + "/rpc").into_client_request()?;
                let auth = action["authentication"].as_str().ok_or("auth absent")?;
                if auth != "missing-cookie" {
                    request.headers_mut().insert(
                        "cookie",
                        if auth == "wrong-cookie" {
                            "morphir_session=wrong".parse()?
                        } else {
                            cookie.parse()?
                        },
                    );
                }
                if auth != "missing-origin" {
                    request.headers_mut().insert(
                        "origin",
                        if auth == "wrong-origin" {
                            "https://untrusted.invalid".parse()?
                        } else {
                            url.parse()?
                        },
                    );
                }
                if auth == "wrong-host" {
                    request
                        .headers_mut()
                        .insert("host", "untrusted.invalid".parse()?);
                }
                match connect_async(request).await {
                    Ok((socket, _)) => {
                        if sockets.insert(connection.to_owned(), socket).is_some() {
                            return Err("connection reused".into());
                        }
                        events.push(json!({"event":"connected","connection":connection,"status":"accepted"}));
                    }
                    Err(error) if authentication_refusal(&error) => events.push(
                        json!({"event":"connected","connection":connection,"status":"refused"}),
                    ),
                    Err(error) => return Err(error.into()),
                }
            }
            "initialize" => {
                let raw=exchange(sockets.get_mut(connection).ok_or("connection absent")?,frame("1","morphir.session.initialize",&json!({"protocolVersion":1,"sessionId":if action["session"]=="current"{"session-fixture"}else{"wrong-session"}}).to_string())).await?;
                let reply = morphir_mck::json::parse_exact_document(&raw)?;
                events.push(json!({"event":"initialized","connection":connection,"status":if reply["result"]["protocolVersion"]==1{"initialized"}else{"refused"}}));
            }
            "generate" => {
                let id = action["requestId"].as_str().ok_or("request ID absent")?;
                id.parse::<u64>()?;
                let raw = exchange(
                    sockets.get_mut(connection).ok_or("connection absent")?,
                    frame(
                        id,
                        "morphir.artifacts.generate",
                        action["params"].as_str().ok_or("params absent")?,
                    ),
                )
                .await?;
                let reply = morphir_mck::json::parse_exact_document(&raw)?;
                if reply["result"]["status"] == "ready" {
                    captures.insert(
                        action["generation"]
                            .as_str()
                            .ok_or("generation alias absent")?
                            .to_owned(),
                        reply["result"].clone(),
                    );
                }
                events.push(json!({"event":"generated","connection":connection,"generation":action["generation"],"requestId":id,"reply":raw}));
            }
            "read-all" => {
                let capture = captures
                    .get(
                        action["generation"]
                            .as_str()
                            .ok_or("generation alias absent")?,
                    )
                    .ok_or("capture absent")?;
                let index = action["artifactIndex"]
                    .as_u64()
                    .ok_or("artifact index absent")? as usize;
                let descriptor = capture["artifacts"].get(index).ok_or("descriptor absent")?;
                let size = descriptor["byteLength"]
                    .as_u64()
                    .filter(|v| *v <= 16777216)
                    .ok_or("invalid advertised size")? as usize;
                let max = action["maxBytes"]
                    .as_u64()
                    .filter(|v| *v > 0 && *v <= 65536)
                    .ok_or("invalid requested chunk")?;
                let mut assembled = Vec::with_capacity(size);
                let mut chunks = Vec::new();
                while assembled.len() < size {
                    reads += 1;
                    if reads > 4096 {
                        return Err("read work budget".into());
                    }
                    read_id += 1;
                    let params = json!({"contractVersion":"0.1.0-draft.1","generationId":capture["generationId"],"artifactId":descriptor["id"],"offset":assembled.len(),"maxBytes":max});
                    let raw = exchange(
                        sockets.get_mut(connection).ok_or("connection absent")?,
                        frame(
                            &read_id.to_string(),
                            "morphir.artifacts.read",
                            &params.to_string(),
                        ),
                    )
                    .await?;
                    let reply = morphir_mck::json::parse_exact_document(&raw)?;
                    let result = &reply["result"];
                    let encoded = result["content"].as_str().ok_or("chunk content absent")?;
                    let bytes = STANDARD.decode(encoded)?;
                    if STANDARD.encode(&bytes) != encoded
                        || bytes.is_empty()
                        || bytes.len() > 65536
                        || assembled.len() + bytes.len() > size
                    {
                        return Err("invalid actual chunk".into());
                    }
                    chunks.push(json!({"generationId":result["generationId"],"artifactId":result["artifactId"],"offset":result["offset"],"nextOffset":result["nextOffset"],"byteLength":bytes.len(),"sha256":Sha256Digest::of_bytes(&bytes).to_string()}));
                    assembled.extend_from_slice(&bytes);
                }
                events.push(json!({"event":"transferred","connection":connection,"generation":action["generation"],"artifactIndex":index,"maxBytes":max,"chunks":chunks,"byteLength":assembled.len(),"sha256":Sha256Digest::of_bytes(&assembled).to_string()}));
            }
            "read" => {
                let capture = captures
                    .get(
                        action["generation"]
                            .as_str()
                            .ok_or("capture alias absent")?,
                    )
                    .ok_or("capture absent")?;
                let descriptor = capture["artifacts"]
                    .get(action["artifactIndex"].as_u64().ok_or("index absent")? as usize)
                    .ok_or("descriptor absent")?;
                let params = format!(
                    "{{\"contractVersion\":\"0.1.0-draft.1\",\"generationId\":{},\"artifactId\":{},\"offset\":{},\"maxBytes\":{}}}",
                    capture["generationId"],
                    descriptor["id"],
                    action["offset"].as_str().ok_or("offset absent")?,
                    action["maxBytes"].as_str().ok_or("limit absent")?
                );
                let id = action["requestId"].as_str().ok_or("request ID absent")?;
                id.parse::<u64>()?;
                let reply = exchange(
                    sockets.get_mut(connection).ok_or("connection absent")?,
                    frame(id, "morphir.artifacts.read", &params),
                )
                .await?;
                events.push(
                    json!({"event":"read","connection":connection,"requestId":id,"reply":reply}),
                );
            }
            "release" => {
                let capture = captures
                    .get(
                        action["generation"]
                            .as_str()
                            .ok_or("capture alias absent")?,
                    )
                    .ok_or("capture absent")?;
                let id = action["requestId"].as_str().ok_or("request ID absent")?;
                id.parse::<u64>()?;
                let raw=exchange(sockets.get_mut(connection).ok_or("connection absent")?,frame(id,"morphir.artifacts.release",&json!({"contractVersion":"0.1.0-draft.1","generationId":capture["generationId"]}).to_string())).await?;
                events.push(json!({"event":"released","connection":connection,"generation":action["generation"],"requestId":id,"reply":raw}));
            }
            "close" => {
                let mut socket = sockets.remove(connection).ok_or("connection absent")?;
                match socket.close(None).await {
                    Ok(())
                    | Err(
                        tokio_tungstenite::tungstenite::Error::ConnectionClosed
                        | tokio_tungstenite::tungstenite::Error::AlreadyClosed,
                    ) => {}
                    Err(error) => return Err(error.into()),
                }
                while let Some(message) =
                    tokio::time::timeout(std::time::Duration::from_secs(2), socket.next()).await?
                {
                    match message {
                        Ok(Message::Close(_)) => break,
                        Ok(_) => {}
                        Err(_) => break,
                    }
                }
                tokio::task::yield_now().await;
                events.push(json!({"event":"closed","connection":connection}));
            }
            "usage" => {
                let actual = usage.snapshot();
                events.push(json!({"event":"usage","invocations":invocations.load(Ordering::SeqCst),"reservedBytes":actual.reserved_bytes(),"reservedGenerations":actual.reserved_generations(),"activeInvocations":actual.active_invocations()}));
            }
            "raw" => {
                let raw = exchange(
                    sockets.get_mut(connection).ok_or("connection absent")?,
                    action["frame"].as_str().ok_or("frame absent")?.to_owned(),
                )
                .await?;
                events.push(json!({"event":"raw","connection":connection,"reply":raw}));
            }
            _ => return Err("fixture action not yet implemented".into()),
        }
    }
    Ok(json!({"sessionId":"session-fixture","providerId":"playground","events":events}))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn authentication_requires_actual_forbidden_response() {
        use tokio_tungstenite::tungstenite::{Error, http::Response};
        let response = |status| {
            Error::Http(Box::new(
                Response::builder().status(status).body(None).unwrap(),
            ))
        };
        assert!(authentication_refusal(&response(403)));
        for error in [
            response(503),
            response(401),
            Error::Io(std::io::Error::new(
                std::io::ErrorKind::ConnectionReset,
                "independent reset fixture",
            )),
        ] {
            assert!(!authentication_refusal(&error), "{error}");
        }
    }
}
#[tokio::main(flavor = "multi_thread", worker_threads = 4)]
async fn main() -> Result<(), Error> {
    let stdin = std::io::stdin();
    let mut input = stdin.lock();
    let stdout = std::io::stdout();
    let mut output = stdout.lock();
    loop {
        let mut bytes = Vec::new();
        let count = input
            .by_ref()
            .take(MAX_FRAME as u64 + 1)
            .read_until(b'\n', &mut bytes)?;
        if count == 0 {
            break;
        }
        if count > MAX_FRAME || !bytes.ends_with(b"\n") {
            return Err("adapter input framing budget".into());
        }
        let request = morphir_mck::json::parse_exact_document(std::str::from_utf8(&bytes)?)?;
        if request["op"] == "exit" {
            break;
        }
        let mut reply = if request["op"] == "capabilities" {
            json!({"suite":"workbench","contractVersion":"0.1.0-draft.28","binding":"morphir-rust-native-artifact-host","language":"rust","operations":["artifact-server"],"formats":["json"]})
        } else if request["op"] == "artifact-server"
            && request["contractVersion"] == "0.1.0-draft.28"
        {
            json!({"status":"ok","value":run(&request["input"]).await?})
        } else {
            return Err("unsupported adapter operation".into());
        };
        reply["id"] = request["id"].clone();
        let bytes = serde_json::to_vec(&reply)?;
        if bytes.len() > MAX_FRAME {
            return Err("adapter output framing budget".into());
        }
        output.write_all(&bytes)?;
        output.write_all(b"\n")?;
        output.flush()?;
    }
    Ok(())
}
