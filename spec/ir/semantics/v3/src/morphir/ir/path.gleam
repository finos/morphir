//// Path representation for the Morphir IR.
//// A Path is a list of Names that identifies modules, packages, or other
//// hierarchical elements in the IR.

import morphir/ir/name.{type Name}

/// A Path is a list of Names forming a hierarchical identifier.
pub type Path =
  List(Name)
