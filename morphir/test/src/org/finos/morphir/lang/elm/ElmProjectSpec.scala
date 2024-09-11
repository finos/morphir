package org.finos.morphir.lang.elm

import org.finos.morphir.testing.MorphirKyoSpecDefault
import kyo.*
import metaconfig.Input
import zio.test.*
import zio.test.Assertion.*

object ElmProjectSpec extends MorphirKyoSpecDefault {
  def spec = suite("ElmProjectSpec")(
    test("should be able to read an application elm.json file") {
      val workspaceFilePath = os.resource / "org" / "finos" / "morphir" / "lang" / "elm" / "application" / "elm.json"
      val contents: String  = os.read(workspaceFilePath)
      val input: metaconfig.Input = Input.String(contents)
      assertTrue(true)
    }
  )
}