package org.finos.morphir.hosting

import kyo.*
import org.finos.morphir.testing.*
import zio.test.*
import zio.Cause

object HostInfoServiceSpec extends MorphirKyoSpecDefault:
  def spec = suite("HostInfoServiceSpec")(
    test("applicationConfigDir should return a path") {
      val service = HostInfoService.Live()
      for {
        path <- service.applicationConfigDir
        name = path.name.toLowerCase

        // _ <- Console.println(pprint(path))
      } yield assertTrue(path != null, name.endsWith("morphir"))

    }
  )
