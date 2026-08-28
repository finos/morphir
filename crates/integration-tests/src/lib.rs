//! Integration test utilities for Morphir CLI testing
//!
//! This crate provides helpers for running CLI integration tests that require
//! the morphir binary to be pre-built and available.
//!
//! # Binary Location
//!
//! The CLI tests look for the morphir binary in these locations (in order):
//! 1. `.morphir/build/bin/morphir` (staged release binary - preferred for CI)
//! 2. `.morphir/build/bin/morphir-debug` (staged debug binary)
//! 3. `target/release/morphir`
//! 4. `target/debug/morphir`
//!
//! # Usage
//!
//! Build the binary first:
//! ```sh
//! mise run build:release
//! ```
//!
//! Then run integration tests:
//! ```sh
//! mise run test:integration
//! ```

#![allow(dead_code)]

use anyhow::Result;
#[allow(unused_imports)]
use morphir_common::vfs::Vfs;
use std::path::{Path, PathBuf};
use std::process::Command;
use tempfile::TempDir;

/// Check if CLI tests can run (morphir binary available or cargo run works)
pub fn cli_tests_available() -> bool {
    // Check if staged binary exists (preferred for CI)
    if CliTestContext::find_workspace_root()
        .is_some_and(|root| root.join(".morphir/build/bin/morphir").exists())
    {
        return true;
    }
    // Check if morphir binary exists in target
    if CliTestContext::get_morphir_binary().is_some() {
        return true;
    }
    // Check if we can find the workspace root (needed for cargo run)
    if CliTestContext::find_workspace_root().is_some() {
        // Try to verify cargo is available
        return Command::new("cargo").arg("--version").output().is_ok();
    }
    false
}

/// CLI test context for managing test environments
#[derive(Debug)]
pub struct CliTestContext {
    pub temp_dir: TempDir,
    pub project_root: PathBuf,
    pub morphir_dir: PathBuf,
}

impl CliTestContext {
    /// Create a new test context with temporary directory
    pub fn new() -> Result<Self> {
        let temp_dir = tempfile::tempdir()?;
        let project_root = temp_dir.path().to_path_buf();
        let morphir_dir = project_root.join(".morphir");

        Ok(Self {
            temp_dir,
            project_root,
            morphir_dir,
        })
    }

    /// Create a test project structure
    pub fn create_test_project(&self) -> Result<()> {
        std::fs::create_dir_all(self.project_root.join("src"))?;
        Ok(())
    }

    /// Create a test workspace structure
    pub fn create_test_workspace(&self, members: &[&str]) -> Result<()> {
        for member in members {
            let member_path = self.project_root.join(member);
            std::fs::create_dir_all(member_path.join("src"))?;
        }
        Ok(())
    }

    /// Write a morphir.toml configuration file
    pub fn write_test_config(&self, config_content: &str) -> Result<()> {
        std::fs::write(self.project_root.join("morphir.toml"), config_content)?;
        Ok(())
    }

    /// Write a test source file
    pub fn write_source_file(&self, path: &str, content: &str) -> Result<()> {
        let file_path = self.project_root.join(path);
        if let Some(parent) = file_path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&file_path, content)?;
        Ok(())
    }

    /// Find the workspace root by looking for Cargo.toml with [workspace]
    pub fn find_workspace_root() -> Option<PathBuf> {
        // Start from CARGO_MANIFEST_DIR if available
        let start_dir = std::env::var("CARGO_MANIFEST_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|_| std::env::current_dir().unwrap());

        let mut current = start_dir.as_path();
        loop {
            let cargo_toml = current.join("Cargo.toml");
            if cargo_toml.exists()
                && let Ok(content) = std::fs::read_to_string(&cargo_toml)
                && content.contains("[workspace]")
            {
                return Some(current.to_path_buf());
            }
            current = current.parent()?;
        }
    }

    /// Get the path to the morphir CLI binary
    pub fn get_morphir_binary() -> Option<PathBuf> {
        // First check for staged binary in .morphir/build/bin/
        // This is the preferred location for CI and pre-built binaries
        if let Some(workspace_root) = Self::find_workspace_root() {
            let staged_release = workspace_root.join(".morphir/build/bin/morphir");
            if staged_release.exists() {
                return Some(staged_release);
            }
            let staged_debug = workspace_root.join(".morphir/build/bin/morphir-debug");
            if staged_debug.exists() {
                return Some(staged_debug);
            }
        }

        // Fall back to target directory locations
        let possible_paths = vec![
            // Release binary (preferred)
            {
                let target_dir =
                    std::env::var("CARGO_TARGET_DIR").unwrap_or_else(|_| "target".to_string());
                PathBuf::from(target_dir).join("release").join("morphir")
            },
            // Debug binary
            {
                let target_dir =
                    std::env::var("CARGO_TARGET_DIR").unwrap_or_else(|_| "target".to_string());
                PathBuf::from(target_dir).join("debug").join("morphir")
            },
            // In workspace root target
            PathBuf::from("../../target/release/morphir"),
            PathBuf::from("../../target/debug/morphir"),
        ];

        possible_paths.into_iter().find(|path| path.exists())
    }

    /// Execute a morphir CLI command
    pub fn execute_cli_command(&self, args: &[&str]) -> Result<CommandResult> {
        // Find workspace root by looking for Cargo.toml with [workspace]
        let workspace_root = Self::find_workspace_root()
            .ok_or_else(|| anyhow::anyhow!("Could not find workspace root"))?;

        let mut cmd = if let Some(binary) = Self::get_morphir_binary() {
            // Use built binary
            Command::new(&binary)
        } else {
            // Fall back to cargo run with absolute path to workspace Cargo.toml
            let manifest_path = workspace_root.join("Cargo.toml");
            let mut cargo_cmd = Command::new("cargo");
            cargo_cmd.args([
                "run",
                "--bin",
                "morphir",
                "--manifest-path",
                manifest_path.to_str().unwrap(),
                "--",
            ]);
            cargo_cmd
        };

        cmd.args(args);
        cmd.current_dir(&self.project_root);
        cmd.env("RUST_BACKTRACE", "1");
        cmd.env("RUST_LOG", "error"); // Reduce noise in test output

        let output = cmd.output()?;

        Ok(CommandResult {
            stdout: String::from_utf8_lossy(&output.stdout).to_string(),
            stderr: String::from_utf8_lossy(&output.stderr).to_string(),
            exit_code: output.status.code().unwrap_or(-1),
            success: output.status.success(),
        })
    }

    /// Load a test fixture from .morphir/test/fixtures/
    pub fn load_test_fixture(&self, name: &str) -> Result<PathBuf> {
        let fixture_path = self.morphir_dir.join("test").join("fixtures").join(name);

        if fixture_path.exists() {
            Ok(fixture_path)
        } else {
            // Try in workspace root
            let workspace_fixture = self
                .project_root
                .parent()
                .unwrap_or(&self.project_root)
                .join(".morphir")
                .join("test")
                .join("fixtures")
                .join(name);

            if workspace_fixture.exists() {
                Ok(workspace_fixture)
            } else {
                Err(anyhow::anyhow!("Test fixture not found: {}", name))
            }
        }
    }

    /// Load a test scenario from .morphir/test/scenarios/
    pub fn load_test_scenario(&self, name: &str) -> Result<PathBuf> {
        let scenario_path = self.morphir_dir.join("test").join("scenarios").join(name);

        if scenario_path.exists() {
            Ok(scenario_path)
        } else {
            // Try in workspace root
            let workspace_scenario = self
                .project_root
                .parent()
                .unwrap_or(&self.project_root)
                .join(".morphir")
                .join("test")
                .join("scenarios")
                .join(name);

            if workspace_scenario.exists() {
                Ok(workspace_scenario)
            } else {
                Err(anyhow::anyhow!("Test scenario not found: {}", name))
            }
        }
    }
}

/// Result of a CLI command execution
#[derive(Debug, Clone)]
pub struct CommandResult {
    pub stdout: String,
    pub stderr: String,
    pub exit_code: i32,
    pub success: bool,
}

impl CommandResult {
    /// Assert that the command succeeded
    pub fn assert_success(&self) {
        assert!(
            self.success,
            "Command failed with exit code {}\nSTDOUT:\n{}\nSTDERR:\n{}",
            self.exit_code, self.stdout, self.stderr
        );
    }

    /// Assert that the command failed
    pub fn assert_failure(&self) {
        assert!(
            !self.success,
            "Command unexpectedly succeeded\nSTDOUT:\n{}\nSTDERR:\n{}",
            self.stdout, self.stderr
        );
    }

    /// Assert that output contains text
    pub fn assert_output_contains(&self, text: &str) {
        assert!(
            self.stdout.contains(text) || self.stderr.contains(text),
            "Output does not contain '{}'\nSTDOUT:\n{}\nSTDERR:\n{}",
            text,
            self.stdout,
            self.stderr
        );
    }

    /// Assert JSON output structure
    pub fn assert_json_output(&self) -> Result<serde_json::Value> {
        let json: serde_json::Value = serde_json::from_str(&self.stdout)?;
        Ok(json)
    }
}

/// Assert that files exist
pub fn assert_files_exist(root: &Path, files: &[&str]) {
    for file in files {
        let path = root.join(file);
        assert!(path.exists(), "File does not exist: {:?}", path);
    }
}

/// Assert .morphir/ folder structure
pub fn assert_morphir_structure(morphir_dir: &Path, project: &str) {
    assert!(
        morphir_dir.exists(),
        ".morphir/ directory does not exist: {:?}",
        morphir_dir
    );

    let out_dir = morphir_dir.join("out").join(project);
    assert!(
        out_dir.exists(),
        ".morphir/out/{} directory does not exist: {:?}",
        project,
        out_dir
    );
}

/// Create a NotebookVfs from a test notebook file
pub fn create_notebook_vfs(notebook_path: &Path) -> Result<morphir_common::vfs::NotebookVfs> {
    Ok(morphir_common::vfs::NotebookVfs::from_file(notebook_path)?)
}

/// Assert that a notebook contains a file with the given path
pub fn assert_notebook_contains_file(
    notebook: &morphir_common::vfs::NotebookVfs,
    file_path: &Path,
) -> Result<()> {
    assert!(
        notebook.exists(file_path),
        "Notebook does not contain file: {:?}",
        file_path
    );
    Ok(())
}
