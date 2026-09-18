use morphir::notebook::Notebook;
use serde_json::{Value, json};

fn document() -> Value {
    json!({"nbformat":4,"nbformat_minor":5,"metadata":{"vendor":{"keep":true},"morphir":{"version":1}},"cells":[
        {"id":"source","cell_type":"code","metadata":{"morphir":{"file":{"path":"src/Example.elm","language":"elm"}},"vendor":42},"source":["module Example exposing (..)\n","type alias Amount = Int\n"],"execution_count":null,"outputs":[]}
    ]})
}

#[test]
fn preserves_metadata_and_newlines_and_materializes_only_declared_files() {
    let value = document();
    let notebook = Notebook::parse(&value.to_string()).unwrap();
    assert_eq!(notebook.document(), &value);
    let destination = tempfile::tempdir().unwrap();
    notebook.materialize(destination.path()).unwrap();
    assert_eq!(
        std::fs::read_to_string(destination.path().join("src/Example.elm")).unwrap(),
        "module Example exposing (..)\ntype alias Amount = Int\n"
    );
    let mut string_source = value.clone();
    string_source["cells"][0]["source"] = json!("one\ntwo\n");
    assert_eq!(
        Notebook::parse(&string_source.to_string()).unwrap().cells()[0].source(),
        "one\ntwo\n"
    );
}

#[test]
fn rejects_invalid_nbformat_ids_sources_and_paths() {
    for (pointer, bad) in [
        ("/nbformat", json!(3)),
        ("/nbformat_minor", json!(4)),
        ("/cells/0/id", json!("src/Example.elm")),
        ("/cells/0/id", json!("")),
        ("/cells/0/source", json!([1])),
        ("/cells/0/outputs", json!(null)),
        ("/cells/0/metadata/morphir/file/path", json!("../outside")),
        ("/cells/0/metadata/morphir/file/path", json!("/outside")),
        ("/cells/0/metadata/morphir/file/path", json!("C:\\outside")),
        ("/cells/0/metadata/morphir/file/path", json!("src//file")),
        ("/metadata/morphir/version", json!(2)),
    ] {
        let mut value = document();
        *value.pointer_mut(pointer).unwrap() = bad;
        assert!(
            Notebook::parse(&value.to_string()).is_err(),
            "accepted {value}"
        );
    }
    for removed in ["id", "execution_count", "outputs", "metadata", "source"] {
        let mut value = document();
        value["cells"][0].as_object_mut().unwrap().remove(removed);
        assert!(
            Notebook::parse(&value.to_string()).is_err(),
            "accepted missing {removed}"
        );
    }
}

#[test]
fn rejects_duplicate_ids_and_conflicting_or_case_colliding_file_paths() {
    for (id, path) in [
        ("source", "other.elm"),
        ("second", "src/Example.elm"),
        ("second", "src"),
        ("second", "SRC/example.elm"),
        ("second", "SRC/other.elm"),
    ] {
        let mut value = document();
        let mut cell = value["cells"][0].clone();
        cell["id"] = json!(id);
        cell["metadata"]["morphir"]["file"]["path"] = json!(path);
        value["cells"].as_array_mut().unwrap().push(cell);
        assert!(
            Notebook::parse(&value.to_string()).is_err(),
            "accepted {id}, {path}"
        );
    }
}

#[test]
fn rejects_unicode_equivalent_workspace_paths() {
    for (first, second) in [
        ("é.txt", "e\u{301}.txt"),
        ("Straße.txt", "STRASSE.txt"),
        ("Ａ.txt", "a.txt"),
        ("é", "e\u{301}/nested.txt"),
        ("e\u{301}/nested.txt", "é"),
    ] {
        let mut value = document();
        value["cells"][0]["metadata"]["morphir"]["file"]["path"] = json!(first);
        let mut cell = value["cells"][0].clone();
        cell["id"] = json!("second");
        cell["metadata"]["morphir"]["file"]["path"] = json!(second);
        value["cells"].as_array_mut().unwrap().push(cell);
        assert!(
            Notebook::parse(&value.to_string()).is_err(),
            "accepted equivalent paths {first:?} and {second:?}"
        );
    }
}

#[cfg(unix)]
#[test]
fn materialization_refuses_existing_files_and_symlinked_ancestors() {
    let notebook = Notebook::parse(&document().to_string()).unwrap();
    let root = tempfile::tempdir().unwrap();
    let outside = tempfile::tempdir().unwrap();
    std::os::unix::fs::symlink(outside.path(), root.path().join("src")).unwrap();
    assert!(notebook.materialize(root.path()).is_err());
    assert!(!outside.path().join("Example.elm").exists());
    let root = tempfile::tempdir().unwrap();
    notebook.materialize(root.path()).unwrap();
    assert!(notebook.materialize(root.path()).is_err());
}

#[test]
fn rejects_nonportable_windows_file_names() {
    for path in [
        "src/CON.elm",
        "CONIN$",
        "src/conout$.txt",
        "aux",
        "src/Lpt9.txt",
        "src/name.",
        "src/name ",
        "src/a?b",
        "src/a*b",
        "src/a|b",
        "src/a\nb",
    ] {
        let mut value = document();
        value["cells"][0]["metadata"]["morphir"]["file"]["path"] = json!(path);
        assert!(
            Notebook::parse(&value.to_string()).is_err(),
            "accepted {path:?}"
        );
    }
}
