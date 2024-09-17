package org.finos.morphir.hosting
import io.github.iltotore.iron.*
import io.github.iltotore.iron.constraint.all.*
import kyo.*
import org.finos.morphir.testing.*
import zio.{test as _, *}
import zio.test.*

object EnvironmentNameSpec extends MorphirSpecDefault:
  def spec = suite("EnvironmentNameSpec")(
    suite("Custom naming")(
      test("apply should return a custom environment name when given a custom name") {
        val name = EnvironmentName("custom")
        assertTrue(name == EnvironmentName.Custom("custom".assume))
      },
      test("apply should return a custom environment name when given a custom name with spaces") {
        val name = EnvironmentName("User Acceptance Test")
        assertTrue(name == EnvironmentName.Custom("User Acceptance Test".assume))
      }
    ),
    test("customUnsafe should return a custom environment name") {
      val name = EnvironmentName.customUnsafe("custom", EnvironmentType.Development)
      assertTrue(name == EnvironmentName.Custom("custom".assume, EnvironmentType.Development))
    },
    test("customUnsafe should throw an IllegalArgumentException when given a reserved name") {
      for {
        exit <- ZIO.attempt {
          EnvironmentName.customUnsafe("development", EnvironmentType.Development)
        }.exit
      } yield assertTrue(
        exit.is(_.failure).getMessage == "Custom environment name cannot be one of the reserved names: 'development', 'dev', 'test', 'production', 'prod'"
      )
    },
    test("custom should return a custom environment name") {
      val name = EnvironmentName.custom("custom", EnvironmentType.Development)
      assertTrue(name == Right(EnvironmentName.Custom("custom".assume, EnvironmentType.Development)))
    },
    test("custom should provide an Error when given a reserved name") {
      val actual = EnvironmentName.custom("development", EnvironmentType.Development)
      assertTrue(
        actual.is(_.left) == "Custom environment name cannot be one of the reserved names: 'development', 'dev', 'test', 'production', 'prod'"
      )
    }
  )
