//! Banner preferences must be resolved before Clap exits for help or version.
use std::path::Path;
use std::process::{Command, Output};
use tempfile::TempDir;

struct Fixture {
    root: TempDir,
}

impl Fixture {
    fn new() -> Self {
        let root = tempfile::tempdir().unwrap();
        for directory in ["project", "home", "config", "data", "morphir-home"] {
            std::fs::create_dir(root.path().join(directory)).unwrap();
        }
        Self { root }
    }

    fn write(&self, file: &str, text: &str) {
        let path = self.root.path().join(file);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }

    fn command(&self, args: &[&str]) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_morphir"));
        command
            .env_clear()
            .current_dir(self.root.path().join("project"))
            .args(args)
            .env("MORPHIR_LOG_FILE", "false");
        // Keep only the OS loader environment; every configuration location is
        // private to this child. No test mutates the process environment.
        for name in ["SystemRoot", "SystemDrive", "WINDIR"] {
            if let Some(value) = std::env::var_os(name) {
                command.env(name, value);
            }
        }
        for (name, directory) in [
            ("HOME", "home"),
            ("USERPROFILE", "home"),
            ("APPDATA", "config"),
            ("LOCALAPPDATA", "data"),
            ("PROGRAMDATA", "data"),
            ("XDG_CONFIG_HOME", "config"),
            ("MORPHIR_HOME", "morphir-home"),
        ] {
            command.env(name, self.root.path().join(directory));
        }
        command
    }

    fn run(&self, args: &[&str], env: &[(&str, &str)]) -> Output {
        let output = self
            .command(args)
            .envs(env.iter().copied())
            .output()
            .unwrap();
        assert!(output.status.success(), "{args:?}: {output:?}");
        output
    }
}

fn has_banner(output: &Output) -> bool {
    String::from_utf8_lossy(&output.stdout).contains(" (built ")
}

#[test]
fn default_banner_is_preserved_for_help_version_and_no_arguments() {
    let fixture = Fixture::new();
    for args in [
        vec![],
        vec!["--help"],
        vec!["-V"],
        vec!["--help-all"],
        vec!["mck", "--help"],
    ] {
        assert!(has_banner(&fixture.run(&args, &[])), "{args:?}");
    }
}

#[test]
fn global_flag_suppresses_banner_before_clap_early_exits() {
    let fixture = Fixture::new();
    for args in [
        vec!["--no-banner"],
        vec!["--no-banner", "--version"],
        vec!["--version", "--no-banner"],
        vec!["--help", "--no-banner"],
        vec!["--help-all", "--no-banner"],
        vec!["help", "--all", "--no-banner"],
        vec!["mck", "--no-banner", "--help"],
        vec!["mck", "--help", "--no-banner"],
        vec!["mck", "run", "--no-banner", "--help"],
    ] {
        assert!(!has_banner(&fixture.run(&args, &[])), "{args:?}");
    }
    let output = fixture.run(&["--no-banner", "--version"], &[]);
    assert_eq!(
        String::from_utf8(output.stdout).unwrap(),
        format!("morphir {}\n", env!("CARGO_PKG_VERSION"))
    );
}

#[test]
fn flag_values_and_arguments_after_double_dash_do_not_suppress_banner() {
    let fixture = Fixture::new();
    for args in [
        vec!["mck", "run", "--adapter-arg", "--no-banner", "--help"],
        vec!["mck", "run", "--adapter-arg=--no-banner", "--help"],
    ] {
        assert!(has_banner(&fixture.run(&args, &[])), "{args:?}");
    }
    let output = fixture
        .command(&["mck", "run", "--", "--no-banner", "--help"])
        .output()
        .unwrap();
    assert!(!output.status.success());
    assert!(has_banner(&output));
}

#[test]
fn boolean_environment_override_precedes_configuration() {
    let fixture = Fixture::new();
    fixture.write("project/morphir.toml", "[cli]\nbanner = false\n");
    for value in ["false", "FALSE", " False "] {
        assert!(has_banner(
            &fixture.run(&["--help"], &[("MORPHIR_NO_BANNER", value)])
        ));
    }
    fixture.write("project/morphir.toml", "[cli]\nbanner = true\n");
    for value in ["true", "TRUE", " True "] {
        assert!(!has_banner(
            &fixture.run(&["--version"], &[("MORPHIR_NO_BANNER", value)])
        ));
    }
    assert!(!has_banner(&fixture.run(
        &["--no-banner", "--help"],
        &[("MORPHIR_NO_BANNER", "false")]
    )));
}

#[test]
fn layered_configuration_controls_banner_and_standard_environment_key() {
    let fixture = Fixture::new();
    fixture.write("morphir-home/morphir.toml", "[cli]\nbanner = false\n");
    assert!(!has_banner(&fixture.run(&["--version"], &[])));
    fixture.write("project/morphir.toml", "[cli]\nbanner = true\n");
    assert!(has_banner(&fixture.run(&["--version"], &[])));
    fixture.write("project/morphir.user.toml", "[cli]\nbanner = false\n");
    assert!(!has_banner(&fixture.run(&["--help"], &[])));
    assert!(has_banner(
        &fixture.run(&["--help"], &[("MORPHIR_CLI__BANNER", "true")])
    ));
    assert!(!has_banner(&fixture.run(
        &["--help"],
        &[
            ("MORPHIR_CLI__BANNER", "true"),
            ("MORPHIR_NO_BANNER", "true")
        ]
    )));
}

#[test]
fn project_yaml_controls_help_and_no_arguments() {
    let fixture = Fixture::new();
    fixture.write("project/morphir.yaml", "cli:\n  banner: false\n");
    assert!(!has_banner(&fixture.run(&[], &[])));
    assert!(!has_banner(&fixture.run(&["mck", "--help"], &[])));
}

#[test]
fn invalid_preferences_and_broken_config_do_not_block_help_or_version() {
    let fixture = Fixture::new();
    fixture.write("project/morphir.toml", "[cli]\nbanner = false\n");
    assert!(!has_banner(
        &fixture.run(&["--help"], &[("MORPHIR_NO_BANNER", "invalid")])
    ));
    for config in ["[cli", "[cli]\nbanner = 'invalid'\n"] {
        fixture.write("project/morphir.toml", config);
        assert!(has_banner(&fixture.run(&["--help"], &[])));
        assert!(has_banner(&fixture.run(&["--version"], &[])));
        assert!(!has_banner(
            &fixture.run(&["--version"], &[("MORPHIR_NO_BANNER", "true")])
        ));
        assert!(!has_banner(&fixture.run(&["--no-banner", "--help"], &[])));
    }
}

#[test]
fn configuration_is_discovered_from_a_nested_working_directory() {
    let fixture = Fixture::new();
    fixture.write("project/morphir.toml", "[cli]\nbanner = false\n");
    let nested = fixture.root.path().join(Path::new("project/src/nested"));
    std::fs::create_dir_all(&nested).unwrap();
    let output = fixture
        .command(&["--version"])
        .current_dir(nested)
        .output()
        .unwrap();
    assert!(output.status.success());
    assert!(!has_banner(&output));
}
