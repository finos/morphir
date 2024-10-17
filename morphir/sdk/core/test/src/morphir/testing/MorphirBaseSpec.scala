package morphir.testing

import zio.internal.stacktracer.SourceLocation
import zio.{ test => _, _ }
import zio.test._

import scala.annotation.nowarn

abstract class MorphirBaseSpec extends ZIOSpecDefault {
  override def aspects = Chunk(TestAspect.timeout(90.seconds))

  def assertEquals[Actual, Expected <: Actual](actual: Actual, expected: Expected)(implicit
    @nowarn sourceLocation: SourceLocation
  ): TestResult =
    assertTrue(actual == expected)
}
