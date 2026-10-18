///|
/// Structural failures found before invoking a compiler or acquiring assets.
pub(all) suberror AssemblyError {
  InvalidPackageName(String)
  InvalidDigest(String)
  InvalidAlias(String)
  DuplicateAlias(PackagePin, String)
  DuplicatePackage(String)
  MissingPackage(Referrer, PackagePin)
  RevisionMismatch(Referrer, PackagePin, PackagePin)
  DependencyCycle(Array[PackagePin])
} derive(Debug)

///|
pub(all) enum Referrer {
  SelectedRoot
  SuppliedAssembly
  DependencyOf(PackagePin)
} derive(Eq, Debug)

///|
/// An exact package identity. The provider must still verify the actual bytes.
pub struct PackagePin {
  priv name : String
  priv digest : String
} derive(Eq, Compare, Debug)

///|
fn letter(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn package_name_valid(name : String) -> Bool {
  !name.is_empty() &&
  name
  .split("/")
  .all(part => {
    !part.is_empty() &&
    part.iter().all(c => letter(c) || digit(c) || c == '_' || c == '-')
  })
}

///|
pub fn PackagePin::new(
  name : String,
  sha256 : String,
) -> PackagePin raise AssemblyError {
  if !package_name_valid(name) {
    raise InvalidPackageName(name)
  }
  if sha256.length() != 64 ||
    !sha256.iter().all(c => digit(c) || (c >= 'a' && c <= 'f')) {
    raise InvalidDigest(sha256)
  }
  { name, digest: sha256, }
}

///|
pub fn PackagePin::name(self : PackagePin) -> String {
  self.name
}

///|
pub fn PackagePin::sha256(self : PackagePin) -> String {
  self.digest
}

///|
/// Aliases are local to the referring package, not part of dependency identity.
pub struct Dependency {
  priv import_name : String
  priv target : PackagePin
} derive(Eq, Compare, Debug)

///|
pub fn Dependency::new(
  import_name : String,
  target : PackagePin,
) -> Dependency raise AssemblyError {
  let chars = import_name.to_array()
  let simple = !chars.is_empty() &&
    (letter(chars[0]) || chars[0] == '_') &&
    chars.iter().all(c => letter(c) || digit(c) || c == '_')
  let qualified = import_name.contains("/") && package_name_valid(import_name)
  if !simple && !qualified {
    raise InvalidAlias(import_name)
  }
  { import_name, target, }
}

///|
pub fn Dependency::import_name(self : Dependency) -> String {
  self.import_name
}

///|
pub fn Dependency::target(self : Dependency) -> PackagePin {
  self.target
}

///|
pub struct Package {
  priv pin : PackagePin
  priv dependencies : Array[Dependency]
} derive(Eq, Debug)

///|
pub fn Package::new(
  pin : PackagePin,
  dependencies : Array[Dependency],
) -> Package raise AssemblyError {
  let aliases : Map[String, Unit] = Map([])
  for dependency in dependencies {
    if aliases.contains(dependency.import_name) {
      raise DuplicateAlias(pin, dependency.import_name)
    }
    aliases[dependency.import_name] = ()
  }
  let snapshot = dependencies.copy()
  snapshot.sort()
  { pin, dependencies: snapshot, }
}

///|
pub fn Package::pin(self : Package) -> PackagePin {
  self.pin
}

///|
pub fn Package::dependencies(self : Package) -> Array[Dependency] {
  self.dependencies.copy()
}

///|
/// A validated snapshot. It establishes structure, not asset or model validity.
pub struct Plan {
  priv root : PackagePin
  priv packages : Array[Package]
} derive(Eq, Debug)

///|
pub fn Plan::root(self : Plan) -> PackagePin {
  self.root
}

///|
/// Dependency-first order, containing every supplied package exactly once.
pub fn Plan::packages(self : Plan) -> Array[Package] {
  self.packages.copy()
}

///|
priv enum VisitState {
  Visiting
  Complete
}

///|
priv enum Walk {
  Enter(PackagePin, Referrer)
  Leave(Package)
}

///|
fn require_package(
  pin : PackagePin,
  referrer : Referrer,
  packages : Map[String, Package],
) -> Package raise AssemblyError {
  guard packages.get(pin.name) is Some(entry) else {
    raise MissingPackage(referrer, pin)
  }
  if entry.pin != pin {
    raise RevisionMismatch(referrer, pin, entry.pin)
  }
  entry
}

///|
/// Validate the entire supplied assembly set, including unreferenced packages.
/// Iterative traversal avoids using the host call stack for dependency depth.
pub fn plan(
  root : PackagePin,
  supplied : Array[Package],
) -> Plan raise AssemblyError {
  let packages : Map[String, Package] = Map([])
  let pins : Array[PackagePin] = []
  for entry in supplied {
    if packages.contains(entry.pin.name) {
      raise DuplicatePackage(entry.pin.name)
    }
    packages[entry.pin.name] = entry
    pins.push(entry.pin)
  }
  require_package(root, SelectedRoot, packages) |> ignore
  pins.sort()
  let states : Map[String, VisitState] = Map([])
  let active : Array[PackagePin] = []
  let ordered : Array[Package] = []
  let work : Array[Walk] = []
  for pin in pins {
    work.push(Enter(pin, SuppliedAssembly))
    while !work.is_empty() {
      match work.pop().unwrap() {
        Enter(pin, referrer) => {
          let entry = require_package(pin, referrer, packages)
          match states.get(pin.name) {
            Some(Complete) => continue
            Some(Visiting) => {
              let mut start = 0
              while start < active.length() && active[start] != pin {
                start += 1
              }
              let cycle = Array::makei(active.length() - start, i => {
                active[start + i]
              })
              cycle.push(pin)
              raise DependencyCycle(cycle)
            }
            None => ()
          }
          states[pin.name] = Visiting
          active.push(pin)
          work.push(Leave(entry))
          for i = entry.dependencies.length() - 1; i >= 0; i = i - 1 {
            work.push(Enter(entry.dependencies[i].target, DependencyOf(pin)))
          }
        }
        Leave(entry) => {
          active.pop() |> ignore
          states[entry.pin.name] = Complete
          ordered.push(entry)
        }
      }
    }
  }
  { root, packages: ordered, }
}

///|
pub extend AssemblyError with @debug.Debug::{to_repr}

///|
pub extend Referrer with Eq::{equal, not_equal}

///|
pub extend Referrer with @debug.Debug::{to_repr}

///|
pub extend PackagePin with Eq::{equal, not_equal}

///|
pub extend PackagePin with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend PackagePin with @debug.Debug::{to_repr}

///|
pub extend Dependency with Eq::{equal, not_equal}

///|
pub extend Dependency with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend Dependency with @debug.Debug::{to_repr}

///|
pub extend Package with Eq::{equal, not_equal}

///|
pub extend Package with @debug.Debug::{to_repr}

///|
pub extend Plan with Eq::{equal, not_equal}

///|
pub extend Plan with @debug.Debug::{to_repr}
