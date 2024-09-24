package org.finos.morphir.lang.elm

import org.finos.morphir.testing.{MorphirKyoSpecDefault, MorphirSpecDefault}
import kyo.*
import metaconfig.*
import metaconfig.sconfig.*
import org.finos.morphir.api.*
import zio.test.*
import zio.test.Assertion.*
import org.finos.morphir.config.*
import org.finos.morphir.lang.elm.ElmProjectSpec.{compileError, test}
import com.github.plokhotnyuk.jsoniter_scala.macros.*
import com.github.plokhotnyuk.jsoniter_scala.core.*
import com.github.plokhotnyuk.jsoniter_scala.macros.JsonCodecMaker.*

object ElmTypesSpec extends MorphirSpecDefault:
  def spec = suite("ElmTypesSpec")(
    elmPackageVersionSuite
  )

  def elmPackageVersionSuite = suite("ElmPackageVersion")(
    test("Should be able to create a ElmPackageVersion with a valid version") {
      val elmPackageVersion = ElmPackageVersion(MajorVersionNumber(1), MinorVersionNumber(2), PatchVersionNumber(3))
      assertTrue(elmPackageVersion.toString() == "1.2.3")
    },
    test("Should be able to create a ElmPackageVersion with a valid version") {
      val elmPackageVersion = ElmPackageVersion(MajorVersionNumber(0), MinorVersionNumber(0), PatchVersionNumber(1))
      assertTrue(elmPackageVersion.toString() == "0.0.1")
    },
    test("Should not be able to create a ElmPackageVersion with an invalid version") {
      assertZIO(typeCheck(
        """val elmPackageVersion = ElmPackageVersion(NonNegativeInt(1), NonNegativeInt(2), NonNegativeInt(-3))"""
      ))(isLeft)
    },
    test("Can decode from a String") {
      val conf   = Conf.Str("10.9.8")
      val result = ElmPackageVersion.confDecoder.read(conf)
      assertTrue(result == Configured.Ok(ElmPackageVersion(
        major"10",
        minor"9",
        patch"8"
      )))
    },
    test("Can decode from an object") {
      val conf   = Conf.parseString("""{major:10, minor:9, patch:8}""")
      val result = ElmPackageVersion.confDecoder.read(conf)
      assertTrue(result == Configured.Ok(ElmPackageVersion(
        MajorVersionNumber(10),
        MinorVersionNumber(9),
        PatchVersionNumber(8)
      )))
    }
      +
        suite("JSON Serialization")(
          test("Should be able to serialize and deserialize a ElmPackageVersion") {
            val elmPackageVersion = ElmPackageVersion(major(1), minor(2), patch(3))
            val json              = writeToString(elmPackageVersion)
            val expected          = """"1.2.3""""
            assertTrue(json == expected)
            val deserialized = readFromString[ElmPackageVersion](json)
            assertTrue(deserialized == elmPackageVersion)
          },
          test("Should be able to parse a ElmPackageVersion from a JSON string") {
            val json         = """"1.2.3""""
            val expected     = ElmPackageVersion(major(1), minor(2), patch(3))
            val deserialized = readFromString[ElmPackageVersion](json)
            assertTrue(deserialized == expected)
          },
          test("Should be able to parse a ElmPackageVersion from a JSON object") {
            val json         = """{"major":1,"minor":2,"patch":3}"""
            val expected     = ElmPackageVersion(major(1), minor(2), patch(3))
            val deserialized = readFromString[ElmPackageVersion](json)
            assertTrue(deserialized == expected)
          }
        )
  )
