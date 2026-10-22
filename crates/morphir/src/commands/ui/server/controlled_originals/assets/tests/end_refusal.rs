//! Proposed child of assets::tests. Captures original image-end refusal.
#[path = "end_refusal/preallocation.rs"]
mod preallocation;
use super::*;
use morphir_mck::workbench::{BrowserInputError, BrowserLoans, ControlledHostStimulus};

fn with_asset_stimulus<R>(
    run: impl FnOnce(ControlledHostStimulus, &mut BrowserLoans<'_, '_>) -> R,
) -> (R, BrowserSourceTerminal) {
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
    // Separate asset-component policy INPUT; old helper's snapshotReadBytes=0
    // remains unchanged. This is no production default or profile grant.
    let configuration = RunConfiguration::from_json(
        &serde_json::json!({
            "kind":"model-originals-browser", "browser":"chromium", "checker":checker,
            "receiving": { "retainedBytes":8388608, "stdoutPrefixBytes":0,
                "stderrPrefixBytes":0, "snapshotReadBytes":1048576,
                "byteVisits":8388608, "records":0 }
        })
        .to_string(),
    )
    .unwrap();
    let corpus = load(root.path()).unwrap();
    let mut run = Some(run);
    let mut actual = None;
    let outcome = with_prepared_browser_clients(&corpus, &configuration, |clients, loans| {
        clients.visit(loans, |client, loans| {
            if run.is_none() {
                return Ok(());
            }
            let opening = client.actions(loans)?.find(|action| {
                matches!(
                    action.kind(),
                    BrowserActionKind::BeginConnectedOpening { .. }
                )
            });
            if let Some(opening) = opening {
                let stimulus = client.prepare_controlled_host(loans, opening.position())?;
                actual = Some(run.take().unwrap()(stimulus, loans));
            }
            Ok::<_, BrowserInputError>(())
        })?;
        Ok::<_, BrowserInputError>(())
    })
    .unwrap();
    let (result, terminal) = outcome.into_parts();
    result.unwrap();
    (
        actual.expect("one real compiled controlled opening is required"),
        terminal,
    )
}

#[test]
fn browser_observed_assets_03_prepared_original_end_cannot_be_extended_at_bind() {
    let root = tempfile::tempdir().unwrap();
    let bodies: [(&str, &[u8]); 3] = [
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
                build_manifest_sha256: digest(b"tiny end fixture v1"),
            },
            files: &files,
        },
    };
    let runtime = runtime();
    let ((refused, unexpected_cleanup), _) = with_asset_stimulus(|stimulus, loans| {
        runtime.block_on(async {
            let original_end = Instant::now() + Duration::from_millis(80);
            let application =
                RunObservedApplication::prepare(&acquired, loans, original_end).unwrap();
            tokio::time::sleep_until(original_end.into()).await;
            let actual = BoundControlledUiHost::bind_with_observed_assets(
                stimulus,
                &application,
                loans,
                original_end + Duration::from_secs(2),
            )
            .await;
            match actual {
                Err(ObservedAssetsFault::End) => (true, None),
                Err(_) => (false, None),
                Ok(mut host) => {
                    // Dispose an unexpected real listener owner before asserting.
                    let joined = host.shutdown().await;
                    drop(host);
                    (false, Some(joined))
                }
            }
        })
    });
    assert!(
        refused,
        "a later bind argument must not extend the acquired image's original end"
    );
    assert!(unexpected_cleanup.is_none());
}
