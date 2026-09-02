use std::{
    env,
    fs::{self, OpenOptions},
    io::Write,
    path::PathBuf,
};

fn main() {
    let home = PathBuf::from(env::var_os("MORPHIR_HOME").expect("MORPHIR_HOME"));
    let logs = env::var_os("MORPHIR_LOG_DIR")
        .filter(|path| !path.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home.join("logs/desktop"));
    fs::create_dir_all(&logs).expect("create Desktop logs");
    let launch_id = env::var("MORPHIR_LAUNCH_ID").expect("MORPHIR_LAUNCH_ID");
    let parent_operation_id =
        env::var("MORPHIR_PARENT_OPERATION_ID").expect("MORPHIR_PARENT_OPERATION_ID");
    let exit_code = fs::read_to_string(home.join("fixture-exit-code"))
        .ok()
        .and_then(|value| value.trim().parse::<i32>().ok())
        .unwrap_or(0);
    let readiness = fs::read_to_string(home.join("fixture-readiness")).unwrap_or_default();
    let mut ready = OpenOptions::new()
        .create(true)
        .append(true)
        .open(logs.join("fixture.jsonl"))
        .expect("open readiness log");
    if readiness == "exit" {
        writeln!(ready, "{{\"fields\":{{\"event_name\":\"desktop.exit\",\"launch_id\":\"{launch_id}\",\"exit_code\":{exit_code}}}}}")
            .expect("write exit event");
    } else if readiness != "silent" {
        writeln!(
        ready,
        "{{\"fields\":{{\"event_name\":\"desktop.ready\",\"launch_id\":\"{launch_id}\",\"parent_operation_id\":\"{parent_operation_id}\"}}}}"
    )
    .expect("write readiness event");
    }

    let workspace = env::var("MORPHIR_DESKTOP_WORKSPACE").expect("MORPHIR_DESKTOP_WORKSPACE");
    let contract = env::var("MORPHIR_DESKTOP_LAUNCH_CONTRACT_VERSION")
        .expect("MORPHIR_DESKTOP_LAUNCH_CONTRACT_VERSION");
    let mut capture = OpenOptions::new()
        .create(true)
        .append(true)
        .open(home.join("launches.txt"))
        .expect("open launch capture");
    writeln!(capture, "{workspace}|{}|{contract}", home.display()).expect("write launch capture");

    std::process::exit(exit_code);
}
