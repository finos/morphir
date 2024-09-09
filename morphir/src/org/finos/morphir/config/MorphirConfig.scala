package org.finos.morphir.config
import kyo.*
import metaconfig.*
import metaconfig.generic.*
import metaconfig.sconfig.*

final case class MorphirConfig(
  workspace: Option[Workspace] = None,
  elm: Option[ElmConfigSection] = None,
  dependencies: Dependencies = Dependencies.empty,
  testDependencies: Dependencies = Dependencies.empty
):
  def containsWorkspace: Boolean = workspace.isDefined
  def workspaceProjects: IndexedSeq[String] = workspace match
    case Some(ws) => ws.projects
    case None     => IndexedSeq.empty

object MorphirConfig extends ConfigCompanion[MorphirConfig]:
  val default: MorphirConfig = MorphirConfig()

  given Surface[MorphirConfig]                  = generic.deriveSurface
  given confDecoder: ConfDecoder[MorphirConfig] = generic.deriveDecoder[MorphirConfig](MorphirConfig.default)

trait ConfigCompanion[Cfg](using decoder: ConfDecoder[Cfg]):

  def parseFile(file: os.Path): Result[ConfError, Cfg] =
    val input: Input = Input.File(file.toNIO.toFile)
    parseInput(input)

  def parseInput(input: Input): Result[ConfError, Cfg] =
    val conf = Conf.parseInput(input)
    decoder.read(conf).fold(error => Result.fail(error))(config => Result.success(config))

  // TODO: Change to not return metaconfig's `ConfError` and instead return a custom error type
  def parseString(input: String): Result[ConfError, Cfg] =
    val conf = Conf.parseString(input)
    decoder.read(conf).fold(error => Result.fail(error))(config => Result.success(config))
