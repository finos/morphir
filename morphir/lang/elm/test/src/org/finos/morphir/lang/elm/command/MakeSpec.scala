package org.finos.morphir.lang.elm.command

import org.finos.morphir.testing.MorphirKyoSpecDefault
import zio.test.*
import zio.test.Assertion.*

object MakeSpec extends MorphirKyoSpecDefault {
  def spec = suite("MakeSpec")(
    test("should be able to create a make command") {
      val cmd = Make(MakeParams())
      assertTrue(cmd != null)
    }
  )
}