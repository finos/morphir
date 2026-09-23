//// Qualified Name representation for the Morphir IR.
//// A QName (Qualified Name) combines a module path with a local name,
//// uniquely identifying a type or value within a module.

import morphir/ir/name.{type Name}
import morphir/ir/path.{type Path}

/// A QName is a module path combined with a local name.
pub type QName {
  QName(module_path: Path, local_name: Name)
}
