//! Why the supported MEP set is written as `>=0.2.0-0` and `<0.3.0-0`.
//!
//! The language-neutral cases are the `mep-version` binding cases in
//! `cases.json`. These tests pin the `semver` crate behaviour that the
//! choice of comparators relies on, so a library change that would alter the
//! set fails here first.

use morphir_toolchain_contract::ProtocolVersion;
use semver::{Version, VersionReq};

fn admits(requirement: &str, version: &str) -> bool {
    VersionReq::parse(requirement)
        .unwrap()
        .matches(&Version::parse(version).unwrap())
}

#[test]
fn a_caret_requirement_does_not_admit_prereleases_of_its_base_version() {
    assert!(!admits("^0.2.0", "0.2.0-draft.1"));
    assert!(admits("^0.2.0", "0.2.0"));
    assert!(admits("^0.2.0", "0.2.3"));
}

#[test]
fn the_supported_comparators_admit_the_whole_line_and_nothing_else() {
    let supported = ProtocolVersion::SUPPORTED.join(", ");
    for version in [
        "0.2.0-draft.1",
        "0.2.0-draft.2",
        "0.2.0-rc.1",
        "0.2.0",
        "0.2.3",
    ] {
        assert!(admits(&supported, version), "{version} is on the line");
    }
    for version in ["0.1.0", "0.3.0-draft.1", "0.3.0", "1.0.0"] {
        assert!(!admits(&supported, version), "{version} is off the line");
    }
}

#[test]
fn only_the_prerelease_rule_keeps_a_prerelease_of_a_later_patch_out() {
    // 0.2.1-rc.1 lies between the two bounds; the crate refuses it because
    // no comparator names 0.2.1 with a prerelease. A library without that
    // rule would admit it, so the pages state the set directly as well.
    assert!(Version::parse("0.2.1-rc.1").unwrap() > Version::parse("0.2.0-0").unwrap());
    assert!(!admits(
        &ProtocolVersion::SUPPORTED.join(", "),
        "0.2.1-rc.1"
    ));
}

#[test]
fn build_metadata_passes_a_requirement_so_the_reader_refuses_it_itself() {
    assert!(admits(
        &ProtocolVersion::SUPPORTED.join(", "),
        "0.2.0+build.1"
    ));
    assert!(ProtocolVersion::parse("0.2.0+build.1").is_err());
}
