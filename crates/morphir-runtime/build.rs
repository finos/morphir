use deno_core::extension;
use std::env;
use std::path::PathBuf;

fn main() {
    extension!(morphir, js = ["src/runtime.js",]);

    let out_dir = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    let snapshot_path = out_dir.join("MORPHIRJS_SNAPSHOT.bin");
    let create_snapshot_options = deno_core::snapshot::CreateSnapshotOptions {
        cargo_manifest_dir: env!("CARGO_MANIFEST_DIR"),
        startup_snapshot: None,
        skip_op_registration: false,
        extensions: vec![morphir::init_ops_and_esm()],
        extension_transpiler: None,
        with_runtime_cb: None,
    };

    let _snapshot = deno_core::snapshot::create_snapshot(
       create_snapshot_options,
       None
    );
}
