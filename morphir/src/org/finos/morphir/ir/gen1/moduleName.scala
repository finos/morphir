package org.finos.morphir.ir.gen1

import neotype.*

/** A module name is a unique identifier for a module within a package. It is represented by a `Path`, which is a "list"
  * of names.
  */
type ModuleName = ModuleName.Type

object ModuleName extends Newtype[Path] {
  /// Create an empty module name.
  val empty: ModuleName = ModuleName(Path.empty)

  def apply(input: String): ModuleName = fromString(input)

  def unapply(input: ModuleName): Option[Path] = Some(input.path)

  def fromString(input: String): ModuleName = ModuleName(Path.fromString(input))

  def apply(parts: Name*): ModuleName                    = ModuleName(Path.fromIterable(parts))
  def fromIterable(segments: Iterable[Name]): ModuleName = ModuleName(Path.fromIterable(segments))
  def fromStrings(parts: String*): ModuleName            = ModuleName(Path.fromStrings(parts: _*))

  extension (self: ModuleName)
    def path: Path = self.unwrap

    /// Construct a new module name by concatting the given module name to this one.
    def ++(other: ModuleName): ModuleName = ModuleName(path ++ other.path)

    /// Construct a new module name by concatting the given local name to this module name.
    def /(name: Name): ModuleName = ModuleName(path / name)
    /// Construct a new module name by concatting the given local name to this module name.
    def /(name: String): ModuleName = ModuleName(path / Name(name))

    // Need a non-symbolic version of this for QualifiedModuleName, strange compilation errors
    // happen in QualifiedModuleName./(str: String) implementation when using `moduleName / str` otherwise
    def addPart(name: String): ModuleName = ModuleName(path / Name(name))

    /// Check if the module name is empty.
    @inline def isEmpty: Boolean = path.isEmpty

    /// Get the name of this module.
    /// For example if the module name is `Morphir.SDK.Basics` then the name is `Basics`.
    def name: Name =
      path match {
        case ModuleName(Path(Vector())) => Name.empty
        case ModuleName(Path(segments)) => segments.last
      }

    // Get the name of this module if a name is present.
    def nameOption: Option[Name] =
      path match {
        case ModuleName(Path(Vector())) => None
        case ModuleName(Path(segments)) => Some(segments.last)
      }

    /// Convert this module name to a `Path`.
    @inline def toPath: Path = path
    def render: String       = path.toString
}
