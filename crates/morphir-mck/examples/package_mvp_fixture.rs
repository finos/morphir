// Copyright 2026 FINOS
// SPDX-License-Identifier: Apache-2.0
//! Author the separately scoped MVP fixture using only public deterministic keys.
#[path = "../tests/support/package_fixture/mod.rs"]
#[allow(dead_code, unused_imports)]
mod fixture;

fn main() -> fixture::Result<()> {
    let args = fixture::parse_arguments(std::env::args().skip(1))?;
    let generated = fixture::mvp::generate_mvp(&args.source)?;
    match args.destination {
        fixture::Destination::Check(path) => {
            fixture::check_files(&path, &generated)?;
            let frozen = fixture::read_files(&path)?;
            let targets = fixture::verify_tuf(&frozen, fixture::CLOCK)?;
            println!(
                "MVP fixture verified: {} files, {targets} TUF targets",
                generated.len()
            );
        }
        fixture::Destination::Output(path) => {
            fixture::write_files(&path, &generated, &args.source)?;
            println!("MVP fixture generated: {} files", generated.len());
        }
    }
    Ok(())
}
