use super::*;
use cap_std::fs::Dir;
use morphir_devkit::{IrDescriptor, IrLayout, TaskId, TaskResult};
use std::path::Path;

#[test]
fn owns_exact_declared_sources_and_empty_directories_without_scratch() {
    let tmp = tempfile::tempdir().unwrap();
    let dest = tmp.path().join("compile.dest");
    std::fs::create_dir_all(dest.join("model/empty")).unwrap();
    std::fs::create_dir_all(dest.join("notes")).unwrap();
    std::fs::write(
        dest.join("model/header.json"),
        b"\r\n {\"formatVersion\":4}\r\n",
    )
    .unwrap();
    std::fs::write(dest.join("notes/opaque.bin"), [0, 255, 13, 10]).unwrap();
    std::fs::write(dest.join("scratch"), b"not model owned").unwrap();
    let mut record = TaskResult::new(&TaskId::compile(), Path::new(""));
    record.ir = Some(IrDescriptor {
        path: "model".into(),
        layout: IrLayout::DocumentTree,
        format: "json".into(),
        version: "v4".into(),
    });
    record.extra.insert("morphirModelOriginals".into(), serde_json::json!({"contractVersion":"0.1.0-draft.1","companions":[{"kind":"file","path":"notes/opaque.bin"}]}));
    record.write(&tmp.path().join("compile.json")).unwrap();
    let raw_record = std::fs::read(tmp.path().join("compile.json")).unwrap();
    let dir = Dir::open_ambient_dir(tmp.path(), cap_std::ambient_authority()).unwrap();
    let capture = capture_compiled(
        &dir,
        &SelectedModule::parse("").unwrap(),
        CaptureScope::Complete,
        &CaptureControl::new(),
    )
    .unwrap()
    .ready()
    .unwrap();
    std::fs::remove_dir_all(&dest).unwrap();
    std::fs::write(tmp.path().join("compile.json"), b"changed").unwrap();
    let paths: Vec<_> = capture
        .entries()
        .iter()
        .map(|entry| entry.path().as_str())
        .collect();
    assert_eq!(
        paths,
        [
            "model",
            "model/empty",
            "model/header.json",
            "notes/opaque.bin"
        ]
    );
    assert_eq!(
        capture.file_bytes(&SourcePath::parse("notes/opaque.bin").unwrap()),
        Some(&[0, 255, 13, 10][..])
    );
    assert_eq!(capture.record().byte_length(), raw_record.len());
    assert_eq!(
        capture.record().sha256(),
        &morphir_distribution::Sha256Digest::of_bytes(&raw_record)
    );
    assert_eq!(capture.source_byte_length(), 28);
    assert_eq!(capture.coverage(), CaptureScope::Complete);
}

fn fixture(declaration: Option<&str>) -> (tempfile::TempDir, Dir) {
    let tmp = tempfile::tempdir().unwrap();
    std::fs::create_dir(tmp.path().join("compile.dest")).unwrap();
    std::fs::write(
        tmp.path().join("compile.dest/model.json"),
        b"\xef\xbb\xbf{\"formatVersion\":4}\r\n",
    )
    .unwrap();
    let declaration = declaration
        .map(|value| format!(",\"morphirModelOriginals\":{value}"))
        .unwrap_or_default();
    std::fs::write(tmp.path().join("compile.json"), format!(r#"{{"schema":1,"task":"compile","module":"","completedAt":"now","ir":{{"path":"model.json","layout":"single-file","format":"json","version":"v4"}}{declaration}}}"#)).unwrap();
    let dir = Dir::open_ambient_dir(tmp.path(), cap_std::ambient_authority()).unwrap();
    (tmp, dir)
}
fn capture(dir: &Dir, scope: CaptureScope) -> Result<CaptureResult, CaptureError> {
    capture_compiled(
        dir,
        &SelectedModule::parse("").unwrap(),
        scope,
        &CaptureControl::new(),
    )
}

#[test]
fn complete_requires_positive_declaration_without_scanning_scratch() {
    let (tmp, dir) = fixture(None);
    std::fs::write(tmp.path().join("compile.dest/foreign"), [255]).unwrap();
    assert!(matches!(
        capture(&dir, CaptureScope::Complete).unwrap(),
        CaptureResult::Unavailable(CaptureUnavailable::CompanionsUndeclared)
    ));
    assert_eq!(
        capture(&dir, CaptureScope::Primary)
            .unwrap()
            .ready()
            .unwrap()
            .entries()
            .len(),
        1
    );
    let (_tmp, dir) = fixture(Some(
        r#"{"contractVersion":"0.1.0-draft.1","companions":[]}"#,
    ));
    assert_eq!(
        capture(&dir, CaptureScope::Complete)
            .unwrap()
            .ready()
            .unwrap()
            .coverage(),
        CaptureScope::Complete
    );
}

#[test]
fn invalid_declaration_is_out_of_scope_for_primary_and_never_opens_companions() {
    for value in [
        r#"{"contractVersion":"0.1.0-draft.1","companions":[],"extra":false}"#,
        r#"{"contractVersion":"0.1.0-draft.1","companions":[],"companions":[]}"#,
        r#"{"contractVersion":"0.1.0-draft.1","companions":[{"kind":"file","path":"../secret"}]}"#,
        r#"{"contractVersion":"0.1.0-draft.1","companions":[{"kind":"file","path":"missing","extra":1}]}"#,
        r#"{"contractVersion":"wrong","companions":[]}"#,
        r#"{"contractVersion":"0.1.0-draft.1","companions":[{"kind":"file","path":"missing","path":"missing"}]}"#,
    ] {
        let (_tmp, dir) = fixture(Some(value));
        assert!(
            matches!(
                capture(&dir, CaptureScope::Complete),
                Err(CaptureError::InvalidDeclaration)
            ),
            "{value}"
        );
        assert_eq!(
            capture(&dir, CaptureScope::Primary)
                .unwrap()
                .ready()
                .unwrap()
                .entries()
                .len(),
            1
        );
    }
}

#[test]
fn source_paths_preserve_the_source_budget_and_shared_portability() {
    let long = std::iter::repeat_n("a".repeat(100), 20)
        .collect::<Vec<_>>()
        .join("/");
    assert!(SourcePath::parse(&long).is_ok()); // >1024UTF16 is legal for sources.
    let exact = (0..40)
        .map(|_| "a".repeat(99))
        .collect::<Vec<_>>()
        .join("/")
        + "a";
    assert_eq!(exact.len(), 4000);
    assert!(SourcePath::parse(&exact).is_ok());
    assert_eq!(
        SourcePath::parse(&(exact + "a")),
        Err(CaptureError::InvalidPath)
    );
    for bad in [
        "/absolute",
        "../secret",
        "a/./b",
        "a//b",
        "C:/path",
        "a\\b",
        "NUL",
        "trailing.",
        "a\u{7f}",
        "a\u{85}",
    ] {
        assert_eq!(
            SourcePath::parse(bad),
            Err(CaptureError::InvalidPath),
            "{bad:?}"
        );
    }
}

#[test]
fn separate_record_source_metadata_and_descendant_limits_are_inclusive() {
    let (_tmp, dir) = fixture(Some(
        r#"{"contractVersion":"0.1.0-draft.1","companions":[]}"#,
    ));
    let baseline = capture(&dir, CaptureScope::Complete)
        .unwrap()
        .ready()
        .unwrap();
    let limits = capture::Limits {
        source: baseline.source_byte_length(),
        record: baseline.record().byte_length(),
        metadata: baseline.metadata_byte_length(),
        descendants: 0,
    };
    let run = |limits| {
        capture::capture_with_limits(
            &dir,
            &SelectedModule::parse("").unwrap(),
            CaptureScope::Complete,
            &CaptureControl::new(),
            limits,
        )
    };
    assert!(run(limits).is_ok());
    assert!(matches!(
        run(capture::Limits {
            source: limits.source - 1,
            ..limits
        }),
        Err(CaptureError::SourceLimit)
    ));
    assert!(matches!(
        run(capture::Limits {
            record: limits.record - 1,
            ..limits
        }),
        Err(CaptureError::RecordLimit)
    ));
    assert!(matches!(
        run(capture::Limits {
            metadata: limits.metadata - 1,
            ..limits
        }),
        Err(CaptureError::InventoryLimit)
    ));
    // The full record is larger than source budget, proving it is not charged
    // against the independently exact original-source credit.
    assert!(limits.record > limits.source);
}

#[test]
fn root_alias_overlap_and_implicit_parent_aliases_refuse_whole_capture() {
    for paths in [
        vec!["model.json"],
        vec!["MODEL.JSON"],
        vec!["data", "data-b", "data/child"],
        vec!["Dir/a", "dir/b"],
        vec!["Straße/a", "STRASSE/b"],
    ] {
        let roots: Vec<_> = paths
            .iter()
            .map(|path| serde_json::json!({"kind":"directory","path":path}))
            .collect();
        let value =
            serde_json::json!({"contractVersion":CONTRACT_VERSION,"companions":roots}).to_string();
        let (_tmp, dir) = fixture(Some(&value));
        assert!(
            matches!(
                capture(&dir, CaptureScope::Complete),
                Err(CaptureError::InvalidPathSet)
            ),
            "{paths:?}"
        );
    }
}

#[test]
fn frozen_projection_plan_has_only_primary_bytes_from_the_same_capture() {
    let (tmp, dir) = fixture(Some(
        r#"{"contractVersion":"0.1.0-draft.1","companions":[{"kind":"file","path":"sidecar"}]}"#,
    ));
    std::fs::write(tmp.path().join("compile.dest/sidecar"), b"metadata").unwrap();
    let sources = capture(&dir, CaptureScope::Complete)
        .unwrap()
        .ready()
        .unwrap();
    std::fs::write(tmp.path().join("compile.dest/model.json"), b"different").unwrap();
    let plan = sources.projection_plan();
    assert_eq!(plan.entries().count(), 1);
    assert_eq!(
        plan.file_bytes(&SourcePath::parse("model.json").unwrap()),
        Some(&b"\xef\xbb\xbf{\"formatVersion\":4}\r\n"[..])
    );
    assert!(
        plan.file_bytes(&SourcePath::parse("sidecar").unwrap())
            .is_none()
    );
    assert_eq!(
        plan.descriptor().version(),
        morphir_common::ir_transport::IrVersion::V4
    ); // selector, not source version
}

#[test]
fn opaque_bookkeeping_and_escaped_known_members_remain_literal() {
    let (tmp, dir) = fixture(None);
    let record = std::fs::read_to_string(tmp.path().join("compile.json")).unwrap();
    let record = record.replace("\"compile\"", "\"com\\u0070ile\"");
    let record = record.strip_suffix('}').unwrap().to_owned()
        + r#", "opaque":{"$serde_json::private::RawValue":"{\"x\":1,\"x\":2}"}}"#;
    std::fs::write(tmp.path().join("compile.json"), &record).unwrap();
    let sources = capture(&dir, CaptureScope::Primary)
        .unwrap()
        .ready()
        .unwrap();
    assert_eq!(
        sources.record.sha256(),
        &morphir_distribution::Sha256Digest::of_bytes(record.as_bytes())
    );
    assert_eq!(sources.record.byte_length(), record.len());
}

#[test]
fn inventory_digest_has_fixed_independently_authored_preimage_and_excludes_ids() {
    // SHA256 literals independently authored from the documented preimage with
    // Bun node:crypto; neither the capture nor its serializer supplied them.
    let (_tmp, dir) = fixture(None);
    let first = capture(&dir, CaptureScope::Primary)
        .unwrap()
        .ready()
        .unwrap();
    let second = capture(&dir, CaptureScope::Primary)
        .unwrap()
        .ready()
        .unwrap();
    assert_ne!(
        first.entries()[0].entry_id(),
        second.entries()[0].entry_id()
    );
    assert_eq!(
        first.entries()[0].sha256().unwrap(),
        &morphir_distribution::Sha256Digest::parse(
            "8ba0c865ed6546595b4f3cd010b125918f656476d10c89703e4b84587f119c8a"
        )
        .unwrap()
    );
    assert_eq!(
        first.inventory_sha256(),
        &morphir_distribution::Sha256Digest::parse(
            "c9b02527158788e7a2d6cf055d11450c37ebf7b6dda0cc2ead369c9e2e66c340"
        )
        .unwrap()
    );
    assert_eq!(first.inventory_sha256(), second.inventory_sha256());
}

#[test]
fn selected_root_count_and_root_depth_are_bounded_before_filesystem_reads() {
    let (_tmp, dir) = fixture(Some(&serde_json::json!({"contractVersion":CONTRACT_VERSION,"companions": (0..64).map(|n| serde_json::json!({"kind":"file","path":format!("missing-{n}")})).collect::<Vec<_>>()} ).to_string()));
    assert!(matches!(
        capture(&dir, CaptureScope::Complete),
        Err(CaptureError::InvalidDeclaration)
    ));
    for count in [128, 129] {
        let path = std::iter::repeat_n("a", count)
            .collect::<Vec<_>>()
            .join("/");
        let (_tmp, dir) = fixture(Some(&serde_json::json!({"contractVersion":CONTRACT_VERSION,"companions":[{"kind":"directory","path":path}]}).to_string()));
        let result = capture(&dir, CaptureScope::Complete);
        assert!(
            matches!(result, Err(CaptureError::CaptureFailed)) && count == 128
                || matches!(result, Err(CaptureError::InvalidDeclaration)) && count == 129
        );
    }
}

#[test]
fn actual_tree_entries_depth_and_empty_directories_are_bounded() {
    let (tmp, dir) = fixture(None);
    let record_path = tmp.path().join("compile.json");
    let original_record = std::fs::read_to_string(&record_path).unwrap();
    std::fs::write(
        &record_path,
        original_record
            .replace("\"model.json\"", "\"tree\"")
            .replace("single-file", "document-tree"),
    )
    .unwrap();
    std::fs::create_dir_all(tmp.path().join("compile.dest/tree/empty")).unwrap();
    std::fs::write(tmp.path().join("compile.dest/tree/zero"), []).unwrap();
    let limits = capture::Limits {
        descendants: 2,
        ..Default::default()
    };
    let run = |limits| {
        capture::capture_with_limits(
            &dir,
            &SelectedModule::parse("").unwrap(),
            CaptureScope::Primary,
            &CaptureControl::new(),
            limits,
        )
    };
    let sources = run(limits).unwrap().ready().unwrap();
    assert_eq!(sources.entries().len(), 3);
    assert_eq!(sources.source_byte_length(), 0);
    assert!(matches!(
        run(capture::Limits {
            descendants: 1,
            ..limits
        }),
        Err(CaptureError::InventoryLimit)
    ));
    let deep = std::iter::repeat_n("a", 129).collect::<Vec<_>>().join("/");
    std::fs::create_dir_all(tmp.path().join("compile.dest/tree").join(deep)).unwrap();
    assert!(matches!(
        capture(&dir, CaptureScope::Primary),
        Err(CaptureError::InventoryLimit)
    ));
}

#[test]
fn real_source_64mib_inclusive_and_one_over_refuses_without_truncation() {
    let (tmp, dir) = fixture(None);
    let path = tmp.path().join("compile.dest/model.json");
    let file = std::fs::File::create(&path).unwrap();
    file.set_len(MAX_SOURCE_BYTES as u64).unwrap();
    let sources = capture(&dir, CaptureScope::Primary)
        .unwrap()
        .ready()
        .unwrap();
    assert_eq!(sources.source_byte_length(), MAX_SOURCE_BYTES);
    assert_eq!(
        sources
            .file_bytes(&SourcePath::parse("model.json").unwrap())
            .unwrap()
            .len(),
        MAX_SOURCE_BYTES
    );
    drop(sources);
    file.set_len(MAX_SOURCE_BYTES as u64 + 1).unwrap();
    assert!(matches!(
        capture(&dir, CaptureScope::Primary),
        Err(CaptureError::SourceLimit)
    ));
}

#[test]
fn waits_for_writer_and_captures_its_record_and_bytes_together() {
    let (tmp, dir) = fixture(None);
    let lock = std::fs::File::create(tmp.path().join("compile.lock")).unwrap();
    fs2::FileExt::lock_exclusive(&lock).unwrap();
    let worker = std::thread::spawn(move || capture(&dir, CaptureScope::Primary));
    // While the exclusive writer lock is held, publish a different descriptor
    // and bytes, then release. The reader cannot pair old bytes/new descriptor.
    std::fs::write(tmp.path().join("compile.dest/new.json"), b"new\r\n").unwrap();
    let record = std::fs::read_to_string(tmp.path().join("compile.json"))
        .unwrap()
        .replace("model.json", "new.json");
    std::fs::write(tmp.path().join("compile.json"), &record).unwrap();
    fs2::FileExt::unlock(&lock).unwrap();
    let sources = worker.join().unwrap().unwrap().ready().unwrap();
    assert_eq!(sources.record.descriptor.path().as_str(), "new.json");
    assert_eq!(
        sources.record.sha256(),
        &morphir_distribution::Sha256Digest::of_bytes(record.as_bytes())
    );
    assert_eq!(
        sources.file_bytes(&SourcePath::parse("new.json").unwrap()),
        Some(&b"new\r\n"[..])
    );
}

#[test]
fn normalization_cannot_hide_path_or_file_directory_aliases() {
    let (tmp, dir) = fixture(None);
    let record_path = tmp.path().join("compile.json");
    let record = std::fs::read_to_string(&record_path)
        .unwrap()
        .replace("\"model.json\"", "\"tree\"")
        .replace("single-file", "document-tree");
    std::fs::write(record_path, record).unwrap();
    std::fs::create_dir_all(tmp.path().join("compile.dest/tree/a")).unwrap();
    std::fs::write(tmp.path().join("compile.dest/tree/a/b"), b"first").unwrap();
    // NFKC changes the fullwidth slash into a separator. Whole-path portable
    // keys, not just independently normalized components, must detect it.
    std::fs::write(tmp.path().join("compile.dest/tree/a／b"), b"second").unwrap();
    assert!(matches!(
        capture(&dir, CaptureScope::Primary),
        Err(CaptureError::InvalidPathSet)
    ));
}

#[test]
fn capture_refuses_invalid_record_identity_duplicates_and_tombstones() {
    for change in [
        ("\"schema\":1", "\"schema\":2"),
        ("\"schema\":1", "\"schema\":1,\"schema\":1"),
        ("\"task\":\"compile\"", "\"task\":\"generate\""),
        ("\"module\":\"\"", "\"module\":\"other\""),
        ("\"completedAt\":\"now\"", "\"completedAt\":false"),
        (
            "\"path\":\"model.json\"",
            "\"path\":\"model.json\",\"path\":\"model.json\"",
        ),
        ("\"version\":\"v4\"", "\"version\":\"v4\",\"extra\":0"),
        ("\"schema\":1", "\"schema\":1,\"tombstone\":true"),
    ] {
        let (tmp, dir) = fixture(None);
        let path = tmp.path().join("compile.json");
        let record = std::fs::read_to_string(&path)
            .unwrap()
            .replace(change.0, change.1);
        std::fs::write(&path, record).unwrap();
        assert!(
            matches!(
                capture(&dir, CaptureScope::Primary),
                Err(CaptureError::InvalidRecord)
            ),
            "{change:?}"
        );
    }
}

#[test]
fn all_64_declared_roots_including_primary_preserve_zero_byte_files() {
    let companions: Vec<_> = (0..63)
        .map(|n| serde_json::json!({"kind":"file","path":format!("side-{n:02}")}))
        .collect();
    let (tmp, dir) = fixture(Some(
        &serde_json::json!({"contractVersion":CONTRACT_VERSION,"companions":companions})
            .to_string(),
    ));
    for n in 0..63 {
        std::fs::write(tmp.path().join(format!("compile.dest/side-{n:02}")), []).unwrap();
    }
    let sources = capture(&dir, CaptureScope::Complete)
        .unwrap()
        .ready()
        .unwrap();
    assert_eq!(sources.entries().len(), MAX_ROOTS);
    assert_eq!(sources.companions().len(), 63);
    assert_eq!(sources.source_byte_length(), 24);
    assert!(
        sources.entries()[1..]
            .iter()
            .all(|entry| entry.byte_length() == Some(0))
    );
}

#[test]
fn declaration_cannot_expand_aggregate_source_limit_using_multiple_files() {
    let (tmp, dir) = fixture(Some(
        r#"{"contractVersion":"0.1.0-draft.1","companions":[{"kind":"file","path":"second"}]}"#,
    ));
    let first = std::fs::File::create(tmp.path().join("compile.dest/model.json")).unwrap();
    first.set_len((MAX_SOURCE_BYTES / 2) as u64).unwrap();
    let second = std::fs::File::create(tmp.path().join("compile.dest/second")).unwrap();
    second.set_len((MAX_SOURCE_BYTES / 2) as u64).unwrap();
    let sources = capture(&dir, CaptureScope::Complete)
        .unwrap()
        .ready()
        .unwrap();
    assert_eq!(sources.source_byte_length(), MAX_SOURCE_BYTES);
    drop(sources);
    second.set_len((MAX_SOURCE_BYTES / 2 + 1) as u64).unwrap();
    assert!(matches!(
        capture(&dir, CaptureScope::Complete),
        Err(CaptureError::SourceLimit)
    ));
}

#[test]
fn missing_records_do_not_invent_model_sources_and_representations_are_closed() {
    let (tmp, dir) = fixture(None);
    std::fs::remove_file(tmp.path().join("compile.json")).unwrap();
    assert!(matches!(
        capture(&dir, CaptureScope::Primary).unwrap(),
        CaptureResult::Unavailable(CaptureUnavailable::NotCompiled)
    ));
    for change in [
        ("\"format\":\"json\"", "\"format\":\"xml\""),
        ("\"version\":\"v4\"", "\"version\":\"v99\""),
    ] {
        let (tmp, dir) = fixture(None);
        let path = tmp.path().join("compile.json");
        let record = std::fs::read_to_string(&path)
            .unwrap()
            .replace(change.0, change.1);
        std::fs::write(path, record).unwrap();
        assert!(matches!(
            capture(&dir, CaptureScope::Primary),
            Err(CaptureError::UnsupportedRepresentation)
        ));
    }
}

#[cfg(unix)]
#[test]
fn no_selected_record_root_child_or_companion_follows_symlinks() {
    for what in [
        "compile.json",
        "compile.dest/model.json",
        "compile.dest/notes",
        "compile.lock",
    ] {
        let (tmp, dir) = fixture(Some(
            r#"{"contractVersion":"0.1.0-draft.1","companions":[{"kind":"directory","path":"notes"}]}"#,
        ));
        let external = tempfile::tempdir().unwrap();
        std::fs::write(external.path().join("secret"), b"secret").unwrap();
        let path = tmp.path().join(what);
        if path.exists() {
            std::fs::remove_file(&path).unwrap();
        }
        std::os::unix::fs::symlink(external.path(), &path).unwrap();
        assert!(capture(&dir, CaptureScope::Complete).is_err(), "{what}");
    }
}

#[test]
fn cancellation_while_waiting_for_compile_writer_is_bounded_and_cleans_up() {
    let (tmp, dir) = fixture(None);
    let lock = std::fs::File::create(tmp.path().join("compile.lock")).unwrap();
    fs2::FileExt::lock_exclusive(&lock).unwrap();
    let control = CaptureControl::new();
    let worker_control = control.clone();
    let worker = std::thread::spawn(move || {
        capture_compiled(
            &dir,
            &SelectedModule::parse("").unwrap(),
            CaptureScope::Primary,
            &worker_control,
        )
    });
    std::thread::sleep(std::time::Duration::from_millis(30));
    control.cancel();
    assert!(matches!(worker.join().unwrap(), Err(CaptureError::Timeout)));
    drop(lock);
    let dir = Dir::open_ambient_dir(tmp.path(), cap_std::ambient_authority()).unwrap();
    assert!(capture(&dir, CaptureScope::Primary).is_ok());
}
