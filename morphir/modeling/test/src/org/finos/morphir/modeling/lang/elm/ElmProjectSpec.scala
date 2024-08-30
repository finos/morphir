package org.finos.morphir.modeling.lang.elm

import io.github.iltotore.iron.*
import org.finos.morphir.testing.MorphirSpecDefault
import zio.test.*
import zio.test.Assertion.*

object ElmProjectSpec extends MorphirSpecDefault {
    def spec = suite("ElmProjectSpec")(elmPackageNameSuite)

    def elmPackageNameSuite = suite("ElmPackageName")(
        test("should be able to create a package with a valid name") {
            val packageName = ElmPackageName("author/package")
            assertTrue(packageName == "author/package")
        },
        test("should not be able to create a package with an invalid name") {
            compileError(
                """val packageName = ElmPackageName("author-only")"""
            )(isLeft)
        }
    )
}
