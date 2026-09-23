//// The V3 library distribution. Dependencies carry public specifications.

import gleam/dict.{type Dict}
import morphir/ir/package
import morphir/ir/type_

pub type Distribution {
  Library(
    package_name: package.PackageName,
    dependencies: Dict(package.PackageName, package.Specification(Nil)),
    definition: package.Definition(Nil, type_.Type(Nil)),
  )
}
