use crate::cli_args::RunArgs;
use crate::js_extensions::morphir_js;

pub(crate) async fn run_js(args: &RunArgs) {
    println!("Running...");
    println!("Args: {:?}", args);
    // let runtime = tokio::runtime::Builder::new_multi_thread()
    //     .enable_all()
    //     .build()
    //     .unwrap();
    let file_path = args.file.as_os_str().to_str().unwrap();

    if let Err(error) = morphir_js(file_path).await {
        eprintln!("error: {error}");
    }
}
