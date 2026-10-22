//! Proposed child of assets::tests. No public owner/ledger or browser verdict.
#[path = "refusals/fused.rs"]
mod fused;
#[path = "refusals/header_funding.rs"]
mod header_funding;
use super::*;
use morphir_mck::workbench::{
    BrowserClients, BrowserLoans, BrowserPreparationErrorKind, ControlledHostStimulus,
};
use tokio::io::{AsyncReadExt as _, AsyncWriteExt as _};

#[derive(Clone, Copy)]
struct Limits {
    retained: u64,
    work: u64,
    read: u64,
}
const ENOUGH: Limits = Limits {
    retained: 2 * 1024 * 1024,
    work: 4 * 1024 * 1024,
    read: 1024 * 1024,
};
const BODIES: [(&str, &[u8]); 3] = [
    ("index.html", b"<!doctype html><div id=\"app\"></div>"),
    (
        "observed-bootstrap.js",
        b"import './product-observer.js';\n",
    ),
    (
        "product-observer.js",
        b"export const fixture = 'fixed-input';\n",
    ),
];
struct Tiny {
    root: tempfile::TempDir,
    held: cap_std::fs::Dir,
}
impl Tiny {
    fn new(write: bool) -> Self {
        let root = tempfile::tempdir().unwrap();
        if write {
            for (name, body) in BODIES {
                std::fs::write(root.path().join(name), body).unwrap();
            }
        }
        let held =
            cap_std::fs::Dir::open_ambient_dir(root.path(), cap_std::ambient_authority()).unwrap();
        Self { root, held }
    }
    fn files(&self) -> Vec<ApplicationFile<'static>> {
        BODIES
            .iter()
            .map(|(path, body)| ApplicationFile {
                path,
                bytes: body.len(),
                sha256: digest(body),
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
                    build_manifest_sha256: digest(b"fixed refusal fixture v1"),
                },
                files,
            },
        }
    }
}
fn corpus_and_configuration(
    limits: Limits,
) -> (
    tempfile::TempDir,
    morphir_mck::workbench::Corpus,
    RunConfiguration,
) {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(
        root.path().join("cases.json"),
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../morphir-mck/src/workbench/model_originals/workflow/pipeline_controls/cases.json"
        )),
    )
    .unwrap();
    let checker: serde_json::Value = serde_json::from_str(include_str!(concat!(env!("CARGO_MANIFEST_DIR"),
        "/../morphir-mck/src/workbench/model_originals/workflow/pipeline_controls/explicit-test-policy.json"))).unwrap();
    let configuration = RunConfiguration::from_json(&serde_json::json!({
        "kind":"model-originals-browser", "browser":"chromium", "checker":checker,
        "receiving": { "retainedBytes":limits.retained, "stdoutPrefixBytes":0,
            "stderrPrefixBytes":0, "snapshotReadBytes":limits.read, "byteVisits":limits.work, "records":0 }
    }).to_string()).unwrap();
    let corpus = load(root.path()).unwrap();
    (root, corpus, configuration)
}
fn scope<R>(
    limits: Limits,
    action: impl FnOnce(BrowserClients<'_>, &mut BrowserLoans<'_, '_>) -> R,
) -> (R, BrowserSourceTerminal) {
    let (_root, corpus, configuration) = corpus_and_configuration(limits);
    let outcome = with_prepared_browser_clients(&corpus, &configuration, |clients, loans| {
        Ok::<_, std::convert::Infallible>(action(clients, loans))
    })
    .unwrap();
    let (result, terminal) = outcome.into_parts();
    (result.unwrap(), terminal)
}
fn first_stimulus(
    clients: BrowserClients<'_>,
    loans: &mut BrowserLoans<'_, '_>,
) -> Result<ControlledHostStimulus, Error> {
    let mut selected = None;
    clients
        .visit(loans, |client, loans| -> Result<(), Error> {
            if selected.is_some() {
                return Ok(());
            }
            let opening = client
                .actions(loans)
                .map_err(|e| failure(format!("actions: {e:?}")))?
                .find(|action| {
                    matches!(
                        action.kind(),
                        BrowserActionKind::BeginConnectedOpening { .. }
                    )
                });
            if let Some(opening) = opening {
                selected = Some(
                    client
                        .prepare_controlled_host(loans, opening.position())
                        .map_err(|e| failure(format!("opening: {e:?}")))?,
                );
            }
            Ok(())
        })
        .map_err(|e| failure(format!("visit: {e:?}")))?;
    selected.ok_or_else(|| failure("one actual controlled opening is required"))
}
fn fault(
    result: Result<RunObservedApplication, ObservedAssetsFault>,
) -> Option<ObservedAssetsFault> {
    match result {
        Ok(application) => {
            drop(application);
            None
        }
        Err(cause) => Some(cause),
    }
}

#[test]
fn browser_observed_assets_refusal_01_zero_scope_and_image_storage_work_before_missing_file_io() {
    let (_root, corpus, configuration) = corpus_and_configuration(Limits {
        retained: 0,
        ..ENOUGH
    });
    let mut entered = false;
    let zero = with_prepared_browser_clients(&corpus, &configuration, |_, _| {
        entered = true;
        Ok::<_, std::convert::Infallible>(())
    });
    assert!(matches!(zero, Err(cause) if cause.kind() == BrowserPreparationErrorKind::Input));
    assert!(
        !entered,
        "zero receiving storage cannot fund the real outer source owner"
    );

    for limits in [
        Limits {
            retained: 65_599,
            ..ENOUGH
        },
        Limits { work: 0, ..ENOUGH },
    ] {
        let tiny = Tiny::new(false);
        let mut declared = tiny.files();
        declared[0].bytes = 65_536;
        declared[1].bytes = 32;
        declared[2].bytes = 32;
        // B=65,600; storage case declares B-1, still enough for outer scope.
        let acquired = tiny.acquired(&declared);
        let ((first, retry), _) = scope(limits, |_, loans| {
            let end = Instant::now() + Duration::from_secs(10);
            let first = fault(RunObservedApplication::prepare(&acquired, loans, end));
            // Correct the actual external input only. Never reset owners.
            for (name, body) in BODIES {
                std::fs::write(tiny.root.path().join(name), body).unwrap();
            }
            let corrected = tiny.files();
            let retry = fault(RunObservedApplication::prepare(
                &tiny.acquired(&corrected),
                loans,
                end,
            ));
            (first, retry)
        });
        assert!(
            matches!(first, Some(ObservedAssetsFault::Funding(_))),
            "funding must win over nonexistent file IO"
        );
        assert!(
            matches!(retry, Some(ObservedAssetsFault::Funding(_))),
            "corrected smaller input must not clear the same owner's first refusal"
        );
    }
}

#[test]
fn browser_observed_assets_refusal_02_zero_read_beats_wrong_hash_and_corrected_retry_is_sticky() {
    let tiny = Tiny::new(true);
    let mut wrong = tiny.files();
    wrong[0].sha256[0] ^= 1;
    let ((first, retry), _) = scope(Limits { read: 0, ..ENOUGH }, |_, loans| {
        let end = Instant::now() + Duration::from_secs(10);
        let first = fault(RunObservedApplication::prepare(
            &tiny.acquired(&wrong),
            loans,
            end,
        ));
        let corrected = tiny.files();
        let retry = fault(RunObservedApplication::prepare(
            &tiny.acquired(&corrected),
            loans,
            end,
        ));
        (first, retry)
    });
    // Existing implementation opens/checks metadata before requesting read
    // permission. This proves before hash scan, not before held file access.
    assert!(matches!(first, Some(ObservedAssetsFault::Funding(_))));
    assert!(matches!(retry, Some(ObservedAssetsFault::Funding(_))));
}

#[test]
fn browser_observed_assets_refusal_03_typed_hash_size_kind_and_unsorted_manifest() {
    for mutation in 0..4 {
        let tiny = Tiny::new(mutation != 3);
        let mut files = tiny.files();
        match mutation {
            0 => files[0].sha256[0] ^= 1,
            1 => files[0].bytes += 1,
            2 => {
                std::fs::remove_file(tiny.root.path().join("index.html")).unwrap();
                std::fs::create_dir(tiny.root.path().join("index.html")).unwrap();
            }
            3 => files.swap(0, 1),
            _ => unreachable!(),
        }
        let (actual, _) = scope(ENOUGH, |_, loans| {
            fault(RunObservedApplication::prepare(
                &tiny.acquired(&files),
                loans,
                Instant::now() + Duration::from_secs(10),
            ))
        });
        match mutation {
            0 => assert!(
                matches!(actual, Some(ObservedAssetsFault::Hash { file: 0, actual }) if actual == digest(BODIES[0].1))
            ),
            1 => assert!(matches!(actual, Some(ObservedAssetsFault::Size))),
            // Some platforms reject a held directory open before file metadata.
            2 => assert!(
                matches!(actual, Some(ObservedAssetsFault::FileKind))
                    || matches!(actual, Some(ObservedAssetsFault::Io(ref e)) if matches!(e.kind(), std::io::ErrorKind::IsADirectory | std::io::ErrorKind::PermissionDenied))
            ),
            3 => assert!(
                matches!(actual, Some(ObservedAssetsFault::Shape)),
                "unsorted table must refuse before nonexistent-file IO"
            ),
            _ => unreachable!(),
        }
    }
}

#[test]
fn browser_observed_assets_refusal_04_foreign_live_outer_scope_bind_and_actual_cleanup() {
    let tiny = Tiny::new(true);
    let files = tiny.files();
    let runtime = runtime();
    let (((foreign, unexpected_cleanup), same_joined), _) =
        scope(ENOUGH, |outer_clients, outer_loans| {
            let end = Instant::now() + Duration::from_secs(10);
            let application =
                RunObservedApplication::prepare(&tiny.acquired(&files), outer_loans, end).unwrap();
            let same_stimulus = first_stimulus(outer_clients, outer_loans).unwrap();
            let (foreign, _) = scope(ENOUGH, |inner_clients, inner_loans| {
                let foreign_stimulus = first_stimulus(inner_clients, inner_loans).unwrap();
                runtime.block_on(async {
                    match BoundControlledUiHost::bind_with_observed_assets(
                        foreign_stimulus,
                        &application,
                        inner_loans,
                        end,
                    )
                    .await
                    {
                        Err(ObservedAssetsFault::Funding(_)) => (true, None),
                        Err(_) => (false, None),
                        Ok(mut host) => {
                            let joined = host.shutdown().await;
                            drop(host);
                            (false, Some(joined))
                        }
                    }
                })
            });
            // The original outer scope remains live. Failed foreign validation must
            // not manufacture permission or poison the actual source's next bind.
            let same_joined = runtime.block_on(async {
                match BoundControlledUiHost::bind_with_observed_assets(
                    same_stimulus,
                    &application,
                    outer_loans,
                    end,
                )
                .await
                {
                    Err(cause) => Err(format!("same-source bind failed: {cause:?}")),
                    Ok(mut host) => {
                        let joined = host.shutdown().await;
                        drop(host);
                        Ok(joined)
                    }
                }
            });
            (foreign, same_joined)
        });
    assert!(foreign);
    assert!(unexpected_cleanup.is_none());
    assert_eq!(same_joined.unwrap(), ControlledHostShutdown::Joined);
}

// Uses the exact same actual TCP connection across all asset requests and source
// revocation. No pooled-client inference or per-byte deadline claim.
async fn raw_asset(
    connection: &mut tokio::net::TcpStream,
    address: std::net::SocketAddr,
    cookie: &str,
    path: &str,
    end: Instant,
) -> Result<(u16, Vec<u8>), Error> {
    let request = format!("GET {path} HTTP/1.1\r\nHost: {address}\r\nCookie: {cookie}\r\n\r\n");
    tokio::time::timeout_at(end.into(), connection.write_all(request.as_bytes())).await??;
    let mut header = Vec::new();
    while !header.ends_with(b"\r\n\r\n") {
        if header.len() >= 8192 {
            return Err(failure("bounded actual HTTP header exceeded"));
        }
        header.push(tokio::time::timeout_at(end.into(), connection.read_u8()).await??);
    }
    let header = std::str::from_utf8(&header)?;
    let status = header
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
        .ok_or_else(|| failure("actual status missing"))?
        .parse()?;
    let length = header
        .lines()
        .find_map(|line| {
            line.split_once(':')
                .filter(|(name, _)| name.eq_ignore_ascii_case("content-length"))
                .map(|(_, value)| value.trim().parse::<usize>())
        })
        .transpose()?
        .ok_or_else(|| failure("actual finite content length missing"))?;
    if length > 1024 * 1024 {
        return Err(failure("bounded actual body exceeded"));
    }
    let mut body = vec![0; length];
    tokio::time::timeout_at(end.into(), connection.read_exact(&mut body)).await??;
    Ok((status, body))
}

#[test]
fn browser_observed_assets_refusal_05_authenticated_duplicate_unknown_and_retained_source_revocation()
 {
    let tiny = Tiny::new(true);
    let files = tiny.files();
    let runtime = runtime();
    let ((mut host, setup, end), terminal) = scope(ENOUGH, |clients, loans| {
        runtime.block_on(async {
            let end = Instant::now() + Duration::from_secs(10);
            let application =
                RunObservedApplication::prepare(&tiny.acquired(&files), loans, end).unwrap();
            let stimulus = first_stimulus(clients, loans).unwrap();
            let mut host = BoundControlledUiHost::bind_with_observed_assets(
                stimulus,
                &application,
                loans,
                end,
            )
            .await
            .unwrap();
            let setup = async {
                host.start().map_err(|e| failure(format!("start: {e:?}")))?;
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
                if launch.status() != reqwest::StatusCode::SEE_OTHER {
                    return Err(failure("launch exchange failed"));
                }
                let cookie = launch
                    .headers()
                    .get(reqwest::header::SET_COOKIE)
                    .ok_or_else(|| failure("cookie missing"))?
                    .to_str()?
                    .split(';')
                    .next()
                    .ok_or_else(|| failure("cookie empty"))?
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
                let duplicate = raw_asset(
                    &mut connection,
                    host.address(),
                    &cookie,
                    "/observed/product-observer.js",
                    end,
                )
                .await?;
                let unknown = raw_asset(
                    &mut connection,
                    host.address(),
                    &cookie,
                    "/observed/missing.js",
                    end,
                )
                .await?;
                Ok::<_, Error>((connection, identity, cookie, first, duplicate.0, unknown.0))
            }
            .await;
            (host, setup, end)
        })
    });
    // Scope callback has returned. Keep the actual connection and host owner.
    let (observed, joined) = runtime.block_on(async {
        let observed = async {
            let (mut connection, before, cookie, first, duplicate, unknown) = setup?;
            let revoked = raw_asset(
                &mut connection,
                host.address(),
                &cookie,
                "/observed/observed-bootstrap.js",
                end,
            )
            .await?;
            let after = (connection.local_addr()?, connection.peer_addr()?);
            drop(connection);
            Ok::<_, Error>((before, after, first, duplicate, unknown, revoked.0))
        }
        .await;
        let joined = host.shutdown().await;
        (observed, joined)
    });
    drop(host);
    assert_eq!(joined, ControlledHostShutdown::Joined);
    let (before, after, first, duplicate, unknown, revoked) = observed.unwrap();
    assert_eq!(before, after);
    assert_eq!(first.0, 200);
    assert_eq!(first.1, BODIES[2].1);
    assert_eq!(duplicate, 409);
    assert_eq!(unknown, 404);
    assert_eq!(revoked, 503);
    assert!(matches!(
        terminal,
        BrowserSourceTerminal::Unfinished { bindings: 1 }
    ));
}

#[test]
fn browser_observed_assets_refusal_06_actual_lookup_tickets_exhaust_while_source_and_end_active() {
    let tiny = Tiny::new(true);
    let files = tiny.files();
    let runtime = runtime();
    let ((observed, joined), _) = scope(ENOUGH, |clients, loans| {
        runtime.block_on(async {
            let end = Instant::now() + Duration::from_secs(10);
            let application =
                RunObservedApplication::prepare(&tiny.acquired(&files), loans, end).unwrap();
            let stimulus = first_stimulus(clients, loans).unwrap();
            let mut host = BoundControlledUiHost::bind_with_observed_assets(
                stimulus,
                &application,
                loans,
                end,
            )
            .await
            .unwrap();
            let observed = async {
                host.start().map_err(|e| failure(format!("start: {e:?}")))?;
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
                if launch.status() != reqwest::StatusCode::SEE_OTHER {
                    return Err(failure("launch exchange failed"));
                }
                let cookie = launch
                    .headers()
                    .get(reqwest::header::SET_COOKIE)
                    .ok_or_else(|| failure("cookie missing"))?
                    .to_str()?
                    .split(';')
                    .next()
                    .ok_or_else(|| failure("cookie empty"))?
                    .to_owned();
                drop(launch);
                drop(client);
                let mut connection = tokio::time::timeout_at(
                    end.into(),
                    tokio::net::TcpStream::connect(host.address()),
                )
                .await??;
                let before = (connection.local_addr()?, connection.peer_addr()?);
                // The real three-record image derives exactly four tickets.
                // Each request uses this same retained authenticated driver.
                let first = raw_asset(
                    &mut connection,
                    host.address(),
                    &cookie,
                    "/observed/product-observer.js",
                    end,
                )
                .await?;
                let duplicate = raw_asset(
                    &mut connection,
                    host.address(),
                    &cookie,
                    "/observed/product-observer.js",
                    end,
                )
                .await?;
                let unknown = raw_asset(
                    &mut connection,
                    host.address(),
                    &cookie,
                    "/observed/missing.js",
                    end,
                )
                .await?;
                let second = raw_asset(
                    &mut connection,
                    host.address(),
                    &cookie,
                    "/observed/observed-bootstrap.js",
                    end,
                )
                .await?;
                let fifth = raw_asset(
                    &mut connection,
                    host.address(),
                    &cookie,
                    "/observed/product-observer.js",
                    end,
                )
                .await?;
                // Capture actual liveness after the fifth response, within the
                // original callback, without fabricating a source/debt receipt.
                let source_active = application.source.while_source_active(|| ()).is_ok();
                let before_end = Instant::now() < end;
                let after = (connection.local_addr()?, connection.peer_addr()?);
                drop(connection);
                Ok::<_, Error>((
                    before,
                    after,
                    first,
                    duplicate.0,
                    unknown.0,
                    second,
                    fifth.0,
                    source_active,
                    before_end,
                ))
            }
            .await;
            let joined = host.shutdown().await;
            drop(host);
            (observed, joined)
        })
    });
    assert_eq!(joined, ControlledHostShutdown::Joined);
    let (before, after, first, duplicate, unknown, second, fifth, source_active, before_end) =
        observed.unwrap();
    assert_eq!(before, after);
    assert_eq!(first.0, 200);
    assert_eq!(first.1, BODIES[2].1);
    assert_eq!(duplicate, 409);
    assert_eq!(unknown, 404);
    assert_eq!(second.0, 200);
    assert_eq!(second.1, BODIES[1].1);
    assert_eq!(fifth, 503);
    assert!(
        source_active,
        "the fifth lookup refused before source revocation"
    );
    assert!(
        before_end,
        "the fifth lookup refused before the original end"
    );
}
