//! Proposed child of assets::tests. Explicit historical policy INPUT only.
use super::*;

#[test]
#[ignore = "requires exact frozen full69 acquisition at MORPHIR_OBSERVED_APPLICATION_BUNDLE; never skips when run"]
fn browser_observed_assets_legacy_limits_full69_refuses_old_1mib_and_8mib_receiving() {
    let bundle = std::path::PathBuf::from(
        std::env::var_os("MORPHIR_OBSERVED_APPLICATION_BUNDLE").expect(
            "set MORPHIR_OBSERVED_APPLICATION_BUNDLE to frozen receipt/assets.tsv/files directory",
        ),
    );
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
    for (retained, work, read) in [
        (1_048_576_u64, 1_048_576_u64, 4096_u64),
        (8_388_608, 8_388_608, 0),
    ] {
        let root = tempfile::tempdir().unwrap();
        std::fs::write(root.path().join("cases.json"), include_str!(concat!(env!("CARGO_MANIFEST_DIR"),
            "/../morphir-mck/src/workbench/model_originals/workflow/pipeline_controls/cases.json"))).unwrap();
        let checker: serde_json::Value = serde_json::from_str(include_str!(concat!(env!("CARGO_MANIFEST_DIR"),
            "/../morphir-mck/src/workbench/model_originals/workflow/pipeline_controls/explicit-test-policy.json"))).unwrap();
        // Re-declare the two old receiving documents as caller-supplied INPUT.
        // Existing helpers/defaults are untouched; no larger grant is inferred.
        let configuration = RunConfiguration::from_json(&serde_json::json!({
            "kind":"model-originals-browser", "browser":"chromium", "checker":checker,
            "receiving": { "retainedBytes":retained, "stdoutPrefixBytes":0,
                "stderrPrefixBytes":0, "snapshotReadBytes":read, "byteVisits":work, "records":0 }
        }).to_string()).unwrap();
        let corpus = load(root.path()).unwrap();
        let outcome = with_prepared_browser_clients(&corpus, &configuration, |_, loans| {
            // Exactly the full caller acquisition, before any per-case visit,
            // stimulus preparation, host bind or HTTP/socket effect.
            let actual = RunObservedApplication::prepare(
                &acquired,
                loans,
                Instant::now() + Duration::from_secs(10),
            );
            let funding = matches!(actual, Err(ObservedAssetsFault::Funding(_)));
            drop(actual);
            Ok::<_, std::convert::Infallible>(funding)
        })
        .unwrap();
        let (result, _) = outcome.into_parts();
        assert!(
            result.unwrap(),
            "full69 image must honestly refuse receiving retained={retained}"
        );
    }
}
