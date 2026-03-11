package morphir.ir

import kyo.Chunk
import zio.test.*

object PathTests extends ZIOSpecDefault:
  def spec = suite("PathTests")(
    suite("fromList / toList")(
      test("round-trip") {
        val names = List(Name.fromList(List("foo", "bar")), Name.fromList(List("baz")))
        val path = Path.fromList(names)
        assertTrue(path.toList == names)
      }
    ),
    suite("fromString (morphir-elm parity)")(
      test("fooBar.Baz -> [fooBar, baz]") {
        val path = Path.fromString("fooBar.Baz")
        val names = path.toList
        assertTrue(names.size == 2)
        assertTrue(names(0).toList == List("foo", "bar"))
        assertTrue(names(1).toList == List("baz"))
      },
      test("foo bar/baz -> [foo bar, baz]") {
        val path = Path.fromString("foo bar/baz")
        val names = path.toList
        assertTrue(names.size == 2)
        assertTrue(names(0).toList == List("foo", "bar"))
        assertTrue(names(1).toList == List("baz"))
      }
    ),
    suite("format (morphir-elm toString)")(
      test("toTitleCase with . separator") {
        val path = Path.fromList(
          List(Name.fromList(List("foo", "bar")), Name.fromList(List("baz")))
        )
        assertTrue(path.format(_.toTitleCase, ".") == "FooBar.Baz")
      },
      test("toSnakeCase with / separator") {
        val path = Path.fromList(
          List(Name.fromList(List("foo", "bar")), Name.fromList(List("baz")))
        )
        assertTrue(path.format(_.toSnakeCase, "/") == "foo_bar/baz")
      }
    ),
    suite("toCanonicalString (v4)")(
      test("names joined by /") {
        val path = Path.fromList(
          List(Name.fromList(List("morphir")), Name.fromList(List("s", "d", "k")))
        )
        assertTrue(path.toCanonicalString == "morphir/s-d-k")
      },
      test("v4 acronym format") {
        val path = Path.fromList(
          List(Name.fromString("valueInUSD"), Name.fromList(List("baz")))
        )
        assertTrue(path.toCanonicalString == "value-in-(usd)/baz")
      }
    ),
    suite("isPrefixOf (morphir-elm parity)")(
      test("[[foo],[bar]] [[foo]] == True") {
        val path = Path.fromList(List(Name.fromList(List("foo")), Name.fromList(List("bar"))))
        val prefix = Path.fromList(List(Name.fromList(List("foo"))))
        assertTrue(path.isPrefixOf(prefix))
      },
      test("[[foo]] [[foo],[bar]] == False") {
        val path = Path.fromList(List(Name.fromList(List("foo"))))
        val prefix = Path.fromList(List(Name.fromList(List("foo")), Name.fromList(List("bar"))))
        assertTrue(!path.isPrefixOf(prefix))
      },
      test("[[foo],[bar]] [[foo],[bar]] == True") {
        val path = Path.fromList(List(Name.fromList(List("foo")), Name.fromList(List("bar"))))
        val prefix = Path.fromList(List(Name.fromList(List("foo")), Name.fromList(List("bar"))))
        assertTrue(path.isPrefixOf(prefix))
      },
      test("empty prefix is prefix of any path") {
        val path = Path.fromList(List(Name.fromList(List("foo")), Name.fromList(List("bar"))))
        val prefix = Path.fromList(Nil)
        assertTrue(path.isPrefixOf(prefix))
      }
    )
  )
