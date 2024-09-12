package org.finos.morphir.cli.command
import org.finos.morphir.*
import caseapp.*
import org.finos.morphir.cli.given

@HelpMessage("Start up a web server and expose developer tools through a web UI.")
final case class DevelopOptions(
  @Name("p")
  @HelpMessage("Port to bind the web server to. (default: 3000)")
  port: Int = 3000,
  @Name("o")
  @HelpMessage("Host to bind the web server to. (default: localhost)")
  host: String = "localhost",
  @Name("i")
  @HelpMessage("Root directory of the project where morphir.json is located. (default: .)")
  projectDir: FilePath = FilePath.parse(os.pwd.toString)
)

object Develop extends Command[DevelopOptions]:
  def run(options: DevelopOptions, remainingArgs: RemainingArgs): Unit =
    pprint.log("DevelopOptions:")
    pprint.log(options)
    pprint.log("Remaining Args:")
    pprint.log(remainingArgs)
