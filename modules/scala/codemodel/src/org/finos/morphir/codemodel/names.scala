package org.finos.morphir.codemodel
import neotype.*
import kyo.*
import scala.annotation.switch
import org.finos.morphir.codemodel.Path.Kind

type Name = Name.Type
object Name extends Newtype[SnakecaseName | TitlecaseName | LowercaseName | UppercaseName]

type KebabcaseName = KebabcaseName.Type
object KebabcaseName extends Newtype[String]:
    override inline def validate(input:String):Boolean = input.nonEmpty && input.forall(_.isLower)

type SnakecaseName = SnakecaseName.Type
object SnakecaseName extends Newtype[String]:
    override inline def validate(input:String):Boolean = input.nonEmpty && input.forall(_.isLower)

type TitlecaseName = TitlecaseName.Type
object TitlecaseName extends Newtype[String]:
    override inline def validate(input:String):Boolean = input.nonEmpty && input.head.isUpper

type LowercaseName = LowercaseName.Type
object LowercaseName extends Newtype[String]:
    override inline def validate(input:String):Boolean = input.nonEmpty && input.forall(_.isLower)

type UppercaseName = UppercaseName.Type
object UppercaseName extends Newtype[String]:
    override inline def validate(input:String):Boolean = input.nonEmpty && input.forall(_.isUpper)    

sealed trait PathLike extends Product with Serializable:
    def parts:Chunk[Name]
    def kind:Path.Kind

enum Path extends PathLike:
    case PackagePath(parts:Chunk[Name]) extends Path(parts)
    case ModulePath(parts:Chunk[Name]) extends Path(parts)
    case LocalPath(name:Name) extends Path(Chunk(name))

object Path:
    enum Kind:
        case Package, Module, Local     


