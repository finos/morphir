package org.finos.morphir.trees
import neotype.*
import io.github.iltotore.iron.*
import io.github.iltotore.iron.constraint.string.*
import kyo.*
import scala.annotation.switch
import org.finos.morphir.trees.Path.Kind

type Name = Name.Type
object Name extends Newtype[SnakecaseName | TitlecaseName | LowercaseName | UppercaseName]

type KebabcaseName = KebabcaseName.Type
object KebabcaseName extends Newtype[String]:
  inline override def validate(input: String): Boolean = input.nonEmpty && input.forall(_.isLower)

type SnakecaseName = SnakecaseName.Type
object SnakecaseName extends Newtype[String]:
  val nameRegex                                        = "^[a-z][a-z0-9_]*$".r
  inline override def validate(input: String): Boolean = nameRegex.matches(input)

type TitlecaseName = TitlecaseName.Type
object TitlecaseName extends Newtype[String]:
  val nameRegex                                        = "^[A-Z][a-zA-Z0-9]*$".r
  inline override def validate(input: String): Boolean = nameRegex.matches(input)

type LowercaseName = LowercaseName.Type
object LowercaseName extends Newtype[String]:
  inline override def validate(input: String): Boolean = input.nonEmpty && input.forall(_.isLower)
  extension (name: LowercaseName)
    def str: String = unwrap(name)

type UppercaseName = UppercaseName.Type
object UppercaseName extends Newtype[String]:
  inline override def validate(input: String): Boolean = input.nonEmpty && input.forall(_.isUpper)

type Path = Path.Type
object Path extends Newtype[PackagePath | ModulePath | AnyPath]:
  case class Repr(parts: Chunk[Name], kind: Path.Kind)
  enum Kind:
    case Package, Module, Any

type AnyPath = AnyPath.Type
object AnyPath extends Newtype[Path.Repr]

type ModulePath = ModulePath.Type
object ModulePath extends Newtype[Path.Repr]

type PackagePath = PackagePath.Type
object PackagePath extends Newtype[Path.Repr]

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
