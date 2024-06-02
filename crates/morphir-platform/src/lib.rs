#[allow(warnings)]
mod bindings;

use bindings::exports::morphir::platform::command_runner;
use bindings::exports::morphir::platform::project;
use bindings::exports::morphir::platform::project::ProjectInfo;

struct Component;

impl command_runner::Guest for Component {
    fn run(args: Vec<String>) -> Result<String, ()> {
        println!("Args are: {:?}", args);
        Ok("Hello".to_string())
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
