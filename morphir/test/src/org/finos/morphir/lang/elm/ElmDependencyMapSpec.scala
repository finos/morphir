package org.finos.morphir.lang.elm

import org.finos.morphir.testing.{MorphirKyoSpecDefault, MorphirSpecDefault}
import kyo.*
import metaconfig.{pprint as _, *}
import metaconfig.sconfig.*
import org.finos.morphir.api.*
import zio.test.*
import zio.test.Assertion.*
import org.finos.morphir.config.*
import org.finos.morphir.lang.elm.ElmProjectSpec.{compileError, test}
import com.github.plokhotnyuk.jsoniter_scala.macros.*
import com.github.plokhotnyuk.jsoniter_scala.core.*
import com.github.plokhotnyuk.jsoniter_scala.macros.JsonCodecMaker.*

object ElmDependencyMapSpec extends MorphirSpecDefault:
  def spec = suite("ElmDependencyMapSpec")(
    jsonCodecSuite,
    metaconfigSuite
  )

  def jsonCodecSuite = suite("JSON codec")(
    test("Should be able to serialize and deserialize an ElmDependencyMap") {
      val elmDependencyMap =
        ElmDependencyMap(Map(
          ElmPackageName("finos/morphir")        -> ElmPackageVersion.parseUnsafe("1.0.0"),
          ElmPackageName("morphir/test_project") -> ElmPackageVersion.parseUnsafe("2.0.0")
        ))
      val json     = writeToString(elmDependencyMap)
      val expected = """{"finos/morphir":"1.0.0","morphir/test_project":"2.0.0"}"""
      assertTrue(json == expected)
      val deserialized = readFromString[ElmDependencyMap](json)
      assertTrue(deserialized == elmDependencyMap)
    }
  )

  def metaconfigSuite = suite("Metaconfig")(
    test("Can decode from an object") {
      val conf   = Conf.parseString("""{"finos/morphir":"1.0.0"}""")
      val result = ElmDependencyMap.confDecoder.read(conf)
      assertTrue(result == Configured.Ok(
        ElmDependencyMap(Map(ElmPackageName("finos/morphir") -> ElmPackageVersion.parseUnsafe("1.0.0")))
      ))
    },
    test("Can decode from an object with multiple dependencies") {
      val conf = Conf.parseString(
        """
          |{
          |   "finos/morphir":"1.0.0"
          |   "morphir/test_project":"2.0.0"
          |}""".stripMargin
      )
      val result = ElmDependencyMap.confDecoder.read(conf)
      assertTrue(result == Configured.Ok(
        ElmDependencyMap(
          Map(
            ElmPackageName("finos/morphir")        -> ElmPackageVersion.parseUnsafe("1.0.0"),
            ElmPackageName("morphir/test_project") -> ElmPackageVersion.parseUnsafe("2.0.0")
          )
        )
      ))
    }
  )
end ElmDependencyMapSpec
