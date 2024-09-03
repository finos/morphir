package org.finos.morphir.services
import org.finos.morphir.testing.MorphirKyoSpecDefault
import kyo.*
import zio.test.*
import zio.test.Assertion.*
object SystemSpec extends MorphirKyoSpecDefault {
  def spec = suite("SystemSpec")(
    test("should be able to get the environment variables") {
      System.SystemLive.envs.map { envs =>
        assertTrue(
          envs.nonEmpty,
          envs.contains("PATH")
        )
      }
    },
    test("should be able to get an environment variable directly") {
      System.SystemLive.env("PATH").map { path =>
        assertTrue(path.nonEmpty)
      }
    }
  )
}
