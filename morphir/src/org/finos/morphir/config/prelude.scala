package org.finos.morphir.config
import kyo.*
import metaconfig.* 
import metaconfig.generic.* 
import metaconfig.sconfig.* 

final case class MorphirConfig(workspace: Option[Workspace]):
    def containsWorkspace: Boolean = workspace.isDefined
    def workspaceMembers:IndexedSeq[String] = workspace match
        case Some(ws) => ws.members
        case None => IndexedSeq.empty

object MorphirConfig extends ConfigCompanion[MorphirConfig]:
    given Surface[MorphirConfig] = generic.deriveSurface
    given confDecoder:ConfDecoder[MorphirConfig] = generic.deriveDecoder[MorphirConfig](MorphirConfig(None))


trait ConfigCompanion[Cfg](using decoder:ConfDecoder[Cfg]): 

    def parseFile(file:os.Path): Result[ConfError, Cfg] = 
        val input:Input = Input.File(file.toNIO.toFile)
        parseInput(input)
    
    def parseInput(input:Input): Result[ConfError, Cfg] = 
        val conf = Conf.parseInput(input)
        decoder.read(conf).fold(error => Result.fail(error))(config => Result.success(config))

    //TODO: Change to not return metaconfig's `ConfError` and instead return a custom error type
    def parseString(input:String): Result[ConfError, Cfg] = 
        val conf = Conf.parseString(input)
        decoder.read(conf).fold(error => Result.fail(error))(config => Result.success(config))