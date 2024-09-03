package org.finos.morphir.lang.elm

import io.github.iltotore.iron.*
import org.finos.morphir.lang.elm.{ElmModuleName, ElmPackageName}
import org.finos.morphir.testing.MorphirSpecDefault
import zio.test.*
import zio.test.Assertion.*

object ElmProjectSpec extends MorphirSpecDefault {
  def spec = suite("ElmProjectSpec")(
    elmPackageNameSuite,
    elmModuleNameSuite
  )

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

  def elmModuleNameSuite = suite("ElmModuleName")(
    test("should be able to create a module with a valid name") {
      val moduleName = ElmModuleName("Author.Module")
      assertTrue(moduleName == "Author.Module")
    },
    test("should not be able to create a module with an invalid name") {
      compileError(
        """val moduleName = ElmModuleName("author.module")"""
      )(isLeft)
    },
    test("should not be able to create a module whose name ends in a .") {
      compileError(
        """val moduleName = ElmModuleName("Morphir.Sdk.")"""
      )(isLeft)
    },
    test("Can get the namespace from a module name with one") {
      val moduleName = ElmModuleName("Morphir.Sdk")
      assertTrue(moduleName.namespace == Some("Morphir"))
    },
    test("Can get the namespace from a module name with a longer namespace") {
      val moduleName = ElmModuleName("Morphir.IR.SDK.String")
      assertTrue(moduleName.namespace == Some("Morphir.IR.SDK"))
    }
  )
}
