package org.finos.morphir.api

import kyo.*
import org.finos.morphir.testing.*
import zio.test.{Result as _, *}

import metaconfig.*

object VersioningSpec extends MorphirSpecDefault {
  def spec = suite("VersioningSpec")(
    semVerStringSuite
  )

  def semVerStringSuite = suite("SemVerString")(
    test("Should be able to create a SemVerString with a valid version") {
      val semVerString = SemVerString("1.2.3")
      assertTrue(semVerString == "1.2.3")
    },
    test("Should be able to create a SemVerString with a valid pre-release version") {
      val semVerString = SemVerString("1.2.3-M01")
      assertTrue(semVerString == "1.2.3-M01")
    },
    test("Should not be able to create a SemVerString with an invalid version") {
      assertZIO(typeCheck(
        """val semVerString = SemVerString("1.2")"""
      ))(Assertion.isLeft)
    },
    test("Can decode from a Conf") {
      val conf   = Conf.Str("10.9.8-alpha-123")
      val result = SemVerString.confDecoder.read(conf)
      assertTrue(result == Configured.Ok(SemVerString("10.9.8-alpha-123")))
    }
  )
}
