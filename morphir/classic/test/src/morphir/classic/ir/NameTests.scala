package morphir.classic.ir
import zio.test.*

object NameTests extends ZIOSpecDefault:
  def spec = suite("NameTests")(
    suite("fromStringClassic (morphir-elm fromString parity)")(
      test("fooBar_baz 123 -> [foo, bar, baz, 123] (doc + Elm test)") {
        val name = Name.fromStringClassic("fooBar_baz 123")
        assertTrue(name.toList == List("foo", "bar", "baz", "123"))
      },
      test("valueInUSD -> [value, in, u, s, d] (doc + Elm test)") {
        val name = Name.fromStringClassic("valueInUSD")
        assertTrue(name.toList == List("value", "in", "u", "s", "d"))
      },
      test("ValueInUSD -> [value, in, u, s, d] (doc example)") {
        val name = Name.fromStringClassic("ValueInUSD")
        assertTrue(name.toList == List("value", "in", "u", "s", "d"))
      },
      test("value_in_USD -> [value, in, u, s, d] (doc + Elm test)") {
        val name = Name.fromStringClassic("value_in_USD")
        assertTrue(name.toList == List("value", "in", "u", "s", "d"))
      },
      test("_-% -> [] (doc example)") {
        val name = Name.fromStringClassic("_-%")
        assertTrue(name.toList == Nil)
      },
      test("_-% with trailing space -> [] (Elm test)") {
        val name = Name.fromStringClassic("_-% ")
        assertTrue(name.toList == Nil)
      }
    ),
    suite("apply / fromString")(
      test("apply delegates to classic parsing") {
        val name = Name("valueInUSD")
        assertTrue(name.toList == List("value", "in", "u", "s", "d"))
      },
      test("fromString delegates to classic parsing") {
        val name = Name.fromString("fooBar_baz 123")
        assertTrue(name.toList == List("foo", "bar", "baz", "123"))
      }
    ),
    suite("fromList / toList round-trip")(
      test("[foo, bar, baz, 123] round-trips") {
        val words = List("foo", "bar", "baz", "123")
        assertTrue(Name.fromList(words).toList == words)
      },
      test("[value, in, u, s, d] round-trips") {
        val words = List("value", "in", "u", "s", "d")
        assertTrue(Name.fromList(words).toList == words)
      }
    ),
    suite("toTitleCase (morphir-elm toTitleCase)")(
      test("[foo, bar, baz, 123] -> FooBarBaz123 (Elm test)") {
        val name = Name.fromList(List("foo", "bar", "baz", "123"))
        assertTrue(name.toTitleCase == "FooBarBaz123")
      },
      test("[value, in, u, s, d] -> ValueInUSD (doc + Elm test)") {
        val name = Name.fromList(List("value", "in", "u", "s", "d"))
        assertTrue(name.toTitleCase == "ValueInUSD")
      }
    ),
    suite("toCamelCase (morphir-elm toCamelCase)")(
      test("[foo, bar, baz, 123] -> fooBarBaz123 (Elm test)") {
        val name = Name.fromList(List("foo", "bar", "baz", "123"))
        assertTrue(name.toCamelCase == "fooBarBaz123")
      },
      test("[value, in, u, s, d] -> valueInUSD (doc + Elm test)") {
        val name = Name.fromList(List("value", "in", "u", "s", "d"))
        assertTrue(name.toCamelCase == "valueInUSD")
      }
    ),
    suite("toSnakeCase (morphir-elm toSnakeCase)")(
      test("[foo, bar, baz, 123] -> foo_bar_baz_123 (Elm test)") {
        val name = Name.fromList(List("foo", "bar", "baz", "123"))
        assertTrue(name.toSnakeCase == "foo_bar_baz_123")
      },
      test("[value, in, u, s, d] -> value_in_USD (doc + Elm test)") {
        val name = Name.fromList(List("value", "in", "u", "s", "d"))
        assertTrue(name.toSnakeCase == "value_in_USD")
      }
    ),
    suite("toHumanWords (morphir-elm toHumanWords)")(
      test("[value, in, u, s, d] -> [value, in, USD] (doc + Elm test)") {
        val name = Name.fromList(List("value", "in", "u", "s", "d"))
        assertTrue(name.toHumanWords == List("value", "in", "USD"))
      },
      test("[foo, bar, baz, 123] unchanged (Elm test)") {
        val name = Name.fromList(List("foo", "bar", "baz", "123"))
        assertTrue(name.toHumanWords == List("foo", "bar", "baz", "123"))
      },
      test("single letter word stays as is (Elm edge case)") {
        val name = Name.fromList(List("x"))
        assertTrue(name.toHumanWords == List("x"))
      }
    ),
    suite("toHumanWordsTitle (morphir-elm toHumanWordsTitle)")(
      test("[value, in, u, s, d] -> [Value, in, USD] (doc)") {
        val name = Name.fromList(List("value", "in", "u", "s", "d"))
        assertTrue(name.toHumanWordsTitle == List("Value", "in", "USD"))
      },
      test("[foo, bar, baz, 123] -> [Foo, bar, baz, 123]") {
        val name = Name.fromList(List("foo", "bar", "baz", "123"))
        assertTrue(name.toHumanWordsTitle == List("Foo", "bar", "baz", "123"))
      }
    ),
    suite("toCanonicalString")(
      test("classic name canonical form (all words)") {
        val name = Name.fromStringClassic("valueInUSD")
        assertTrue(name.toCanonicalString == "value-in-u-s-d")
      },
      test("fromList canonical form") {
        val name = Name.fromList(List("foo", "bar"))
        assertTrue(name.toCanonicalString == "foo-bar")
      }
    ),
    suite("empty name edge cases")(
      test("fromList(Nil) -> all outputs empty") {
        val name = Name.fromList(Nil)
        assertTrue(
          name.toList == Nil,
          name.toTitleCase == "",
          name.toCamelCase == "",
          name.toSnakeCase == "",
          name.toHumanWords == Nil,
          name.toHumanWordsTitle == Nil
        )
      }
    )
  )
