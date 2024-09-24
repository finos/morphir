package org.finos.morphir.cli.commands

import caseapp.*
import kyo.*
import org.finos.morphir.cli.{given, *}
import org.finos.morphir.cli.commands.shared.{given, *}
import org.graalvm.polyglot.*
import scala.util.Using

@HelpMessage("Generate Morphir IR from a Morphir project/model")
final case class MakeOptions(
  @Recurse
  globalOptions: GlobalOptions = GlobalOptions.default,
  @Group("Main")
  @Name("p")
  @ValueDescription("project root directory")
  @HelpMessage("Set root directory of the project where morphir.json is located. (default: .)")
  projectDir: os.Path = os.pwd,
  @Group("Main")
  @Name("o")
  @ValueDescription("output file")
  @HelpMessage("Set the target file location where the Morphir IR will be saved. (default: morphir-ir.json)")
  output: os.Path = os.pwd / "morphir-ir.json",
  @Group("Secondary")
  @Name("t")
  @HelpMessage("Only include type information in the IR, no values. (default: false)")
  typesOnly: Boolean = false,
  @Group("Formatting")
  @Name("i")
  @HelpMessage("Use indentation in the generated JSON file. (default: false)")
  indentJson: Boolean = false,
  @Group("Main")
  @Name("I")
  @ValueDescription("path or url")
  @HelpMessage(
    "Include additional Morphir distributions as a dependency. Can be specified multiple times. Can be a path, url, or data-url."
  )
  include: List[String] = Nil
)

object Make extends MorphirCliCommand[MakeOptions]:
  override def group = "Main"
  def runEffect(options: MakeOptions, remainingArgs: RemainingArgs) =
    defer {
      pprint.log("MakeOptions:")
      pprint.log(options)
      pprint.log("Remaining Args:")
      pprint.log(remainingArgs)
    }
