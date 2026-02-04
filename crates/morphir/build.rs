use chrono::Utc;

fn main() {
    // Use UTC for reproducible builds across time zones
    let now = Utc::now();
    let date = now.format("%Y-%m-%d").to_string();
    let time = now.format("%H:%M:%S").to_string();

    println!("cargo::rerun-if-changed=build.rs");
    println!("cargo::rustc-env=BUILD_DATE={}", date);
    println!("cargo::rustc-env=BUILD_TIME={}", time);
}
