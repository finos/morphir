//! Proposed child tests of controlled_originals::assets. Not mounted or run.
//! Mount in assets.rs with #[cfg(test)] #[path = "assets/tests.rs"] mod tests;
//! These are component INPUT tests. They make no browser/profile verdict.
#[path = "tests/end_refusal.rs"]
mod end_refusal;
#[path = "tests/legacy_limits.rs"]
mod legacy_limits;
#[path = "tests/refusals.rs"]
mod refusals;
use super::super::{BoundControlledUiHost, ControlledHostShutdown};
use super::*;
use crate::commands::ui::server::controlled_originals_tests::runtime;
use morphir_mck::workbench::{
    BrowserActionKind, BrowserSourceTerminal, RunConfiguration, load, with_prepared_browser_clients,
};
use sha2::{Digest as _, Sha256};
use std::time::{Duration, Instant};

type Error = Box<dyn std::error::Error + Send + Sync>;
const COMMIT: &str = "e760edeb6a914a1218e833d54fb7bc1c66600433";
const TREE: &str = "0657be42c8077cb86cc27b6d03cba62003f9c64d";
const RECEIPT_SHA: &str = "f9ad187494cc46d76646b245720a99bbfefabf8652cd208e4e79c6b5188f3133";
const TABLE_SHA: &str = "a527add3cf5c5461d23dcf59a740fce58f3becab14c60500ae43b9e9afed1725";

fn failure(message: impl Into<String>) -> Error {
    std::io::Error::other(message.into()).into()
}
fn digest(bytes: &[u8]) -> [u8; 32] {
    Sha256::digest(bytes).into()
}
fn hex_digest(text: &str) -> Result<[u8; 32], Error> {
    if text.len() != 64 || !text.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(failure("fixture digest must have exactly 64 hex digits"));
    }
    let mut digest = [0; 32];
    for (i, byte) in digest.iter_mut().enumerate() {
        *byte = u8::from_str_radix(&text[i * 2..i * 2 + 2], 16)?;
    }
    Ok(digest)
}

struct ExpectedAsset<'a> {
    path: &'a str,
    bytes: usize,
    sha256: [u8; 32],
    mime: &'static str,
}
struct Response {
    path: String,
    status: u16,
    mime: Option<String>,
    bytes: usize,
    sha256: [u8; 32],
}
struct HostObservation {
    responses: Result<Vec<Response>, Error>,
    joined: ControlledHostShutdown,
    prepared_backing: usize,
    actual_backing: Option<usize>,
}

// This helper copies the old helper's real corpus/checker INPUT, not its 8 MiB
// receiving fixture. This separate policy is only asset-component test INPUT.
fn with_two_asset_hosts(
    acquired: &AcquiredObservedWorkbench<'_>,
    expected: &[ExpectedAsset<'_>],
    retained_bytes: u64,
    byte_visits: u64,
    snapshot_read_bytes: u64,
    check_no_auth: bool,
) -> (Result<Vec<HostObservation>, Error>, BrowserSourceTerminal) {
    let corpus_root = tempfile::tempdir().unwrap();
    std::fs::write(
        corpus_root.path().join("cases.json"),
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../morphir-mck/src/workbench/model_originals/workflow/pipeline_controls/cases.json"
        )),
    )
    .unwrap();
    let checker: serde_json::Value = serde_json::from_str(include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../morphir-mck/src/workbench/model_originals/workflow/pipeline_controls/explicit-test-policy.json"
    ))).unwrap();
    let configuration = RunConfiguration::from_json(
        &serde_json::json!({
            "kind":"model-originals-browser", "browser":"chromium", "checker":checker,
            "receiving": {
                "retainedBytes":retained_bytes, "stdoutPrefixBytes":0,
                "stderrPrefixBytes":0, "snapshotReadBytes":snapshot_read_bytes,
                "byteVisits":byte_visits, "records":0
            }
        })
        .to_string(),
    )
    .unwrap();
    let corpus = load(corpus_root.path()).unwrap();
    let runtime = runtime();
    let outcome = with_prepared_browser_clients(&corpus, &configuration, |clients, loans| {
        let end = Instant::now() + Duration::from_secs(30);
        // Intentionally once, outside visit and the actual case/host loop.
        let application = RunObservedApplication::prepare(acquired, loans, end)
            .map_err(|e| failure(format!("application preparation: {e:?}")))?;
        // Record the actual paid raw image once, before visiting any host.
        let prepared_backing = application.image.raw.as_ptr() as usize;
        let mut observations = Vec::new();
        // Joined host owners still retain their real source bindings. Keep them
        // alive through both binds; dropping host1 would revoke this scope.
        let mut joined_hosts = Vec::new();
        let mut selected = Vec::new();
        clients
            .visit(loans, |client, loans| -> Result<(), Error> {
                if selected.len() == 2 {
                    return Ok(());
                }
                let opening = client
                    .actions(loans)
                    .map_err(|e| failure(format!("actual actions: {e:?}")))?
                    .find(|action| {
                        matches!(
                            action.kind(),
                            BrowserActionKind::BeginConnectedOpening { .. }
                        )
                    });
                let Some(opening) = opening else {
                    return Ok(());
                };
                let identity = (client.case_index(), client.run_index());
                if selected.contains(&identity) {
                    return Ok(());
                }
                let stimulus = client
                    .prepare_controlled_host(loans, opening.position())
                    .map_err(|e| failure(format!("actual opening: {e:?}")))?;
                let (observation, host) = runtime.block_on(async {
                    let mut host = BoundControlledUiHost::bind_with_observed_assets(
                        stimulus,
                        &application,
                        loans,
                        end,
                    )
                    .await
                    .map_err(|e| failure(format!("actual asset bind: {e:?}")))?;
                    let actual_backing = host
                        .state
                        .assets
                        .as_ref()
                        .map(|assets| assets.image.raw.as_ptr() as usize);
                    // No assertion/unwrap/early ? occurs after the real host exists
                    // until its actual listener and socket cleanup has been joined.
                    let responses = async {
                        host.start()
                            .map_err(|e| failure(format!("actual start: {e:?}")))?;
                        observe_http_assets(&host, expected, end, check_no_auth).await
                    }
                    .await;
                    let joined = host.shutdown().await;
                    Ok::<_, Error>((
                        HostObservation {
                            responses,
                            joined,
                            prepared_backing,
                            actual_backing,
                        },
                        host,
                    ))
                })?;
                joined_hosts.push(host);
                selected.push(identity);
                observations.push(observation);
                Ok(())
            })
            .map_err(|e| failure(format!("actual client visit: {e:?}")))?;
        // Raw owner disposal remains the existing incomplete-source oracle.
        // This is after all binds and actual joins, before any assertions.
        drop(joined_hosts);
        if selected.len() != 2 {
            return Err(failure(
                "two distinct compiled controlled openings are required",
            ));
        }
        Ok::<_, Error>(observations)
    })
    .unwrap();
    outcome.into_parts()
}

async fn observe_http_assets(
    host: &BoundControlledUiHost,
    expected: &[ExpectedAsset<'_>],
    end: Instant,
    check_no_auth: bool,
) -> Result<Vec<Response>, Error> {
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
        return Err(failure("actual authenticated launch exchange failed"));
    }
    let cookie = launch
        .headers()
        .get(reqwest::header::SET_COOKIE)
        .ok_or_else(|| failure("actual launch cookie missing"))?
        .to_str()?
        .split(';')
        .next()
        .ok_or_else(|| failure("actual launch cookie empty"))?
        .to_owned();
    drop(launch);
    let mut responses = Vec::new();
    if check_no_auth {
        responses.push(fetch(&client, host, "/observed/product-observer.js", None, end).await?);
    }
    for asset in expected {
        responses.push(
            fetch(
                &client,
                host,
                &format!("/observed/{}", asset.path),
                Some(&cookie),
                end,
            )
            .await?,
        );
    }
    // Original index is template DATA, never an unobserved runnable entry.
    responses.push(fetch(&client, host, "/observed/index.html", Some(&cookie), end).await?);
    responses.push(
        fetch(
            &client,
            host,
            "/observed/?mode=connected-originals",
            Some(&cookie),
            end,
        )
        .await?,
    );
    drop(client);
    Ok(responses)
}

async fn fetch(
    client: &reqwest::Client,
    host: &BoundControlledUiHost,
    path: &str,
    cookie: Option<&str>,
    end: Instant,
) -> Result<Response, Error> {
    let mut request = client
        .get(format!("{}{path}", host.base_url()))
        .header("Connection", "close");
    if let Some(cookie) = cookie {
        request = request.header("Cookie", cookie);
    }
    let response = tokio::time::timeout_at(end.into(), request.send()).await??;
    let status = response.status().as_u16();
    let mime = response
        .headers()
        .get(reqwest::header::CONTENT_TYPE)
        .map(|v| v.to_str().map(str::to_owned))
        .transpose()?;
    let body = tokio::time::timeout_at(end.into(), response.bytes()).await??;
    Ok(Response {
        path: path.to_owned(),
        status,
        mime,
        bytes: body.len(),
        sha256: digest(&body),
    })
}

fn assert_observations(
    actual: Result<Vec<HostObservation>, Error>,
    terminal: BrowserSourceTerminal,
    expected: &[ExpectedAsset<'_>],
    check_no_auth: bool,
) {
    let actual = actual.unwrap();
    assert_eq!(actual.len(), 2);
    for host in actual {
        assert_eq!(host.joined, ControlledHostShutdown::Joined);
        assert_ne!(host.prepared_backing, 0);
        assert_eq!(
            host.actual_backing,
            Some(host.prepared_backing),
            "each actual host must retain the same once-prepared raw backing"
        );
        let mut responses = host.responses.unwrap().into_iter();
        if check_no_auth {
            assert_eq!(responses.next().unwrap().status, 401);
        }
        for expected in expected {
            let response = responses.next().unwrap();
            assert_eq!(response.path, format!("/observed/{}", expected.path));
            assert_eq!(response.status, 200, "{}", response.path);
            assert_eq!(response.mime.as_deref(), Some(expected.mime));
            assert_eq!(response.bytes, expected.bytes, "{}", response.path);
            assert_eq!(response.sha256, expected.sha256, "{}", response.path);
        }
        assert_eq!(
            responses.next().unwrap().status,
            503,
            "raw template must refuse"
        );
        assert_eq!(
            responses.next().unwrap().status,
            503,
            "document ingress is not prepared"
        );
        assert!(responses.next().is_none());
    }
    assert!(
        matches!(terminal, BrowserSourceTerminal::Incomplete { .. }),
        "joined physical owners do not fabricate logical source completion"
    );
}

#[test]
fn browser_observed_assets_01_tiny_source_same_run_two_authenticated_hosts_disabled_entry() {
    // Fixed source INPUT. No browser, observer sink or injected execution.
    let root = tempfile::tempdir().unwrap();
    let bodies: [(&str, &[u8]); 3] = [
        ("index.html", b"<!doctype html><div id=\"app\"></div><script type=\"module\" src=\"./bootstrap.js\"></script>"),
        ("observed-bootstrap.js", b"import './product-observer.js';\n"),
        ("product-observer.js", b"export const fixture = 'fixed-input';\n"),
    ];
    for (path, bytes) in bodies {
        std::fs::write(root.path().join(path), bytes).unwrap();
    }
    let files: Vec<_> = bodies
        .iter()
        .map(|(path, bytes)| ApplicationFile {
            path,
            bytes: bytes.len(),
            sha256: digest(bytes),
        })
        .collect();
    let held =
        cap_std::fs::Dir::open_ambient_dir(root.path(), cap_std::ambient_authority()).unwrap();
    let acquired = AcquiredObservedWorkbench {
        root: &held,
        manifest: ApplicationManifest {
            source: ApplicationSource {
                commit: COMMIT,
                tree: TREE,
                build_manifest_sha256: digest(b"tiny fixed source fixture v1"),
            },
            files: &files,
        },
    };
    let expected: Vec<_> = files
        .iter()
        .filter(|f| f.path != "index.html")
        .map(|f| ExpectedAsset {
            path: f.path,
            bytes: f.bytes,
            sha256: f.sha256,
            mime: "text/javascript; charset=utf-8",
        })
        .collect();
    let (actual, terminal) = with_two_asset_hosts(
        &acquired,
        &expected,
        2 * 1024 * 1024,
        4 * 1024 * 1024,
        1024 * 1024,
        true,
    );
    assert_observations(actual, terminal, &expected, true);
}

#[test]
#[ignore = "requires explicit frozen full69 acquisition at MORPHIR_OBSERVED_APPLICATION_BUNDLE; never skips when run"]
fn browser_observed_assets_02_full69_prepared_once_two_hosts_exact_all_static_bytes() {
    let path = std::env::var_os("MORPHIR_OBSERVED_APPLICATION_BUNDLE").expect(
        "set MORPHIR_OBSERVED_APPLICATION_BUNDLE to the frozen receipt/assets.tsv/files directory",
    );
    let bundle = std::path::PathBuf::from(path);
    let receipt = std::fs::read(bundle.join("receipt.json")).unwrap();
    assert_eq!(digest(&receipt), hex_digest(RECEIPT_SHA).unwrap());
    let table_bytes = std::fs::read(bundle.join("assets.tsv")).unwrap();
    assert_eq!(digest(&table_bytes), hex_digest(TABLE_SHA).unwrap());
    let table = std::str::from_utf8(&table_bytes).unwrap();
    let files: Vec<_> = table
        .lines()
        .map(|line| {
            let mut columns = line.split('\t');
            let path = columns.next().unwrap();
            let bytes = columns.next().unwrap().parse().unwrap();
            let sha256 = hex_digest(columns.next().unwrap()).unwrap();
            assert!(columns.next().is_none());
            ApplicationFile {
                path,
                bytes,
                sha256,
            }
        })
        .collect();
    assert_eq!(files.len(), 69);
    assert_eq!(
        files.iter().map(|file| file.bytes).sum::<usize>(),
        15_047_401
    );
    let expected: Vec<_> = files
        .iter()
        .filter(|f| f.path != "index.html")
        .map(|f| ExpectedAsset {
            path: f.path,
            bytes: f.bytes,
            sha256: f.sha256,
            mime: if f.path.ends_with(".js") {
                "text/javascript; charset=utf-8"
            } else if f.path.ends_with(".json") || f.path.ends_with(".map") {
                "application/json"
            } else if f.path.ends_with(".css") {
                "text/css; charset=utf-8"
            } else if f.path.ends_with(".svg") {
                "image/svg+xml"
            } else if f.path.ends_with(".txt") {
                "text/plain; charset=utf-8"
            } else {
                panic!("fixture has unreviewed MIME: {}", f.path)
            },
        })
        .collect();
    assert_eq!(expected.len(), 68);
    let held =
        cap_std::fs::Dir::open_ambient_dir(bundle.join("files"), cap_std::ambient_authority())
            .unwrap();
    let acquired = AcquiredObservedWorkbench {
        root: &held,
        manifest: ApplicationManifest {
            source: ApplicationSource {
                commit: COMMIT,
                tree: TREE,
                build_manifest_sha256: hex_digest(TABLE_SHA).unwrap(),
            },
            files: &files,
        },
    };
    // Explicit sufficient test INPUT. Less than 2B storage and 6B content work:
    // per-host full recopy/rehash cannot pass by spending a second image.
    // Extra receiving terms cover metadata, bounded requested reads and work.
    let (actual, terminal) = with_two_asset_hosts(
        &acquired,
        &expected,
        15_047_401 + 2 * 1024 * 1024,
        45_142_203 + 4 * 1024 * 1024,
        32 * 1024 * 1024,
        false,
    );
    assert_observations(actual, terminal, &expected, false);
}
