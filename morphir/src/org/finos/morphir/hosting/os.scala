package org.finos.morphir.hosting

enum OsType:
  case Windows
  case Linux
  case MacOS
  case Other(name: String)

  def isWindows: Boolean = this == OsType.Windows
  def isLinux: Boolean   = this == OsType.Linux
  def isMacOS: Boolean   = this == OsType.MacOS
  def isOther: Boolean = this match
    case OsType.Other(_) => true
    case _               => false

sealed trait OsName extends Product with Serializable:
  import OsName.Repr
  def name: String

  def isWindows: Boolean = this match
    case _: Repr.Windows => true
    case _               => false

  def isLinux: Boolean = this match
    case _: Repr.Linux => true
    case _             => false

  def isMacOS: Boolean = this match
    case _: Repr.MacOS => true
    case _             => false

  def isOther: Boolean = this match
    case Repr.Other(_) => true
    case _             => false

  def osType: OsType = this match
    case _: Repr.Windows => OsType.Windows
    case _: Repr.Linux   => OsType.Linux
    case _: Repr.MacOS   => OsType.MacOS
    case Repr.Other(_)   => OsType.Other(name)

  override def toString: String = name

object OsName:
  def apply(): OsName =
    sys.props.get("os.name").map(parse).getOrElse(Repr.Other("Unknown"))

  def parse(name: String): OsName =
    if name.toLowerCase.contains("windows") then Repr.Windows(name)
    else if name.toLowerCase.contains("mac") then Repr.MacOS(name)
    else if name.toLowerCase.contains("linux") || name.contains("nix") then Repr.Linux(name)
    else Repr.Other(name)

  enum Repr extends OsName:
    case Windows(name: String)
    case Linux(name: String)
    case MacOS(name: String)
    case Other(name: String)
