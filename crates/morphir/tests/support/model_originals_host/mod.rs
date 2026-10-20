//! Actual CLI/HTTP/WebSocket machinery; expected source bytes never come from RPC.
use futures_util::{SinkExt, StreamExt};
use morphir_mck::workbench::model_originals::{ModelRelease, SourceFormatVersion};
use serde_json::{Value, json};
use std::{
    fs,
    io::{BufRead, BufReader},
    path::Path,
    process::{Child, Command, Stdio},
    sync::mpsc,
    time::{Duration, Instant},
};
use tokio::net::TcpStream;
use tokio_tungstenite::{
    MaybeTlsStream, WebSocketStream, connect_async,
    tungstenite::{Message, client::IntoClientRequest},
};

const TIMEOUT: Duration = Duration::from_secs(90);
pub const VERSION: &str = "0.1.0-draft.1";
pub const PROFILE: &str = "morphir/workbench/model-originals";
pub const SIDECAR: &[u8] = &[0, 255, 13, 10, 128];

pub struct Process(Option<Child>);
impl Drop for Process {
    fn drop(&mut self) {
        if let Some(child) = &mut self.0 {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

#[derive(Clone, Copy)]
pub enum Layout {
    File,
    Tree,
}

#[derive(Clone, Copy)]
pub enum Format {
    Json,
    Yaml,
    Ion,
}
impl Format {
    fn name(self) -> &'static str {
        match self {
            Self::Json => "json",
            Self::Yaml => "yaml",
            Self::Ion => "ion",
        }
    }
}

pub struct Fixture {
    pub temp: tempfile::TempDir,
    pub primary: String,
    /// Filesystem snapshot taken before the host starts, not host-generated evidence.
    pub originals: Vec<(String, Option<Vec<u8>>)>,
    pub expected_version: SourceFormatVersion,
}
impl Fixture {
    pub fn compile(layout: Layout) -> Self {
        Self::compile_format(layout, Format::Yaml)
    }
    pub fn compile_format(layout: Layout, format: Format) -> Self {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path();
        fs::create_dir(root.join("models")).unwrap();
        let layout_name = match layout {
            Layout::File => "single-file",
            Layout::Tree => "document-tree",
        };
        fs::write(root.join("morphir.toml"), format!("[project]\nname='acme/originals'\nversion='1.0.0'\nsource_directory='models'\nexposed_modules=['api']\n[frontend]\nlanguage='gleam'\n[ir]\nlayout='{layout_name}'\nformat='{}'\n", format.name())).unwrap();
        fs::write(
            root.join("models/api.gleam"),
            "pub type Answer { Answer }\n",
        )
        .unwrap();
        let mut child = Process(Some(
            Command::new(env!("CARGO_BIN_EXE_morphir"))
                .args(["compile", "--json"])
                .current_dir(root)
                .env("MORPHIR_HOME", root.join("home"))
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .spawn()
                .unwrap(),
        ));
        let deadline = Instant::now() + TIMEOUT;
        while child.0.as_mut().unwrap().try_wait().unwrap().is_none() {
            assert!(
                Instant::now() < deadline,
                "actual compiler exceeded deadline"
            );
            std::thread::sleep(Duration::from_millis(10));
        }
        let output = child.0.take().unwrap().wait_with_output().unwrap();
        assert!(
            output.status.success(),
            "actual compile failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        let record: Value =
            serde_json::from_slice(&fs::read(root.join(".morphir/out/compile.json")).unwrap())
                .unwrap();
        assert_eq!(
            record["morphirModelOriginals"],
            json!({"contractVersion":VERSION,"companions":[]}),
            "the genuine writer must declare coverage"
        );
        let primary = match layout {
            Layout::File => format!("morphir-ir.{}", format.name()),
            Layout::Tree => "morphir-ir".to_owned(),
        };
        assert_eq!(record["ir"]["path"], primary);
        let dest = root.join(".morphir/out/compile.dest");
        if matches!(layout, Layout::Tree) {
            // A controlled cooperating writer, not a claim these bytes came from Gleam.
            // All added entries are inside the real writer's declared primary tree.
            let lock = fs::OpenOptions::new()
                .read(true)
                .write(true)
                .open(root.join(".morphir/out/compile.lock"))
                .unwrap();
            fs2::FileExt::lock_exclusive(&lock).unwrap();
            fs::write(dest.join(&primary).join("opaque.bin"), SIDECAR).unwrap();
            fs::write(dest.join(&primary).join("zero.bin"), []).unwrap();
            fs::create_dir(dest.join(&primary).join("empty")).unwrap();
            fs2::FileExt::unlock(&lock).unwrap();
        }
        let mut originals = Vec::new();
        snapshot(&dest, &dest.join(&primary), &mut originals);
        originals.sort_by(|a, b| a.0.as_bytes().cmp(b.0.as_bytes()));
        Self {
            temp,
            primary,
            originals,
            expected_version: match format {
                // Current bounded Ion physical probe is explicitly unavailable.
                // These remain real compiler-produced Ion originals, not opaque stand-ins.
                Format::Ion => SourceFormatVersion::NotReported,
                _ => SourceFormatVersion::Reported(ModelRelease::parse("4.0.0").unwrap()),
            },
        }
    }
    pub fn replace_primary(&mut self, bytes: &[u8], expected: SourceFormatVersion) {
        let dest = self.root().join(".morphir/out/compile.dest");
        assert!(dest.join(&self.primary).is_file());
        let lock = fs::OpenOptions::new()
            .read(true)
            .write(true)
            .open(self.root().join(".morphir/out/compile.lock"))
            .unwrap();
        fs2::FileExt::lock_exclusive(&lock).unwrap();
        fs::write(dest.join(&self.primary), bytes).unwrap();
        self.originals.clear();
        snapshot(&dest, &dest.join(&self.primary), &mut self.originals);
        fs2::FileExt::unlock(&lock).unwrap();
        self.expected_version = expected;
    }
    pub fn root(&self) -> &Path {
        self.temp.path()
    }
}
fn snapshot(base: &Path, path: &Path, entries: &mut Vec<(String, Option<Vec<u8>>)>) {
    let relative = path
        .strip_prefix(base)
        .unwrap()
        .components()
        .map(|c| c.as_os_str().to_str().unwrap())
        .collect::<Vec<_>>()
        .join("/");
    let metadata = fs::symlink_metadata(path).unwrap();
    assert!(!metadata.file_type().is_symlink());
    if metadata.is_dir() {
        entries.push((relative, None));
        for entry in fs::read_dir(path).unwrap() {
            snapshot(base, &entry.unwrap().path(), entries);
        }
    } else {
        assert!(metadata.is_file());
        entries.push((relative, Some(fs::read(path).unwrap())));
    }
}

pub struct Host {
    _process: Process,
    pub base: String,
    pub cookie: String,
    pub manifest: Value,
    client: reqwest::Client,
}
impl Host {
    pub async fn launch(fixture: &Fixture) -> Self {
        let mut child = Command::new(env!("CARGO_BIN_EXE_morphir"))
            .args(["ui", "--no-open"])
            .arg(fixture.root())
            .current_dir(fixture.root())
            .env("MORPHIR_HOME", fixture.root().join("home"))
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        let stderr = child.stderr.take().unwrap();
        let process = Process(Some(child));
        let (sender, receiver) = mpsc::channel();
        std::thread::spawn(move || {
            for line in BufReader::new(stderr).lines() {
                let Ok(line) = line else { break };
                if let Some(url) = line.strip_prefix("Morphir UI: ") {
                    let _ = sender.send(url.to_owned());
                }
            }
        });
        let launch = receiver
            .recv_timeout(TIMEOUT)
            .expect("actual CLI must print its launch URL");
        let parsed = reqwest::Url::parse(&launch).unwrap();
        assert_eq!(parsed.scheme(), "http");
        assert_eq!(parsed.host_str(), Some("127.0.0.1"));
        let base = parsed.origin().ascii_serialization();
        let client = reqwest::Client::builder()
            .timeout(TIMEOUT)
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .unwrap();
        assert_eq!(
            client
                .get(format!("{base}/api/session"))
                .send()
                .await
                .unwrap()
                .status(),
            reqwest::StatusCode::UNAUTHORIZED
        );
        let response = client.get(launch).send().await.unwrap();
        assert!(response.status().is_redirection());
        let cookie = response.headers()["set-cookie"]
            .to_str()
            .unwrap()
            .split(';')
            .next()
            .unwrap()
            .to_owned();
        let manifest = client
            .get(format!("{base}/api/session"))
            .header("cookie", &cookie)
            .send()
            .await
            .unwrap();
        assert_eq!(manifest.status(), reqwest::StatusCode::OK);
        let manifest = manifest.json().await.unwrap();
        Self {
            _process: process,
            base,
            cookie,
            manifest,
            client,
        }
    }
    fn socket_request(&self) -> tokio_tungstenite::tungstenite::handshake::client::Request {
        let mut request = format!("{}/rpc", self.base.replacen("http://", "ws://", 1))
            .into_client_request()
            .unwrap();
        request
            .headers_mut()
            .insert("origin", self.base.parse().unwrap());
        request
            .headers_mut()
            .insert("cookie", self.cookie.parse().unwrap());
        request
    }
    pub async fn prove_authentication(&self) {
        let mut missing = self.socket_request();
        missing.headers_mut().remove("cookie");
        let error = connect_async(missing).await.unwrap_err();
        assert!(
            matches!(error, tokio_tungstenite::tungstenite::Error::Http(ref response) if response.status().as_u16() == 401)
        );
        let mut foreign = self.socket_request();
        foreign
            .headers_mut()
            .insert("origin", "http://example.invalid".parse().unwrap());
        let error = connect_async(foreign).await.unwrap_err();
        assert!(
            matches!(error, tokio_tungstenite::tungstenite::Error::Http(ref response) if response.status().as_u16() == 403)
        );
        assert_eq!(
            self.client
                .get(format!("{}/api/session", self.base))
                .header("cookie", "morphir=wrong")
                .send()
                .await
                .unwrap()
                .status(),
            reqwest::StatusCode::UNAUTHORIZED
        );
    }
    pub async fn connect(&self) -> Socket {
        let (inner, _) = connect_async(self.socket_request()).await.unwrap();
        let mut socket = Socket { inner, next: 1 };
        let initialized = socket
            .call(
                "morphir.session.initialize",
                json!({"protocolVersion":1,"sessionId":self.manifest["sessionId"]}),
            )
            .await;
        assert!(initialized["error"].is_null(), "{initialized}");
        socket
    }
}
pub struct Socket {
    inner: WebSocketStream<MaybeTlsStream<TcpStream>>,
    next: u64,
}
impl Socket {
    pub async fn raw_call(&mut self, method: &str, params: Value) -> (String, String) {
        let id = self.next;
        self.next += 1;
        let request = json!({"jsonrpc":"2.0","id":id,"method":method,"params":params}).to_string();
        let reply = self.literal(&request).await;
        let envelope: Value = serde_json::from_str(&reply).unwrap();
        assert_eq!(envelope["jsonrpc"], "2.0");
        assert_eq!(envelope["id"], id);
        (request, reply)
    }
    /// Actual literal bytes, including malformed controls. No normalization.
    /// Callers use separate IDs so this does not synthesize the normal ID ledger.
    pub async fn literal(&mut self, request: &str) -> String {
        self.inner
            .send(Message::Text(request.to_owned().into()))
            .await
            .unwrap();
        tokio::time::timeout(TIMEOUT, async {
            loop {
                match self.inner.next().await.expect("socket closed").unwrap() {
                    Message::Text(text) => break text.to_string(),
                    Message::Ping(_) | Message::Pong(_) => (),
                    other => panic!("unexpected RPC frame: {other:?}"),
                }
            }
        })
        .await
        .expect("actual RPC deadline")
    }
    pub async fn call(&mut self, method: &str, params: Value) -> Value {
        serde_json::from_str(&self.raw_call(method, params).await.1).unwrap()
    }
    pub async fn close(mut self) {
        self.inner.close(None).await.unwrap();
    }
}

pub fn capture_params(source: &Value, project: &str) -> Value {
    json!({"contractVersion":VERSION,"source":{"providerId":source["providerId"],"locator":source["locator"]},"projectId":project,"scope":"complete","semantic":"none"})
}
