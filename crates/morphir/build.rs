use chrono::Utc;

fn main() {
    // Use UTC for reproducible builds across time zones
    let now = Utc::now();
    let date = now.format("%Y-%m-%d").to_string();
    let time = now.format("%H:%M:%S").to_string();

    println!("cargo::rerun-if-changed=build.rs");
    println!("cargo::rustc-env=BUILD_DATE={}", date);
    println!("cargo::rustc-env=BUILD_TIME={}", time);

    // The LongPathsEnabled registry switch only applies to processes whose
    // manifest declares longPathAware; without this, morphir.exe fails on
    // document-tree paths past 260 characters even on a configured machine.
    // /MANIFEST:EMBED is an MSVC linker flag, and msvc is the only Windows
    // toolchain we release for.
    if std::env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("msvc") {
        let manifest =
            std::path::Path::new(&std::env::var("CARGO_MANIFEST_DIR").unwrap())
                .join("morphir.exe.manifest");
        println!("cargo::rerun-if-changed=morphir.exe.manifest");
        println!("cargo::rustc-link-arg-bins=/MANIFEST:EMBED");
        println!("cargo::rustc-link-arg-bins=/MANIFESTINPUT:{}", manifest.display());
    }
}
