package org.finos.morphir.command.lang.elm

import org.finos.morphir.testing.MorphirKyoSpecDefault 
import zio.test.*
import zio.test.Assertion.*

object FetchSpec extends MorphirKyoSpecDefault {
  def spec = suite("FetchSpec")(
    test("should be able to create a fetch command") {
      val fetch = Fetch(FetchParams())
      assertTrue(fetch != null)
    }
  )
}

