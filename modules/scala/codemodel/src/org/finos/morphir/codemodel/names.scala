package org.finos.morphir.codemodel
import neotype.*
import kyo.*
import scala.annotation.switch
import org.finos.morphir.codemodel.Path.Kind

type Name = Name.Type
object Name extends Newtype[SnakecaseName | TitlecaseName | LowercaseName | UppercaseName]

type KebabcaseName = KebabcaseName.Type
object KebabcaseName extends Newtype[String]:
  inline override def validate(input: String): Boolean = input.nonEmpty && input.forall(_.isLower)

type SnakecaseName = SnakecaseName.Type
object SnakecaseName extends Newtype[String]:
  inline override def validate(input: String): Boolean = input.nonEmpty && input.forall(_.isLower)

type TitlecaseName = TitlecaseName.Type
object TitlecaseName extends Newtype[String]:
  inline override def validate(input: String): Boolean = input.nonEmpty && input.head.isUpper

type LowercaseName = LowercaseName.Type
object LowercaseName extends Newtype[String]:
  inline override def validate(input: String): Boolean = input.nonEmpty && input.forall(_.isLower)

type UppercaseName = UppercaseName.Type
object UppercaseName extends Newtype[String]:
  inline override def validate(input: String): Boolean = input.nonEmpty && input.forall(_.isUpper)

type Path = Path.Type
object Path extends Newtype[PackagePath | ModulePath | GenericPath]

type GenericPath = LocalPath.Type
object GenericPath extends Newtype[Path.Repr]

type ModulePath = ModulePath.Type
object ModulePath extends Newtype[Path.Repr]

type PackagePath = PackagePath.Type
object PackagePath extends Newtype[Path.Repr]

object Path:
  case class Repr(parts: Chunk[Name], kind: Path.Kind)
  enum Kind:
    case Package, Module, Generic

sealed trait QualifiedName extends Product with Serializable:
  self =>

  def getPackage: Option[PackagePath] = self match
    case FQName(packagePath, _, _) => Some(packagePath)
    case _                         => None
  end getPackage

  def module: ModulePath
  def localName: Name

final case class FQName($package: PackagePath, module: ModulePath, localName: Name) extends QualifiedName:
  inline def packagePath: PackagePath = $package
  inline def modulePath: ModulePath   = module

final case class QName(module: ModulePath, localName: Name) extends QualifiedName
