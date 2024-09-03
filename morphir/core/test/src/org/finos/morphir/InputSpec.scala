package org.finos.morphir
import org.finos.morphir.testing.*
import zio.test.*
import zio.test.Assertion.*
import org.finos.morphir.Path.Root.name

object InputSpec extends MorphirKyoSpecDefault {
  def spec = suite("InputSpec")(virtualFileSuite)

  def virtualFileSuite = suite("VirtualFile")(
    test("Can be created by a path and some string content") {
      val contents = """
                       |# Content
                       |
                       |Here is some content!
                       |""".stripMargin
      val vpath  = VirtualPath.parse("subproja/example.txt")
      val actual = Input.VirtualFile(path = vpath, contents = contents)
      assertTrue(
        actual.path == vpath && actual.contents == contents
      )
    }
  )
}
