//! Platform identifiers used by toolchain recipes, locks and receipts.
//!
//! The spelling follows .NET runtime identifiers, which state the C library
//! on Linux: `linux-x64` is glibc and `linux-musl-x64` is musl. Tool release
//! metadata v1 platforms (`{ "os": "linux", "arch": "x86_64" }`) and extension
//! descriptor target triples are derived from it; neither is substituted for
//! another platform.

use morphir_distribution::Platform;
use std::fmt;

/// An operating system and, on Linux, its C library.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Os {
    /// Windows.
    Windows,
    /// macOS.
    MacOs,
    /// Linux with glibc.
    LinuxGlibc,
    /// Linux with musl.
    LinuxMusl,
}

/// A processor architecture.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Arch {
    /// x86-64.
    X64,
    /// AArch64.
    Arm64,
}

/// A platform this contract version can name.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct PlatformId {
    os: Os,
    arch: Arch,
}

const ALL: [(&str, Os, Arch); 8] = [
    ("win-x64", Os::Windows, Arch::X64),
    ("win-arm64", Os::Windows, Arch::Arm64),
    ("osx-x64", Os::MacOs, Arch::X64),
    ("osx-arm64", Os::MacOs, Arch::Arm64),
    ("linux-x64", Os::LinuxGlibc, Arch::X64),
    ("linux-arm64", Os::LinuxGlibc, Arch::Arm64),
    ("linux-musl-x64", Os::LinuxMusl, Arch::X64),
    ("linux-musl-arm64", Os::LinuxMusl, Arch::Arm64),
];

impl PlatformId {
    /// The six first-delivery platforms.
    pub const FIRST_DELIVERY: [&'static str; 6] = [
        "win-x64",
        "win-arm64",
        "osx-x64",
        "osx-arm64",
        "linux-x64",
        "linux-arm64",
    ];

    /// Parse a platform identifier.
    pub fn parse(value: &str) -> Result<Self, String> {
        ALL.iter()
            .find(|(name, _, _)| *name == value)
            .map(|(_, os, arch)| Self {
                os: *os,
                arch: *arch,
            })
            .ok_or_else(|| {
                format!(
                    "'{value}' is not a platform id; expected one of {}",
                    ALL.map(|(name, _, _)| name).join(", ")
                )
            })
    }

    /// Return the identifier.
    pub fn as_str(&self) -> &'static str {
        ALL.iter()
            .find(|(_, os, arch)| *os == self.os && *arch == self.arch)
            .map(|(name, _, _)| *name)
            .expect("every platform has a spelling")
    }

    /// Return the operating system.
    pub fn os(&self) -> Os {
        self.os
    }

    /// Return the architecture.
    pub fn arch(&self) -> Arch {
        self.arch
    }

    /// Return the tool release metadata v1 platform.
    ///
    /// Version 1 platforms do not state a C library. A v1 Linux artifact is
    /// therefore bound only to a glibc platform, and a musl platform has no v1
    /// platform: it can never select a glibc artifact.
    pub fn tool_platform(&self) -> Option<Platform> {
        let os = match self.os {
            Os::Windows => "windows",
            Os::MacOs => "macos",
            Os::LinuxGlibc => "linux",
            Os::LinuxMusl => return None,
        };
        let arch = match self.arch {
            Arch::X64 => "x86_64",
            Arch::Arm64 => "aarch64",
        };
        Some(Platform::new(os, arch).expect("fixed v1 platform spelling is valid"))
    }

    /// Return the target triple an extension release descriptor uses.
    pub fn target_triple(&self) -> &'static str {
        match (self.os, self.arch) {
            (Os::Windows, Arch::X64) => "x86_64-pc-windows-msvc",
            (Os::Windows, Arch::Arm64) => "aarch64-pc-windows-msvc",
            (Os::MacOs, Arch::X64) => "x86_64-apple-darwin",
            (Os::MacOs, Arch::Arm64) => "aarch64-apple-darwin",
            (Os::LinuxGlibc, Arch::X64) => "x86_64-unknown-linux-gnu",
            (Os::LinuxGlibc, Arch::Arm64) => "aarch64-unknown-linux-gnu",
            (Os::LinuxMusl, Arch::X64) => "x86_64-unknown-linux-musl",
            (Os::LinuxMusl, Arch::Arm64) => "aarch64-unknown-linux-musl",
        }
    }

    /// Whether launch paths on this platform use Windows syntax.
    pub fn is_windows(&self) -> bool {
        self.os == Os::Windows
    }
}

impl fmt::Display for PlatformId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}
