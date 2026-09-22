// Copyright 2026 FINOS
// SPDX-License-Identifier: Apache-2.0
//! Test/authoring tool only. This is not a production registry client.
#[path = "../tests/support/package_fixture/mod.rs"]
#[allow(dead_code)]
mod fixture;
fn main() -> fixture::Result<()> {
    let args = fixture::parse_arguments(std::env::args().skip(1))?;
    let generated = fixture::generate(&fixture::read_inputs(&args.source)?)?;
    match &args.destination {
        fixture::Destination::Check(path) => {
            fixture::check_files(path, &generated)?;
            let frozen = fixture::read_files(path)?;
            fixture::verify_relationships(&args.source, &frozen)?;
            let target_count = fixture::verify_tuf(&frozen, fixture::CLOCK)?;
            println!(
                "Signed fixture verified: {} exact files, {target_count} independently verified TUF targets",
                generated.len()
            );
        }
        fixture::Destination::Output(path) => {
            fixture::write_files(path, &generated, &args.source)?;
            println!("Signed fixture generated: {} exact files", generated.len());
        }
    }
    Ok(())
}
