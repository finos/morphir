//// Package representation for the Morphir IR.
//// A package is a collection of modules that are versioned together.
//// It represents a deployable unit of Morphir code.

import gleam/dict.{type Dict}
import morphir/ir/access_controlled.{type AccessControlled}
import morphir/ir/module
import morphir/ir/path.{type Path}

/// A package name is a Path that globally identifies the package.
pub type PackageName =
  Path

/// Package specification - the public interface of a package.
/// Contains only exposed module specifications.
pub type Specification(ta) {
  Specification(modules: Dict(module.ModuleName, module.Specification(ta)))
}

/// Package definition - the complete implementation of a package.
/// Contains all modules, with access control.
pub type Definition(ta, va) {
  Definition(
    modules: Dict(
      module.ModuleName,
      AccessControlled(module.Definition(ta, va)),
    ),
  )
}
