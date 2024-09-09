package org.finos.morphir.config
import kyo.*
import org.finos.morphir.testing.*
import metaconfig.{pprint as _, *}
import metaconfig.sconfig.*
import zio.test.*
object ConfigSpec extends MorphirSpecDefault: 
    def spec = suite("ConfigSpec")(
        workspaceMembersSuite
    )

    def workspaceMembersSuite = suite("Workspace Members")(
        test("Workspace should be able to be loaded") {
            val workspaceFilePath = os.resource / "org" / "finos" / "morphir" / "config" / "workspace-01.conf"
            val contents:String = os.read(workspaceFilePath)
            val input:metaconfig.Input = Input.String(contents)
            val result = MorphirConfig.parseInput(input)
            pprint.log(result)
            assertTrue(
                result.isSuccess,
                result.value.get.containsWorkspace == true,
                result.value.get.workspaceProjects == IndexedSeq("common","project-01","project-02")
            )  
        },

    )