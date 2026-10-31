use std::{fs, process::Command};

#[test]
fn workspace_compile_selects_member_sources_package_and_exposure() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    fs::write(root.join("morphir.toml"), "[workspace]\nmembers = ['packages/*']\ndefault_member = 'packages/first'\n[frontend]\nlanguage = 'elm'\n[frontend.elm]\nextension = 'morphir-elm-native'\n").unwrap();
    for name in ["first", "second"] {
        let member = root.join("packages").join(name);
        fs::create_dir_all(member.join("models")).unwrap();
        fs::write(member.join("morphir.toml"), format!("[project]\nname = 'acme/{name}'\nversion = '1.0.0'\nsource_directory = 'models'\nexposed_modules = ['Api']\n")).unwrap();
        fs::write(
            member.join("models/Api.elm"),
            "module Api exposing (Answer)\n\n\ntype Answer\n    = Answer\n",
        )
        .unwrap();
        fs::write(
            member.join("models/Internal.elm"),
            "module Internal exposing (Detail)\n\n\ntype Detail\n    = Detail\n",
        )
        .unwrap();
    }
    for (args, name) in [
        (vec![], "first"),
        (vec!["--project", "acme/second"], "second"),
    ] {
        let output = Command::new(env!("CARGO_BIN_EXE_morphir"))
            .arg("compile")
            .args(args)
            .arg("--json")
            .current_dir(root)
            .env("MORPHIR_HOME", root.join("home"))
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let record: serde_json::Value = serde_json::from_slice(
            &fs::read(root.join(format!(".morphir/out/packages/{name}/compile.json"))).unwrap(),
        )
        .unwrap();
        assert_eq!(record["module"], format!("packages/{name}"));
        let ir: serde_json::Value = serde_json::from_slice(
            &fs::read(root.join(format!(
                ".morphir/out/packages/{name}/compile.dest/morphir-ir.json"
            )))
            .unwrap(),
        )
        .unwrap();
        let text = serde_json::to_string(&ir).unwrap();
        assert!(text.contains(name), "{text}");
        assert!(text.contains("Private"), "{text}");
        assert!(text.contains("Public"), "{text}");
    }
}
