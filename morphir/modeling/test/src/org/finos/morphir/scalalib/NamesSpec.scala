package org.finos.morphir.scalalib
import org.finos.morphir.testing.* 
import zio.test.* 
import org.finos.morphir.fs.Path.Root.name

object NamesSpec extends MorphirSpecDefault {
    def spec = suite("NamesSpec")(lowerCaseNameSuite)

    def lowerCaseNameSuite = suite("LowercaseName")(
        test("Should be able to create a lowercase name") {
            val name = LowercaseName("hello")
            assertTrue(name.str == "hello")
        } 
        + test("Should not be able to create a lowercase name with an uppercase character") {
            val name = LowercaseName("Hello") 
            assertTrue(name.str == "hello")
        }
    )
}
