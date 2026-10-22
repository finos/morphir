//! Exact fixed entry delivery only; no module evaluation or browser verdict.
use super::*;

const ENTRY: &[u8] = b"<!doctype html><div id=\"app\"></div><script type=\"module\" src=\"./observed-document-entry.js\"></script>";
const ENTRY_PATH: &str = "/observed/?mode=connected-originals";
const BODIES: [(&str, &[u8]); 5] = [
    ("index.html", b"<!doctype html><div id=\"app\"></div><script type=\"module\" src=\"./bootstrap.js\"></script>"),
    ("observed-bootstrap.js", b"import './product-observer.js';\n"),
    ("observed-document-entry.js", b"import './observed-bootstrap.js';\n"),
    ("observed-index.html", ENTRY),
    ("product-observer.js", b"export const fixture = 'fixed-input';\n"),
];

enum HostKind {
    Fused,
    AssetsOnly,
}

struct Fixture {
    _root: tempfile::TempDir,
    held: cap_std::fs::Dir,
}
impl Fixture {
    fn new() -> Self {
        let root = tempfile::tempdir().unwrap();
        for (name, bytes) in BODIES {
            std::fs::write(root.path().join(name), bytes).unwrap();
        }
        let held =
            cap_std::fs::Dir::open_ambient_dir(root.path(), cap_std::ambient_authority()).unwrap();
        Self { _root: root, held }
    }
    fn files(&self) -> Vec<ApplicationFile<'static>> {
        BODIES
            .iter()
            .map(|(path, bytes)| ApplicationFile {
                path,
                bytes: bytes.len(),
                sha256: digest(bytes),
            })
            .collect()
    }
    fn acquired<'a>(&'a self, files: &'a [ApplicationFile<'a>]) -> AcquiredObservedWorkbench<'a> {
        AcquiredObservedWorkbench {
            root: &self.held,
            manifest: ApplicationManifest {
                source: ApplicationSource {
                    commit: COMMIT,
                    tree: TREE,
                    build_manifest_sha256: digest(b"fixed observed template component fixture v1"),
                },
                files,
            },
        }
    }
}

fn requests(
    acquired: &AcquiredObservedWorkbench<'_>,
    kind: HostKind,
    paths: &[&str],
) -> (
    Result<Vec<Response>, Error>,
    ControlledHostShutdown,
    BrowserSourceTerminal,
) {
    requests_with_limits(acquired, kind, paths, FUSED_ENOUGH)
}

fn requests_with_limits(
    acquired: &AcquiredObservedWorkbench<'_>,
    kind: HostKind,
    paths: &[&str],
    limits: Limits,
) -> (
    Result<Vec<Response>, Error>,
    ControlledHostShutdown,
    BrowserSourceTerminal,
) {
    let runtime = runtime();
    let ((actual, joined), terminal) = scope(limits, |clients, loans| {
        let stimulus = first_stimulus(clients, loans).unwrap();
        runtime.block_on(async {
            let end = Instant::now() + Duration::from_secs(30);
            let application = RunObservedApplication::prepare(acquired, loans, end).unwrap();
            let mut host = match kind {
                HostKind::Fused => BoundControlledUiHost::bind_with_observed_document(
                    stimulus,
                    &application,
                    loans,
                    document_limits(),
                    end,
                )
                .await
                .unwrap(),
                HostKind::AssetsOnly => BoundControlledUiHost::bind_with_observed_assets(
                    stimulus,
                    &application,
                    loans,
                    end,
                )
                .await
                .unwrap(),
            };
            let actual = async {
                host.start()
                    .map_err(|e| failure(format!("entry host start: {e:?}")))?;
                let client = reqwest::Client::builder()
                    .redirect(reqwest::redirect::Policy::none())
                    .build()?;
                let launch = tokio::time::timeout_at(
                    end.into(),
                    client
                        .get(host.launch_url())
                        .header("Connection", "close")
                        .send(),
                )
                .await??;
                let cookie = launch
                    .headers()
                    .get(reqwest::header::SET_COOKIE)
                    .ok_or_else(|| failure("actual entry launch cookie missing"))?
                    .to_str()?
                    .split(';')
                    .next()
                    .ok_or_else(|| failure("actual entry launch cookie empty"))?
                    .to_owned();
                drop(launch);
                let mut observed = Vec::new();
                // An unauthenticated request cannot consume an entry ticket.
                observed.push(fetch(&client, &host, ENTRY_PATH, None, end).await?);
                for path in paths {
                    observed.push(fetch(&client, &host, path, Some(&cookie), end).await?);
                }
                Ok::<_, Error>(observed)
            }
            .await;
            let joined = host.shutdown().await;
            (actual, joined)
        })
    });
    (actual, joined, terminal)
}

#[test]
fn browser_observed_entry_01_only_exact_fused_entry_once_same_immutable_bytes() {
    let fixture = Fixture::new();
    let files = fixture.files();
    let acquired = fixture.acquired(&files);
    // Six authenticated attempts consume the existing five-record n+1 ledger.
    let (actual, joined, terminal) = requests(
        &acquired,
        HostKind::Fused,
        &[
            "/observed/?mode=wrong",
            "/observed/observed-index.html",
            ENTRY_PATH,
            ENTRY_PATH,
            "/observed/index.html",
            "/observed/?mode=connected-originals&extra=1",
        ],
    );
    assert_eq!(joined, ControlledHostShutdown::Joined);
    let actual = actual.unwrap();
    assert_eq!(
        actual.iter().map(|r| r.status).collect::<Vec<_>>(),
        [401, 404, 503, 200, 409, 503, 404]
    );
    assert_eq!(actual[3].mime.as_deref(), Some("text/html; charset=utf-8"));
    assert_eq!(actual[3].bytes, ENTRY.len());
    assert_eq!(actual[3].sha256, digest(ENTRY));
    assert!(matches!(terminal, BrowserSourceTerminal::Incomplete { .. }));
}

#[test]
fn browser_observed_entry_02_asset_only_and_missing_recorded_module_refuse() {
    let fixture = Fixture::new();
    let files = fixture.files();
    let acquired = fixture.acquired(&files);
    let (actual, joined, _) = requests(&acquired, HostKind::AssetsOnly, &[ENTRY_PATH]);
    assert_eq!(joined, ControlledHostShutdown::Joined);
    assert_eq!(
        actual.unwrap().iter().map(|r| r.status).collect::<Vec<_>>(),
        [401, 503]
    );
    let missing_module: Vec<_> = fixture
        .files()
        .into_iter()
        .filter(|file| file.path != "observed-document-entry.js")
        .collect();
    let acquired = fixture.acquired(&missing_module);
    let (actual, joined, _) = requests(&acquired, HostKind::Fused, &[ENTRY_PATH]);
    assert_eq!(joined, ControlledHostShutdown::Joined);
    assert_eq!(
        actual.unwrap().iter().map(|r| r.status).collect::<Vec<_>>(),
        [401, 503]
    );
}

#[test]
fn browser_observed_entry_03_missing_duplicate_and_oversized_query_do_not_take_entry() {
    let fixture = Fixture::new();
    let files = fixture.files();
    let acquired = fixture.acquired(&files);
    let (actual, joined, _) = requests(
        &acquired,
        HostKind::Fused,
        &[
            "/observed/",
            "/observed/?mode=connected-originals&mode=connected-originals",
            "/observed/?mode=connected-originalsxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
            ENTRY_PATH,
        ],
    );
    assert_eq!(joined, ControlledHostShutdown::Joined);
    let actual = actual.unwrap();
    assert_eq!(
        actual.iter().map(|r| r.status).collect::<Vec<_>>(),
        [401, 404, 404, 404, 200]
    );
    assert_eq!(actual[4].sha256, digest(ENTRY));
}

#[test]
fn browser_observed_entry_05_retained_actual_peer_cannot_publish_after_source_return() {
    let fixture = Fixture::new();
    let files = fixture.files();
    let acquired = fixture.acquired(&files);
    let runtime = runtime();
    let ((mut host, setup, end), terminal) = scope(FUSED_ENOUGH, |clients, loans| {
        let stimulus = first_stimulus(clients, loans).unwrap();
        runtime.block_on(async {
            let end = Instant::now() + Duration::from_secs(30);
            let application = RunObservedApplication::prepare(&acquired, loans, end).unwrap();
            let mut host = BoundControlledUiHost::bind_with_observed_document(
                stimulus,
                &application,
                loans,
                document_limits(),
                end,
            )
            .await
            .unwrap();
            let setup = async {
                host.start()
                    .map_err(|e| failure(format!("source host start: {e:?}")))?;
                let client = reqwest::Client::builder()
                    .redirect(reqwest::redirect::Policy::none())
                    .build()?;
                let launch = tokio::time::timeout_at(
                    end.into(),
                    client
                        .get(host.launch_url())
                        .header("Connection", "close")
                        .send(),
                )
                .await??;
                let cookie = launch
                    .headers()
                    .get(reqwest::header::SET_COOKIE)
                    .ok_or_else(|| failure("source launch cookie missing"))?
                    .to_str()?
                    .split(';')
                    .next()
                    .ok_or_else(|| failure("source launch cookie empty"))?
                    .to_owned();
                drop(launch);
                drop(client);
                let mut connection = tokio::time::timeout_at(
                    end.into(),
                    tokio::net::TcpStream::connect(host.address()),
                )
                .await??;
                let identity = (connection.local_addr()?, connection.peer_addr()?);
                let first = raw_asset(
                    &mut connection,
                    host.address(),
                    &cookie,
                    "/observed/product-observer.js",
                    end,
                )
                .await?;
                Ok::<_, Error>((connection, identity, cookie, first))
            }
            .await;
            (host, setup, end)
        })
    });
    // The genuine source callback has now returned, while the same admitted
    // TCP peer and controlled host stay retained. No new receiving owner exists.
    let (observed, joined) = runtime.block_on(async {
        let observed = async {
            let (mut connection, before, cookie, first) = setup?;
            let revoked =
                raw_asset(&mut connection, host.address(), &cookie, ENTRY_PATH, end).await?;
            let after = (connection.local_addr()?, connection.peer_addr()?);
            drop(connection);
            Ok::<_, Error>((before, after, first.0, revoked.0))
        }
        .await;
        let joined = host.shutdown().await;
        (observed, joined)
    });
    drop(host);
    assert_eq!(joined, ControlledHostShutdown::Joined);
    let (before, after, first, revoked) = observed.unwrap();
    assert_eq!(before, after);
    assert_eq!(first, 200);
    assert_eq!(revoked, 503);
    assert!(matches!(
        terminal,
        BrowserSourceTerminal::Unfinished { bindings: 1 }
    ));
}

#[test]
#[ignore = "requires exact new72 image at MORPHIR_OBSERVED_ENTRY_APPLICATION_BUNDLE; never skips when run"]
fn browser_observed_entry_04_full72_fixed_source_exact_template_and_all_static_bytes() {
    let bundle = std::path::PathBuf::from(
        std::env::var_os("MORPHIR_OBSERVED_ENTRY_APPLICATION_BUNDLE")
            .expect("set MORPHIR_OBSERVED_ENTRY_APPLICATION_BUNDLE to the frozen 5c714 full image"),
    );
    let receipt_bytes = std::fs::read(bundle.join("receipt.json")).unwrap();
    assert_eq!(
        digest(&receipt_bytes),
        hex_digest("2e3d4d3b067b4f09571a61630f0c1da85541e605e56fc889118e87229cad3644").unwrap()
    );
    let receipt: serde_json::Value = serde_json::from_slice(&receipt_bytes).unwrap();
    let commit = receipt["source"]["commit"].as_str().unwrap();
    let tree = receipt["source"]["tree"].as_str().unwrap();
    assert_eq!(commit, "5c714c4a2ac7975d296ebb1a9a29b63c071c05d2");
    assert_eq!(tree, "6aa0cefa2c316c88433344c9388422f81109e917");
    let table = std::fs::read(bundle.join("assets.tsv")).unwrap();
    let table_digest =
        hex_digest("ad79aa080c9d4e32f50f634f34151d874aabdbb21fc26f1ea89fabea71b89d23").unwrap();
    assert_eq!(digest(&table), table_digest);
    let files: Vec<_> = receipt["files"]
        .as_array()
        .unwrap()
        .iter()
        .map(|file| {
            assert_eq!(file["kind"], "regular");
            ApplicationFile {
                path: file["path"].as_str().unwrap(),
                bytes: usize::try_from(file["bytes"].as_u64().unwrap()).unwrap(),
                sha256: hex_digest(file["sha256"].as_str().unwrap()).unwrap(),
            }
        })
        .collect();
    assert_eq!(files.len(), 72);
    assert_eq!(
        files.iter().map(|file| file.bytes).sum::<usize>(),
        15_121_546
    );
    let held =
        cap_std::fs::Dir::open_ambient_dir(bundle.join("files"), cap_std::ambient_authority())
            .unwrap();
    let acquired = AcquiredObservedWorkbench {
        root: &held,
        manifest: ApplicationManifest {
            source: ApplicationSource {
                commit,
                tree,
                build_manifest_sha256: table_digest,
            },
            files: &files,
        },
    };
    let static_files: Vec<_> = files
        .iter()
        .filter(|file| file.path != ORDINARY_TEMPLATE && file.path != OBSERVED_TEMPLATE)
        .collect();
    let mut paths: Vec<_> = static_files
        .iter()
        .map(|file| format!("/observed/{}", file.path))
        .collect();
    paths.extend([
        ENTRY_PATH.to_owned(),
        "/observed/index.html".to_owned(),
        ENTRY_PATH.to_owned(),
    ]);
    assert_eq!(
        paths.len(),
        files.len() + 1,
        "same existing n+1 ticket ledger"
    );
    let paths: Vec<_> = paths.iter().map(String::as_str).collect();
    // Same image-sized component derivation as the historical full-image test,
    // with the existing document fixture's 8MiB headroom for its real decoder.
    let limits = Limits {
        retained: 15_121_546 + FUSED_ENOUGH.retained,
        work: 3 * 15_121_546 + FUSED_ENOUGH.work,
        read: 32 * 1024 * 1024,
    };
    let (actual, joined, terminal) =
        requests_with_limits(&acquired, HostKind::Fused, &paths, limits);
    assert_eq!(joined, ControlledHostShutdown::Joined);
    let actual = actual.unwrap();
    assert_eq!(actual[0].status, 401);
    for (response, file) in actual[1..].iter().zip(&static_files) {
        assert_eq!(response.status, 200, "{}", file.path);
        assert_eq!(response.bytes, file.bytes, "{}", file.path);
        assert_eq!(response.sha256, file.sha256, "{}", file.path);
    }
    let template = files
        .iter()
        .find(|file| file.path == OBSERVED_TEMPLATE)
        .unwrap();
    let entry = &actual[1 + static_files.len()];
    assert_eq!(entry.status, 200);
    assert_eq!(entry.mime.as_deref(), Some("text/html; charset=utf-8"));
    assert_eq!(entry.bytes, template.bytes);
    assert_eq!(entry.sha256, template.sha256);
    assert_eq!(actual[2 + static_files.len()].status, 503);
    assert_eq!(actual[3 + static_files.len()].status, 409);
    assert!(matches!(terminal, BrowserSourceTerminal::Incomplete { .. }));
}
