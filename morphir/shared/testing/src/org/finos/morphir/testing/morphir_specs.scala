package org.finos.morphir.testing
import kyo.test.*
import zio.{test as _, *}
import zio.test.*
import zio.test.TestAspect

import scala.annotation.nowarn
import zio.test.ZIOSpecDefault
import zio.test.ZIOSpecAbstract

abstract class MorphirKyoSpecDefault extends KyoSpecDefault with MorphirSpec {
  override def aspects = zio.Chunk(TestAspect.timeout(90.seconds))
}

abstract class MorphirSpecDefault extends ZIOSpecDefault with MorphirSpec {
  override def aspects = zio.Chunk(TestAspect.timeout(90.seconds))
}

trait MorphirSpec { self: ZIOSpecAbstract =>
  inline def compileError(code:String) = assertZIO(typeCheck(code))
}