//! Language-neutral native bundle authoring and verified acquisition.
use super::*;
use morphir_distribution::{ReleaseBundleDescriptor, Sha256Digest};
use std::path::Path;

fn platform() -> String {
    if let Some(target) = option_env!("MORPHIR_BUILD_TARGET") {
        return target.into();
    }
    let suffix = match std::env::consts::OS {
        "macos" => "apple-darwin",
        "windows" => "pc-windows-msvc",
        "linux" => "unknown-linux-gnu",
        os => panic!("unsupported fixture platform {os}"),
    };
    format!("{}-{suffix}", std::env::consts::ARCH)
}

fn guest(root: &Path) -> PathBuf {
    let path = root.join(if cfg!(windows) {
        "built-guest.exe"
    } else {
        "built-guest"
    });
    std::fs::write(&path, super::extension_probe::guest_bytes()).unwrap();
    path
}

fn bundle(
    root: &Path,
    executable: &Path,
    output: &Path,
    id: &str,
    version: &str,
    target: &str,
) -> std::process::Output {
    run_morphir(
        &[
            "extension",
            "bundle",
            "--executable",
            executable.to_str().unwrap(),
            "--extension-id",
            id,
            "--short-id",
            "test",
            "--version",
            version,
            "--platform",
            target,
            "--output",
            output.to_str().unwrap(),
        ],
        &root.join("home"),
        root,
    )
}

fn successful(output: &std::process::Output) {
    assert!(
        output.status.success(),
        "stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn extension_bundle_round_trip_without_cargo_layout() {
    let temp = TempDir::new().unwrap();
    let root = temp.path();
    let executable = guest(root);
    let output = root.join("bundle");
    assert!(!root.join("Cargo.toml").exists());
    successful(&bundle(
        root,
        &executable,
        &output,
        "morphir-test",
        "1.2.3",
        &platform(),
    ));
    let bytes = std::fs::read(output.join("release.json")).unwrap();
    let descriptor = ReleaseBundleDescriptor::parse_json(&bytes).unwrap();
    assert_eq!(descriptor.extension_id().as_str(), "morphir-test");
    assert_eq!(descriptor.version().to_string(), "1.2.3");
    let artifact = &descriptor.artifacts()[0];
    assert_eq!(artifact.platform(), Some(platform().as_str()));
    assert_eq!(artifact.claims().extension.id, "morphir-test");
    let filename = artifact.filename().as_str();
    let packaged = std::fs::read(output.join(filename)).unwrap();
    assert_eq!(packaged, std::fs::read(&executable).unwrap());
    let digest = Sha256Digest::of_bytes(&packaged);
    assert_eq!(artifact.sha256(), &digest);
    assert_eq!(
        std::fs::read_to_string(output.join(format!("{filename}.sha256"))).unwrap(),
        format!("{digest}  {filename}\n")
    );
    assert_eq!(std::fs::read_dir(&output).unwrap().count(), 3);
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        assert_ne!(
            std::fs::metadata(output.join(filename))
                .unwrap()
                .permissions()
                .mode()
                & 0o111,
            0
        );
    }
    let home = root.join("home");
    let index = root.join("index");
    successful(&run_morphir(
        &["extension", "repository", "init", index.to_str().unwrap()],
        &home,
        root,
    ));
    successful(&add_test_repository("local", &index, &home, root));
    successful(&run_morphir(
        &[
            "extension",
            "repository",
            "publish",
            "local",
            "--bundle",
            output.to_str().unwrap(),
        ],
        &home,
        root,
    ));
    successful(&run_morphir(
        &[
            "extension",
            "install",
            "morphir-test",
            "--repository",
            "local",
            "--version",
            "1.2.3",
        ],
        &home,
        root,
    ));
    let catalog: serde_json::Value =
        serde_json::from_slice(&std::fs::read(home.join("catalog/extensions.json")).unwrap())
            .unwrap();
    assert_eq!(catalog["extensions"][0]["claimCheck"], "probed");
    assert_eq!(catalog["extensions"][0]["probeSource"], "describe");
}

#[test]
fn extension_bundle_rejects_identity_version_and_platform_mismatches_without_output() {
    let temp = TempDir::new().unwrap();
    let root = temp.path();
    let executable = guest(root);
    for (id, version, target, expected) in [
        ("other-guest", "1.2.3", platform(), "identity"),
        ("morphir-test", "9.0.0", platform(), "version"),
        (
            "morphir-test",
            "1.2.3",
            "not-this-platform".into(),
            "platform",
        ),
    ] {
        let output = root.join("bundle");
        let result = bundle(root, &executable, &output, id, version, &target);
        assert!(!result.status.success());
        assert!(
            String::from_utf8_lossy(&result.stderr).contains(expected),
            "{}",
            String::from_utf8_lossy(&result.stderr)
        );
        assert!(!output.exists());
        assert!(
            !std::fs::read_dir(root)
                .unwrap()
                .filter_map(Result::ok)
                .any(|entry| entry
                    .file_name()
                    .to_string_lossy()
                    .starts_with(".morphir-bundle-"))
        );
    }
}

#[test]
fn extension_bundle_never_replaces_existing_output() {
    let temp = TempDir::new().unwrap();
    let root = temp.path();
    let executable = guest(root);
    let output = root.join("bundle");
    std::fs::create_dir(&output).unwrap();
    let result = bundle(
        root,
        &executable,
        &output,
        "morphir-test",
        "1.2.3",
        &platform(),
    );
    assert!(!result.status.success());
    assert_eq!(std::fs::read_dir(&output).unwrap().count(), 0);
    std::fs::write(output.join("keep"), "original").unwrap();
    assert!(
        !bundle(
            root,
            &executable,
            &output,
            "morphir-test",
            "1.2.3",
            &platform()
        )
        .status
        .success()
    );
    assert_eq!(
        std::fs::read_to_string(output.join("keep")).unwrap(),
        "original"
    );
}

#[test]
fn extension_bundle_probe_failure_leaves_no_bundle() {
    let temp = TempDir::new().unwrap();
    let root = temp.path();
    let executable = root.join("invalid-guest");
    let output = root.join("bundle");
    std::fs::write(&executable, b"not an executable").unwrap();
    assert!(
        !bundle(
            root,
            &executable,
            &output,
            "morphir-test",
            "1.2.3",
            &platform()
        )
        .status
        .success()
    );
    assert!(!output.exists());
}

#[cfg(unix)]
#[test]
fn extension_bundle_refuses_symlink_artifacts_and_destinations() {
    use std::os::unix::fs::symlink;
    let temp = TempDir::new().unwrap();
    let root = temp.path();
    let executable = guest(root);
    let linked = root.join("linked-guest");
    let output = root.join("bundle");
    symlink(&executable, &linked).unwrap();
    assert!(
        !bundle(root, &linked, &output, "morphir-test", "1.2.3", &platform())
            .status
            .success()
    );
    assert!(!output.exists());
    let destination = root.join("untouched");
    std::fs::create_dir(&destination).unwrap();
    symlink(&destination, &output).unwrap();
    assert!(
        !bundle(
            root,
            &executable,
            &output,
            "morphir-test",
            "1.2.3",
            &platform()
        )
        .status
        .success()
    );
    assert_eq!(std::fs::read_dir(destination).unwrap().count(), 0);
}

#[test]
fn extension_bundle_preserves_optional_claims_and_excludes_probe_side_effects() {
    let temp = TempDir::new().unwrap();
    let root = temp.path();
    let executable = root.join(if cfg!(windows) {
        "built-guest.exe"
    } else {
        "built-guest"
    });
    let output = root.join("bundle");
    let extra = r#""vendorFacts":{"schema":"v1","annotation":"kept"}"#;
    let bytes = super::extension_probe::build_guest(Some("bundle-touch"), Some(extra));
    std::fs::write(&executable, &bytes).unwrap();
    successful(&bundle(
        root,
        &executable,
        &output,
        "morphir-test",
        "1.2.3",
        &platform(),
    ));
    let descriptor: serde_json::Value =
        serde_json::from_slice(&std::fs::read(output.join("release.json")).unwrap()).unwrap();
    assert_eq!(
        descriptor["artifacts"][0]["claims"]["capabilities"]["vendorFacts"]["annotation"],
        "kept"
    );
    assert_eq!(descriptor["artifacts"][0]["claimCheck"], "unchecked");
    assert!(!output.join("guest-created.txt").exists());
    assert!(!root.join("guest-created.txt").exists());
    assert_eq!(std::fs::read_dir(output).unwrap().count(), 3);
}

#[test]
fn extension_bundle_requires_direct_describe_and_cleans_up_failed_guest() {
    let temp = TempDir::new().unwrap();
    let root = temp.path();
    for (mode, diagnostic) in [
        ("fallback", "requires morphir.extension.describe"),
        ("fail", "describe"),
    ] {
        let executable = root.join(if cfg!(windows) {
            "built-guest.exe"
        } else {
            "built-guest"
        });
        let output = root.join("bundle");
        std::fs::write(
            &executable,
            super::extension_probe::build_guest(Some(mode), None),
        )
        .unwrap();
        let result = bundle(
            root,
            &executable,
            &output,
            "morphir-test",
            "1.2.3",
            &platform(),
        );
        assert!(!result.status.success());
        assert!(
            String::from_utf8_lossy(&result.stderr).contains(diagnostic),
            "{}",
            String::from_utf8_lossy(&result.stderr)
        );
        assert!(!output.exists());
        assert!(
            !std::fs::read_dir(root)
                .unwrap()
                .filter_map(Result::ok)
                .any(|entry| entry
                    .file_name()
                    .to_string_lossy()
                    .starts_with(".morphir-bundle-"))
        );
    }
}

#[test]
fn extension_bundle_refuses_output_created_during_probe() {
    let temp = TempDir::new().unwrap();
    let root = temp.path();
    let output = root.join("bundle");
    let executable = root.join(if cfg!(windows) {
        "built-guest.exe"
    } else {
        "built-guest"
    });
    let mode = format!("bundle-race:{}", output.display());
    std::fs::write(
        &executable,
        super::extension_probe::build_guest(Some(&mode), None),
    )
    .unwrap();
    let result = bundle(
        root,
        &executable,
        &output,
        "morphir-test",
        "1.2.3",
        &platform(),
    );
    assert!(!result.status.success());
    assert!(String::from_utf8_lossy(&result.stderr).contains("without replacing existing output"));
    assert_eq!(
        std::fs::read_to_string(output.join("keep")).unwrap(),
        "concurrent output"
    );
    assert!(!output.join("release.json").exists());
}
