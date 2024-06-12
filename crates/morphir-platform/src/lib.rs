#[allow(warnings)]
mod bindings;
mod cli_args;

use bindings::exports::morphir::platform::command_runner;
use bindings::exports::morphir::platform::project;
use bindings::exports::morphir::platform::project::ProjectInfo;

use crate::cli_args::Cli;
use clap::Parser;

struct Component;

impl command_runner::Guest for Component {
    fn run(args: Vec<String>) -> Result<String, String> {
        let args_str = format!("Arguments are: {:?}", args);
        let result_cli = Cli::try_parse_from(args.iter());
        let cli = match result_cli {
            Ok(cli) => cli,
            Err(err) => {
                return Err(err.to_string());
            }
        };
        let cwd = std::env::current_dir().unwrap();
        let output = format!(
            "[WASM]Parsed CLI: {:?}\r\nArgs: {:?}\r\n{:?}",
            cli, args_str, cwd
        );
        Ok(output.to_string())
    }
}

impl project::Guest for Component {
    fn get_project_info(_path: String) -> Result<project::ProjectInfo, ()> {
        let project_info = ProjectInfo {
            name: "HardCoded.Project".to_string(),
            source_directory: "src".to_string(),
            includes: vec![],
            dependencies: vec![],
            local_dependencies: vec![],
        };
        Ok(project_info)
    }
}

bindings::export!(Component with_types_in bindings);
