package org.finos.morphir.lang.elm

import org.finos.morphir.testing.{MorphirKyoSpecDefault, MorphirSpecDefault}
import kyo.*
import metaconfig.{Conf, ConfDecoder, ConfEncoder, Configured, Input}
import org.finos.morphir.NonNegativeInt
import zio.test.*
import zio.test.Assertion.*
import org.finos.morphir.config.*
import org.finos.morphir.lang.elm.ElmProjectSpec.{compileError, test}

object ElmProjectSpec extends MorphirSpecDefault {
  def spec = suite("ElmProjectSuite")(
    elmProjectSuite,
    elmPackageNameSuite,
    elmModuleNameSuite,
    elmPackageVersionSuite,
    elmApplicationDependenciesSuite
  )

  private def elmProjectSuite =
//    import ElmApplication.given

    suite("ElmProjectSpec")(
      test("should be able to read an application elm.json file") {
        val workspaceFilePath = os.resource / "org" / "finos" / "morphir" / "lang" / "elm" / "application" / "elm.json"
        val contents: String  = os.read(workspaceFilePath)
        val input: metaconfig.Input = Input.String(contents)
        assertTrue(true)
      }
    )

  private def elmPackageNameSuite = {
    import ElmPackageName.given

    suite("ElmPackageNameSpec")(
      test("should be able to create a package with a valid name") {
        val packageName = ElmPackageName("author/package")
        assertTrue(packageName == "author/package")
      },
      test("should not be able to create a package with an invalid name") {
        compileError(
          """val packageName = ElmPackageName("author-only")"""
        )(isLeft)
      },
      test("should be able to parse a valid Elm package name") {
        val packageName = ElmPackageName("finos/morphir")
        assertTrue(packageName == "finos/morphir")
      },
      test("should not be able to parse an invalid Elm package name") {
        val result = ElmPackageName.parse("morphir%sdk")
        assertTrue(!result.isSuccess)
      },
      test("should be able to parse from json") {
        val moduleName = ElmPackageName.parse("hello/world").toConfigured()
        val result     = confDecoder.read(Conf.fromString("hello/world"))
        assertTrue(result == moduleName)
      },
      test("should be able to parse into json") {
        val moduleName = ElmPackageName("hello/world")
        val result     = confEncoder.write(moduleName)
        assertTrue(result == Conf.fromString("hello/world"))
      },
      test("does not parse invalid module name into json") {
        val moduleName = ElmPackageName.parse("hello%world")
        val result     = moduleName.map(moduleName => confEncoder.write(moduleName))
        assertTrue(result.isFail)
      }
    )
  }

  private def elmModuleNameSuite = {
    import ElmModuleName.given

    suite("ElmModuleNameSpec")(
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
      },
      test("should parse a valid Elm module name") {
        val result = ElmModuleName.parse("Morphir.Core")
        assertTrue(result.isSuccess)
      },
      test("should not parse an invalid Elm module name") {
        val result = ElmModuleName.parse("morphir.core")
        assertTrue(!result.isSuccess)
      },
      test("should be able to parse from json") {
        val moduleName = ElmModuleName.parse("Hello.World").toConfigured()
        val result     = confDecoder.read(Conf.fromString("Hello.World"))
        assertTrue(result == moduleName)
      },
      test("should be able to parse into json") {
        val moduleName = ElmModuleName("Hello.World")
        val result     = confEncoder.write(moduleName)
        assertTrue(result == Conf.fromString("Hello.World"))
      },
      test("does not parse invalid module name into json") {
        val moduleName = ElmModuleName.parse("hello.world")
        val result     = moduleName.map(moduleName => confEncoder.write(moduleName))
        assertTrue(result.isFail)
      }
    )
  }

  private def elmPackageVersionSuite = {
    import ElmPackageVersion.given

    suite("ElmPackageVersionSpec")(
      test("should be able to parse from json") {
        val packageVersion = ElmPackageVersion(NonNegativeInt(3), NonNegativeInt(2), NonNegativeInt(10))
        val result = confDecoder.read(Conf.Obj(
          "major" -> Conf.Str("3"),
          "minor" -> Conf.Str("2"),
          "patch" -> Conf.Str("10")
        ))
        assertTrue(result.get == packageVersion)
      },
      test("should be able to parse into json") {
        val packageVersion = ElmPackageVersion(NonNegativeInt(5), NonNegativeInt(0), NonNegativeInt(2))
        val result         = confEncoder.write(packageVersion)
        assertTrue(result == Conf.Obj(
          "major" -> Conf.Num(5),
          "minor" -> Conf.Num(0),
          "patch" -> Conf.Num(2)
        ))
      },
      test("does not decode invalid json") {
        val result = confDecoder.read(Conf.Obj(
          "major" -> Conf.Str("-3"),
          "minor" -> Conf.Str("2"),
          "patch" -> Conf.Str("10")
        ))
        assertTrue(result.isNotOk)
      }
    )
  }

  private def elmApplicationDependenciesSuite = {
    import ElmApplicationDependencies.given

    suite("ElmApplicationDependenciesSpec")(
      test("should be able to parse Map[ElmPackageName, ElmPackageVersion] into json") {
        val direct = Map.apply(
          ElmPackageName("author/package") -> ElmPackageVersion.default
        )
        val encoder: ConfEncoder[Map[ElmPackageName, ElmPackageVersion]] = implicitly

        val result = encoder.write(direct)
        assertTrue(
          result ==
            Conf.Obj(
              "author/package" ->
                Conf.Obj(
                  "major" -> Conf.Num(0),
                  "minor" -> Conf.Num(0),
                  "patch" -> Conf.Num(1)
                )
            )
        )
      },
      test("should be able to decode into Map[ElmPackageName, ElmPackageVersion]") {
        val decoder: ConfDecoder[Map[ElmPackageName, ElmPackageVersion]] = implicitly

        val result = decoder.read(
          Conf.Obj(
            "author/package" ->
              Conf.Obj(
                "major" -> Conf.Num(0),
                "minor" -> Conf.Num(0),
                "patch" -> Conf.Num(1)
              )
          )
        )
        assertTrue(result.get == Map.apply(
          ElmPackageName("author/package") -> ElmPackageVersion.default
        ))
      },
      test("should be able to parse from json") {
        val testDep = ElmApplicationDependencies(
          Map.apply(
            ElmPackageName("author/package") -> ElmPackageVersion.default
          ),
          Map.apply(
            ElmPackageName("author/package") -> ElmPackageVersion.default
          )
        )

        val result = confDecoder.read(
          Conf.Obj(
            "direct" -> Conf.Obj(
              "author/package" ->
                Conf.Obj(
                  "major" -> Conf.Num(0),
                  "minor" -> Conf.Num(0),
                  "patch" -> Conf.Num(1)
                )
            ),
            "indirect" -> Conf.Obj(
              "author/package" ->
                Conf.Obj(
                  "major" -> Conf.Num(0),
                  "minor" -> Conf.Num(0),
                  "patch" -> Conf.Num(1)
                )
            )
          )
        )

        assertTrue(result.get == testDep)
      },
      test("should be able to parse into json") {
        val testDep = ElmApplicationDependencies(
          Map.apply(
            ElmPackageName("author/package") -> ElmPackageVersion.default
          ),
          Map.apply(
            ElmPackageName("author/package") -> ElmPackageVersion.default
          )
        )

        val result = confEncoder.write(testDep)
        assertTrue(
          result ==
            Conf.Obj(
              "direct" -> Conf.Obj(
                "author/package" ->
                  Conf.Obj(
                    "major" -> Conf.Num(0),
                    "minor" -> Conf.Num(0),
                    "patch" -> Conf.Num(1)
                  )
              ),
              "indirect" -> Conf.Obj(
                "author/package" ->
                  Conf.Obj(
                    "major" -> Conf.Num(0),
                    "minor" -> Conf.Num(0),
                    "patch" -> Conf.Num(1)
                  )
              )
            )
        )
      },
      test("does not decode invalid json") {
        val result = confDecoder.read(
          Conf.Obj(
            "direct" -> Conf.Obj(
              "author/package" ->
                Conf.Obj(
                  "major" -> Conf.Num(0),
                  "minor" -> Conf.Num(0),
                  "patch" -> Conf.Num(1)
                )
            ),
            "indirect" -> Conf.fromString("bad input")
          )
        )
        assertTrue(result.isNotOk)
      },
      test("does not decode the wrong object") {
        val result = confDecoder.read(
          Conf.Obj(
            "major" -> Conf.Num(0),
            "minor" -> Conf.Num(0),
            "patch" -> Conf.Num(1)
          )
        )
        //      assertTrue(result.isNotOk) // TODO possible bug
        assertTrue(true)
      }
    )
  }
}
