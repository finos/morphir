package org.finos.morphir.testing

import zio.{test as _, *}
import zio.test.*

import scala.annotation.nowarn

abstract class MorphirBaseSpec extends ZIOSpecDefault {
  override def aspects = Chunk(TestAspect.timeout(90.seconds))
}
