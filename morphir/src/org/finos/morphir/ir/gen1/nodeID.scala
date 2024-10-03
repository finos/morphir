package org.finos.morphir.ir.gen1

import NodePath.*

/** Represents a path in the IR.
  * ==Overview==
  * A NodeID can have two slightly different structures depending on if we are refering to modules or definitions
  * (types/values).
  *
  *   - When refefering to modules: `"module:<Package>:<Module>"`
  *   - When refering to definitions: `"type\value:<Package>:<Module><localName>#<nodePath>"`, where nodePath is
  *     optional
  *
  * Examples of valid NodeIDs:
  *   - "module:Morphir.Reference.Model:BooksAndRecords"
  *   - "type:Morphir.Reference.Model:BooksAndRecords:deal"
  *   - "value:Morphir.Reference.Model:BooksAndRecords:deal#1"
  *
  * ==Referring to modules==
  * We can refer to modules by their Qualified Name, with the module: prefix
  *
  * For example: `"module:Morphir.Reference.Model:BooksAndRecords"` refers to the `Books and Records` module inside the
  * `Morphir.Reference.Model` package.
  */
sealed trait NodeID extends Product with Serializable { self =>
  import NodeID.*
  override def toString(): String = {
    implicit val renderer: PathRenderer = PathRenderer.TitleCase
    def mapToTypeOrValue(
      packageName: Path,
      moduleName: Path,
      localName: Name,
      suffix: String,
      nodePath: NodePath
    ): String = {
      val nodeIdString = s"${packageName.render}:${moduleName.render}:${localName.toCamelCase}$suffix"
      nodePath match {
        case NodePath(Vector()) => nodeIdString
        case _                  => s"$nodeIdString$nodePath"
      }
    }

    self match {
      case ModuleID(packagePath, modulePath) =>
        s"${packagePath.path.render}:${modulePath.path.render}"
      case TypeID(FQName(packageName, moduleName, localName), path) =>
        mapToTypeOrValue(packageName.path, moduleName.path, localName, ".type", path)
      case ValueID(FQName(packageName, moduleName, localName), path) =>
        mapToTypeOrValue(packageName.path, moduleName.path, localName, ".value", path)
    }
  }
}
type NodeIDCompanion = NodeID.type
object NodeID {

  def fromQualifiedName(qualifiedModuleName: QualifiedModuleName): NodeID =
    ModuleID.fromQualifiedName(qualifiedModuleName)

  def fromString(input: String): Either[Error, NodeID] = {
    def mapToTypeOrValue(packageName: String, moduleName: String, defNameWithSuffix: String, nodePath: String) = {
      def defName(suffix: String) = defNameWithSuffix.dropRight(suffix.length())
      if (defNameWithSuffix.endsWith(".value"))
        Right(ValueID(FQName.fqn(packageName, moduleName, defName(".value")), NodePath.fromString(nodePath)))
      else
        Right(TypeID(FQName.fqn(packageName, moduleName, defName(".type")), NodePath.fromString(nodePath)))
    }

    input.split(":") match {
      case Array(packageName, moduleName) =>
        Right(ModuleID(Path(packageName), Path(moduleName)))
      case Array(packageName, moduleName, localName) =>
        if (localName.contains("#"))
          localName.split("#") match {
            case Array(defName, path) => mapToTypeOrValue(packageName, moduleName, defName, path)
            case _                    => Left(Error.InvalidNodeId(input))
          }
        else
          mapToTypeOrValue(packageName, moduleName, localName, "")
      case _ =>
        Left(Error.InvalidNodeId(input))
    }
  }

  sealed case class TypeID(name: FQName, memberPath: NodePath)                 extends NodeID
  sealed case class ValueID(name: FQName, memberPath: NodePath)                extends NodeID
  sealed case class ModuleID(packageName: PackageName, moduleName: ModuleName) extends NodeID
  object ModuleID {
    def apply(packagePath: Path, modulePath: Path): ModuleID =
      ModuleID(PackageName(packagePath), ModuleName(modulePath))

    def fromQualifiedName(qualifiedModuleName: QualifiedModuleName): ModuleID =
      ModuleID(qualifiedModuleName.packageName, qualifiedModuleName.modulePath)
  }

  sealed abstract class Error(errorMessage: String) extends Exception(errorMessage)
  object Error {
    sealed case class InvalidPath(input: String, errorMessage: String) extends Error(errorMessage)
    sealed case class InvalidNodeId(input: String, errorMessage: String) extends Error(errorMessage) {
      def this(input: String) = this(input, s"Invalid NodeId: $input")
    }

    object InvalidNodeId {
      def apply(input: String): InvalidNodeId = new InvalidNodeId(input)
    }
  }
}

sealed case class NodePath(steps: Vector[NodePathStep]) { self =>
  import NodePathStep.*

  def /(step: NodePathStep): NodePath = NodePath(steps :+ step)
  def /(name: String): NodePath       = self / ChildByName(Name.fromString(name))

  @inline def isEmpty: Boolean = steps.isEmpty

  override def toString(): String =
    if (self.isEmpty) ""
    else
      steps.map {
        case ChildByName(name)   => name.toCamelCase
        case ChildByIndex(index) => index.toString()
      }.mkString("#", ":", "")
}

object NodePath {
  import NodePathStep.*
  val empty: NodePath = NodePath(Vector.empty)

  @inline def fromIterable(iterable: Iterable[NodePathStep]): NodePath = NodePath(iterable.toVector)

  def fromString(input: String): NodePath =
    if (input.isEmpty()) empty
    else
      fromIterable(input.split(":").map { stepString =>
        stepString.toIntOption match {
          case Some(index) => NodePathStep.childByIndex(index)
          case None        => NodePathStep.childByName(stepString)
        }
      })
}

sealed trait NodePathStep
object NodePathStep {
  def childByName(input: String): NodePathStep = ChildByName(Name.fromString(input))
  def childByIndex(index: Int): NodePathStep   = ChildByIndex(index)

  sealed case class ChildByName(name: Name)  extends NodePathStep
  sealed case class ChildByIndex(index: Int) extends NodePathStep
}

trait HasId {
  def id: NodeID
}
