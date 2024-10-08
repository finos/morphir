package org.finos.morphir.ir.gen1

/// A qualified name (`QName`) is a combination of a module path and a local name.
sealed case class QName(moduleName: ModuleName, localName: Name) {
  def modulePath: Path = moduleName.path

  /// Turn a qualified name into a tuple of a module path and a local name.
  @inline def toTuple: (Path, Name) = (modulePath, localName)

  override def toString: String =
    modulePath.toString(Name.toTitleCase, ".") + ":" + localName.toCamelCase

}

object QName {
  val empty: QName = QName(ModuleName.empty, Name.empty)

  def apply(moduleName: String, localName: String): QName =
    QName(ModuleName.fromString(moduleName), Name.fromString(localName))

  /// Turn a qualified name into a tuple of a module path and a local name.
  def toTuple(qName: QName): (Path, Name) = qName.toTuple

  /// Turn a tuple of a module path and a local name into a qualified name (`QName`).
  def fromTuple(tuple: (Path, Name)): QName = QName(ModuleName(tuple._1), tuple._2)

  /// Creates a qualified name from a module path and a local name.
  def fromName(modulePath: Path, localName: Name): QName = QName(ModuleName(modulePath), localName)

  /// Creates a qualified name from strings representing a module path and a local name.
  def fromName(modulePath: String, localName: String): QName =
    QName(ModuleName(Path.fromString(modulePath)), Name.fromString(localName))

  /// Get the local name part of a qualified name.
  def getLocalName(qname: QName): Name = qname.localName

  /// Get the module path part of a qualified name.
  def getModulePath(qname: QName): Path = qname.modulePath

  /// Turn a `QName` into a string using `:` as the separator between the module path and the local name.
  def toString(qName: QName): String = qName.toString

  /// Parse a string into a qualified name using `:` as the separator between the module path and the local name.
  def fromString(str: String): Option[QName] =
    str.split(":") match {
      case Array(packageNameString, localNameString) =>
        Some(QName(ModuleName(Path.fromString(packageNameString)), Name.fromString(localNameString)))
      case _ => None
    }
}
