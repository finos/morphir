package org.finos.morphir.testing
import kyo.test.*
import zio.*
import zio.test.TestAspect

import scala.annotation.nowarn

abstract class MorphirSpecDefault extends KyoSpecDefault {
  override def aspects = zio.Chunk(TestAspect.timeout(90.seconds))
}
