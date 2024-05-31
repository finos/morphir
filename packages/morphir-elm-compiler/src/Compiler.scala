package morphir
import scala.scalajs.js
import scala.scalajs.js.annotation._

enum SourceFile:
  case VirtualFile(path: String, content: String)

object Compiler:
  @JSExportTopLevel(name = "compile")
  def compile(sourceFile: SourceFile): String =
    sourceFile match
      case SourceFile.VirtualFile(path, content) =>
        s"Compiling $path with content: $content"
