package org.finos.morphir.workspaces
import org.finos.morphir.testing.* 
import zio.test.*

object ProjectNameSpec extends MorphirSpecDefault {
  def spec = suite("ProjectNameSpec")(
    test("ProjectName should be able to be created") {
      import io.github.iltotore.iron.*
      val projectName = ProjectName("Morphir.SDK")
      assertTrue(projectName.value == "Morphir.SDK")
    },
    test("ProjectName should be able to be parsed") {
      val projectName = ProjectName.parse("Morphir.SDK")
      assertTrue(projectName == Right(ProjectName.assume("Morphir.SDK")))
    },
    test("ProjectName should fail to parse invalid names") {
      val projectName = ProjectName.parse("Morphir.SDK!")
      println(projectName)
      assertTrue(projectName.isLeft)
    }
  )
}
