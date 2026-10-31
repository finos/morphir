///|
/// An operating system that a host runs and a process artifact targets.
pub(all) enum Os {
  MacOs
  Linux
  Windows
} derive(Eq, Debug)

///|
pub extend Os with Eq::{equal, not_equal}

///|
pub extend Os with @debug.Debug::{to_repr}

///|
pub impl Show for Os with fn output(self, logger) {
  logger.write_string(
    match self {
      MacOs => "macOS"
      Linux => "Linux"
      Windows => "Windows"
    },
  )
}

///|
pub extend Os with Show::{to_string, output}

///|
/// A CPU architecture that a host runs and a process artifact targets.
pub(all) enum Arch {
  Aarch64
  X86_64
} derive(Eq, Debug)

///|
pub extend Arch with Eq::{equal, not_equal}

///|
pub extend Arch with @debug.Debug::{to_repr}

///|
pub impl Show for Arch with fn output(self, logger) {
  logger.write_string(
    match self {
      Aarch64 => "aarch64"
      X86_64 => "x86_64"
    },
  )
}

///|
pub extend Arch with Show::{to_string, output}

///|
/// A C library environment of Linux. A dynamically linked executable for it
/// starts only where its dynamic loader is present.
pub(all) enum Libc {
  Glibc
  Musl
} derive(Eq, Compare, Debug)

///|
pub extend Libc with Eq::{equal, not_equal}

///|
pub extend Libc with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend Libc with @debug.Debug::{to_repr}

///|
pub impl Show for Libc with fn output(self, logger) {
  logger.write_string(
    match self {
      Glibc => "glibc"
      Musl => "musl"
    },
  )
}

///|
pub extend Libc with Show::{to_string, output}

///|
/// The absolute paths where a Linux machine of `arch` keeps the dynamic loader
/// of this C library. One present path is enough.
pub fn Libc::loaders(self : Libc, arch : Arch) -> Array[String] {
  match (self, arch) {
    (Glibc, X86_64) =>
      [
        "/lib64/ld-linux-x86-64.so.2", "/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2",
      ]
    (Glibc, Aarch64) =>
      [
        "/lib/ld-linux-aarch64.so.1", "/lib64/ld-linux-aarch64.so.1", "/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1",
      ]
    (Musl, _) => ["/lib/ld-musl-\{arch}.so.1"]
  }
}

///|
pub fn Platform::os(self : Platform) -> Os {
  match self {
    Aarch64AppleDarwin | X86_64AppleDarwin => MacOs
    Aarch64UnknownLinuxGnu
    | X86_64UnknownLinuxGnu
    | Aarch64UnknownLinuxMusl
    | X86_64UnknownLinuxMusl => Linux
    Aarch64PcWindowsMsvc | X86_64PcWindowsMsvc => Windows
  }
}

///|
pub fn Platform::arch(self : Platform) -> Arch {
  match self {
    Aarch64AppleDarwin
    | Aarch64UnknownLinuxGnu
    | Aarch64UnknownLinuxMusl
    | Aarch64PcWindowsMsvc => Aarch64
    X86_64AppleDarwin
    | X86_64UnknownLinuxGnu
    | X86_64UnknownLinuxMusl
    | X86_64PcWindowsMsvc => X86_64
  }
}

///|
/// The C library environment that an artifact for this platform needs: one
/// for a Linux platform, none for macOS and Windows.
pub fn Platform::libc(self : Platform) -> Libc? {
  match self {
    Aarch64UnknownLinuxGnu | X86_64UnknownLinuxGnu => Some(Glibc)
    Aarch64UnknownLinuxMusl | X86_64UnknownLinuxMusl => Some(Musl)
    _ => None
  }
}

///|

///|
/// What a host machine can run: its operating system, its CPU architecture
/// and, on Linux, the C library environments whose dynamic loaders are
/// present. A host decides it at run time; the target that its own executable
/// was built for does not matter, so a static musl host on a glibc machine
/// runs gnu artifacts.
pub struct Machine {
  priv os : Os
  priv arch : Arch
  priv libcs : Array[Libc]
} derive(Eq, Debug)

///|
pub extend Machine with Eq::{equal, not_equal}

///|
pub extend Machine with @debug.Debug::{to_repr}

///|
/// A machine with `libcs`, in any order and with repeats. Only Linux has C
/// library environments; on macOS and Windows `libcs` is ignored.
pub fn Machine::new(os : Os, arch : Arch, libcs~ : Array[Libc] = []) -> Machine {
  let present = match os {
    Linux => [Glibc, Musl].filter(libc => libcs.contains(libc))
    MacOs | Windows => []
  }
  { os, arch, libcs: present, }
}

///|
/// The machine of `os` and `arch`, with each Linux C library whose dynamic
/// loader `present` reports. `present` receives the absolute paths of
/// `Libc::loaders`; detection runs no program. On macOS and Windows it
/// checks no paths.
pub fn Machine::detect(
  os : Os,
  arch : Arch,
  present~ : (String) -> Bool,
) -> Machine {
  let libcs = match os {
    Linux =>
      [Glibc, Musl].filter(libc => libc.loaders(arch).iter().any(present))
    MacOs | Windows => []
  }
  Machine::new(os, arch, libcs~)
}

///|
/// The machine that runs exactly `platform`.
pub fn Machine::of(platform : Platform) -> Machine {
  Machine::new(
    platform.os(),
    platform.arch(),
    libcs=platform.libc().map_or([], libc => [libc]),
  )
}

///|
pub fn Machine::os(self : Machine) -> Os {
  self.os
}

///|
pub fn Machine::arch(self : Machine) -> Arch {
  self.arch
}

///|
/// The C library environments present, glibc first.
pub fn Machine::libcs(self : Machine) -> Array[Libc] {
  self.libcs.copy()
}

///|
/// Whether a process artifact for `platform` can start here: the operating
/// system and the architecture match, and on Linux the C library environment
/// that the artifact needs is present.
pub fn Machine::runs(self : Machine, platform : Platform) -> Bool {
  platform.os() == self.os &&
  platform.arch() == self.arch &&
  (match platform.libc() {
    Some(libc) => self.libcs.contains(libc)
    None => true
  })
}

///|
/// The release platforms that this machine runs, in release order.
pub fn Machine::platforms(self : Machine) -> Array[Platform] {
  platforms.filter(platform => self.runs(platform))
}

///|
pub fn Machine::path_style(self : Machine) -> PathStyle {
  match self.os {
    Windows => Windows
    MacOs | Linux => Posix
  }
}

///|
/// Why this machine cannot run a process artifact for `platform`, in words
/// that name what the machine has, or `None` when it can.
pub fn Machine::mismatch(self : Machine, platform : Platform) -> String? {
  guard !self.runs(platform) else { None }
  if platform.os() == self.os &&
    platform.arch() == self.arch &&
    platform.libc() is Some(libc) {
    Some("this host runs \{self}; the artifact needs \{libc}")
  } else {
    Some("this host runs \{self}; the artifact is built for \{platform}")
  }
}

///|
/// For example `x86_64 Linux with glibc and musl` or `aarch64 macOS`.
pub impl Show for Machine with fn output(self, logger) {
  logger.write_string("\{self.arch} \{self.os}")
  guard self.os is Linux else { return }
  match self.libcs {
    [] => logger.write_string(" with no C library loader")
    libcs =>
      logger.write_string(
        " with \{libcs.map(libc => libc.to_string()).join(" and ")}",
      )
  }
}

///|
pub extend Machine with Show::{to_string, output}
