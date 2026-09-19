//// Fully Qualified Name representation for the Morphir IR.
//// An FQName (Fully Qualified Name) combines a package path, module path,
//// and local name to uniquely identify any type or value across packages.

import morphir/ir/name.{type Name}
import morphir/ir/path.{type Path}

/// An FQName is a fully qualified name consisting of:
/// - package_path: The path identifying the package
/// - module_path: The path identifying the module within the package
/// - local_name: The local name within the module
pub type FQName {
  FQName(package_path: Path, module_path: Path, local_name: Name)
}
