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
  import MorphirSpec.TestContext
  def testContext(using testFile:sourcecode.File):TestContext = TestContext(testFile.value)
  inline def compileError(code: String) = assertZIO(typeCheck(code))
}

object MorphirSpec:
  final case class TestContext(testFilePath: os.Path):
    lazy val testDir:os.Path =
      def isTestDir(path:os.Path):Boolean = path.lastOpt match
        case Some(last) => last == "test" && os.isDir(path)
        case None => false
      var curr = testFilePath
      while( curr != os.root && !isTestDir(curr))
        curr = curr / os.up
      if curr == os.root then throw new Exception("Could not find test directory")
      else curr
    lazy val testResourcesDir:os.Path = testDir / "resources"
  end TestContext
  object TestContext:
    def apply(path:String) = new TestContext(os.Path(path))