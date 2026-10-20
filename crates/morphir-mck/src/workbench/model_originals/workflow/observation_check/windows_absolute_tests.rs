//! Pure Windows lexical unit DATA. No Windows OS process/runtime execution.
//! Child of observation_check::installed::implementation, exercising SAME
//! existing private absolute matcher. Native platform is irrelevant here.
use super::*;
use crate::workbench::model_originals::workflow::{Items, Natural};

fn wide(units: &[u16]) -> OsOperand {
    OsOperand::WindowsWide {
        units: Items(
            units
                .iter()
                .copied()
                .map(|unit| Natural(u64::from(unit)))
                .collect(),
        ),
    }
}
fn text(value: &str) -> OsOperand {
    wide(&value.encode_utf16().collect::<Vec<_>>())
}

#[test]
fn w01_drive_prefix_requires_alphabetic_drive_and_root() {
    for value in [r"C:\file", "z:/file"] {
        assert!(absolute(&text(value)), "{value}")
    }
    for value in [
        r"1:\file",
        r"?:\file",
        r"é:\file",
        r"C:file",
        r"\file",
        "file",
        "",
    ] {
        assert!(!absolute(&text(value)), "{value}");
    }
}
#[test]
fn w02_normal_unc_requires_server_and_share_and_accepts_both_separators() {
    for value in [
        r"\\server\share\file",
        "//server/share/file",
        r"\/server/share/file",
    ] {
        assert!(absolute(&text(value)), "{value}");
    }
    for value in [r"\\", r"\\server", r"\\server\", r"\\\share"] {
        assert!(!absolute(&text(value)), "{value}");
    }
}
#[test]
fn w03_verbatim_and_device_prefixes_preserve_rust_windows_lexical_rules() {
    for value in [
        r"\\?\C:\file",
        r"\\?\UNC\server\share\file",
        r"\\?\volume\file",
        r"\\.\COM42",
        r"\\?\C:",
        r"\\?\C:/file",
    ] {
        assert!(absolute(&text(value)), "{value}");
    }
    // Rust Prefix::has_implicit_root excludes only normal Disk, not
    // VerbatimDisk. Preserve its lexical result even for unusual spellings;
    // this does not claim that the corresponding WinAPI launch succeeds.
}
#[test]
fn w04_unpaired_utf16_is_preserved_without_lossy_drive_or_path_conversion() {
    let units = [
        u16::from(b'C'),
        u16::from(b':'),
        u16::from(b'\\'),
        0xD800,
        u16::from(b'x'),
    ];
    let operand = wide(&units);
    assert!(absolute(&operand));
    let OsOperand::WindowsWide { units: retained } = operand else {
        unreachable!()
    };
    assert_eq!(
        retained.0.iter().map(|n| n.0).collect::<Vec<_>>(),
        units.iter().copied().map(u64::from).collect::<Vec<_>>()
    );
    assert!(!absolute(&wide(&[
        0xD800,
        u16::from(b':'),
        u16::from(b'\\'),
        u16::from(b'x')
    ])));
}
