use deno_core::extension;
use std::env;
use std::path::PathBuf;
//use download_git;

fn main() {
    extension!(morphirjs, js = ["src/runtime.js",]);

    let out_dir = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    let snapshot_path = out_dir.join("MORPHIRJS_SNAPSHOT.bin");

    let snapshot = deno_core::snapshot::create_snapshot(
        deno_core::snapshot::CreateSnapshotOptions {
            cargo_manifest_dir: env!("CARGO_MANIFEST_DIR"),
            startup_snapshot: None,
            skip_op_registration: false,
            extensions: vec![morphirjs::init_ops_and_esm()],
            with_runtime_cb: None,
            extension_transpiler: None,
        },
        None,
    )
    .unwrap();

    std::fs::write(snapshot_path, snapshot.output).unwrap();
    // download_git::download(
    //     "https://github.com/twbs/bootstrap.git:main",
    //     download_git::DownloadOptions {
    //         target_files: Some(vec!["dist".to_string(), "README.md".to_string()]),
    //         dest_path: String::from(TEST_FOLDER),
    //     },
    // )?;
    // git_download::repo("https://github.com/akiradeveloper/lol")
    //     // Tag name can be used.
    //     .branch_name("v0.9.1")
    //     // Can be saved in a different name.
    //     .add_file("lol-core/proto/lol-core.proto", "proto/lol.proto")
    //     .exec()?;

    // tonic_build::configure()
    //     .build_server(false)
    //     .compile(&["lol.proto"], &["proto"])?;
}
