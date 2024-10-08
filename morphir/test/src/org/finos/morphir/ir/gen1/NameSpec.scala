package org.finos.morphir.ir.gen1

import org.finos.morphir.ir.gen1.naming.*
import org.finos.morphir.testing.MorphirSpecDefault
import zio.test.*

object NameSpec extends MorphirSpecDefault {
  def spec = suite("Name")(
    suite("Create a Name from a string and check that:")(
      suite("Name should be creatable from a single word that:")(
        test("Starts with a capital letter") {
          assertTrue(Name.fromString("Marco") == Name("marco"))
        },
        test("Is all lowercase") {
          assertTrue(Name.fromString("polo") == Name("polo"))
        }
      ),
      suite("Name should be creatable from compound words that:")(
        test("Are formed from a snake case word") {
          assertTrue(Name.fromString("super_mario_world") == Name("super", "mario", "world"))
        },
        test("Contain many kinds of word delimiters") {
          assertTrue(Name.fromString("fooBar_baz 123") == Name("foo", "bar", "baz", "123"))
        },
        test("Are formed from a camel-cased string") {
          assertTrue(Name.fromString("valueInUSD") == Name("value", "in", "u", "s", "d"))
        },
        test("Are formed from a title-cased string") {
          assertTrue(
            Name.fromString("ValueInUSD") == Name("value", "in", "u", "s", "d"),
            Name.fromString("ValueInJPY") == Name("value", "in", "j", "p", "y")
          )
        },
        test("Have a number in the middle") {
          assertTrue(Name.fromString("Nintendo64VideoGameSystem") == Name("nintendo", "64", "video", "game", "system"))
        },
        test("Are complete and utter nonsense") {
          assertTrue(Name.fromString("_-%") == Name.empty)
        }
      ),
      test("It splits the name as expected") {
        // "fooBar","blahBlah" => ["foo","bar","blah","blah"]
        // "fooBar","blahBlah" => ["fooBar","blahBlah"]
        assertTrue(
          Name.fromString("fooBar").value == List("foo", "bar")
        )
      }
    ),
    suite("Name should be convertible to a title-case string:")(
      test("When the name was originally constructed from a snake-case string") {
        val sut = Name.fromString("snake_case_input")
        assertTrue(Name.toTitleCase(sut) == "SnakeCaseInput")
      },
      test(
        "When the name was originally constructed from a camel-case string"
      ) {
        val sut = Name.fromString("camelCaseInput")
        assertTrue(Name.toTitleCase(sut) == "CamelCaseInput")
      }
    ),
    suite("Name should be convertible to a camel-case string:")(
      test(
        "When the name was originally constructed from a snake-case string"
      ) {
        val sut = Name.fromString("snake_case_input")
        assertTrue(Name.toCamelCase(sut) == "snakeCaseInput")
      },
      test(
        "When the name was originally constructed from a camel-case string"
      ) {
        val sut = Name.fromString("camelCaseInput")
        assertTrue(Name.toCamelCase(sut) == "camelCaseInput")
      }
    ),
    suite("Name should be convertible to snake-case")(
      test("When given a name constructed from a list of words") {
        val input = Name.fromList(List("foo", "bar", "baz", "123"))
        assertTrue(Name.toSnakeCase(input) == "foo_bar_baz_123")
      },
      test("When the name has parts of an abbreviation") {
        val name = Name.fromList(List("value", "in", "u", "s", "d"))
        assertTrue(Name.toSnakeCase(name) == "value_in_USD")
      }
    ),
    suite("Name should be convertible to kebab-case")(
      test("When given a name constructed from a list of words") {
        val input = Name.fromList(List("foo", "bar", "baz", "123"))
        assertTrue(Name.toKebabCase(input) == "foo-bar-baz-123")
      },
      test("When the name has parts of an abbreviation") {
        val name = Name.fromList(List("value", "in", "u", "s", "d"))
        assertTrue(Name.toKebabCase(name) == "value-in-USD")
      }
    ),
    suite("Name toHumanWords should provide a list of words from a Name")(
      test("When the name is from a camelCase string") {
        val sut = Name.fromString("ValueInUSD")
        assertTrue(Name.toHumanWords(sut) == List("value", "in", "USD"))
      }
    ),
    suite("fromIterable")(
      test("Splits provided names as expected") {
        assertTrue(Name.fromIterable(List("fooBar", "fizzBuzz")) == Name("foo", "bar", "fizz", "buzz"))
      }
    ),
    suite("Misc")(
      test("Name.render") {
        assertTrue(
          Name.fromString("fooBar").renderToString == "[foo,bar]",
          Name.fromString("a").renderToString == "[a]"
        )
      }
    ),
    suite("VariableName")(
      test("When calling VariableName.unapply") {
        val sut          = Name.fromString("InspectorGadget")
        val variableName = Name.VariableName.unapply(sut)
        assertTrue(variableName == Some("inspectorGadget"))
      },
      test("When using as an extractor") {
        val sut = Name.fromString("IronMan")
        val actual = sut match {
          case Name.VariableName(variableName) => variableName
          case _                               => "not a variable name"
        }
        assertTrue(actual == "ironMan")
      }
    ),
    suite("String Interpolation")(
      test("When using the n interpolator on a plain string") {
        assertTrue(n"Foo" == Name.fromString("Foo"), n"Foo" == Name.fromList(List("foo")))
      },
      test("When using the n interpolator with an int value") {
        val n = 42
        assertTrue(n"Foo$n" == Name.fromString("Foo42"), n"Foo$n" == Name.fromList(List("foo", "42")))
      }
    ),
    suite("Operators")(
      suite("+")(
        test("It should support adding a String to a Name") {
          assertTrue(Name.fromString("Foo") + "bar" == Name.fromString("FooBar"))
        }
      )
    )
  )
}
