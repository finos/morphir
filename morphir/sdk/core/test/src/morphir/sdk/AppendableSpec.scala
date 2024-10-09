package morphir.sdk

import morphir.testing.MorphirBaseSpec

import zio.test.Assertion._
import zio.test._
import morphir.testing.MorphirBaseSpec

object AppendableSpec extends MorphirBaseSpec {
  def spec = suite("AppendableSpec")(
    suite("Appendable.append spec")(
      test("Appending two strings") {
        val a        = "Hello, "
        val b        = "World!"
        val expected = "Hello, World!"
        assert(morphir.sdk.Basics.append(a)(b))(equalTo(expected))
      },
      test("Appending two lists") {
        val a        = List(1, 2, 3)
        val b        = List(4, 5, 6)
        val expected = List(1, 2, 3, 4, 5, 6)
        assert(morphir.sdk.Basics.append(a)(b))(equalTo(expected))
      },
      test("Appending two sets") {
        val a        = morphir.sdk.Set.Set(1, 2, 3)
        val b        = morphir.sdk.Set.Set(4, 5, 6)
        val expected = morphir.sdk.Set.Set(1, 2, 3, 4, 5, 6)
        assert(morphir.sdk.Basics.append(a)(b))(equalTo(expected))
      },
      test("Appending two iterables") {
        val a        = Iterable(1, 2, 3)
        val b        = Iterable(4, 5, 6)
        val expected = Iterable(1, 2, 3, 4, 5, 6)
        assert(morphir.sdk.Basics.append(a)(b))(equalTo(expected))
      },
      test("Appending two vectors") {
        val a        = Vector(1, 2, 3)
        val b        = Vector(4, 5, 6)
        val expected = Vector(1, 2, 3, 4, 5, 6)
        assert(morphir.sdk.Basics.append(a)(b))(equalTo(expected))
      }
    )
  )
}
