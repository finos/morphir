//// Module representation for the Morphir IR.
//// A module is a container for types and values within a package.

import gleam/dict.{type Dict}
import gleam/option.{type Option}
import morphir/ir/access_controlled.{type AccessControlled}
import morphir/ir/documented.{type Documented}
import morphir/ir/name.{type Name}
import morphir/ir/path.{type Path}
import morphir/ir/type_
import morphir/ir/value

/// A module name is a Path identifying the module within a package.
pub type ModuleName =
  Path

/// A qualified module name combining package and module paths.
pub type QualifiedModuleName =
  #(Path, Path)

/// Module specification - the public interface of a module.
/// Contains only publicly exposed types and value signatures.
pub type Specification(ta) {
  Specification(
    types: Dict(Name, Documented(type_.Specification(ta))),
    values: Dict(Name, Documented(value.Specification(ta))),
    doc: Option(String),
  )
}

/// Module definition - the complete implementation of a module.
/// Contains all types and values, including private ones.
pub type Definition(ta, va) {
  Definition(
    types: Dict(Name, AccessControlled(Documented(type_.Definition(ta)))),
    values: Dict(Name, AccessControlled(Documented(value.Definition(ta, va)))),
    doc: Option(String),
  )
}
