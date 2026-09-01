//! Verifies that `morphir playground` is registered as a subcommand with a
//! `--no-open` flag and takes no workspace argument.

#[test]
fn the_playground_command_is_registered_with_a_no_open_flag() {
    let output = std::process::Command::new(env!("CARGO_BIN_EXE_morphir"))
        .args(["playground", "--help"])
        .output()
        .expect("the playground subcommand exists");

    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(
        output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(stdout.contains("--no-open"), "help: {stdout}");
    assert!(
        !stdout.contains("WORKSPACE"),
        "the playground takes no workspace: {stdout}"
    );
}
