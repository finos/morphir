package morphir.ir
import zio.test.*
import Name.Token

object NameTests extends ZIOSpecDefault:
  def spec = suite("NameTests")(
    suite("fromStringClassic (morphir-elm fromString parity)")(
      test("fooBar_baz 123 -> [foo, bar, baz, 123] (doc + Elm test)") {
        val name = Name.fromStringClassic("fooBar_baz 123")
        assertTrue(name.toList == List("foo", "bar", "baz", "123"))
        assertTrue(name == Name.fromList(List("foo", "bar", "baz", "123")))
      },
      test("valueInUSD -> [value, in, u, s, d] (doc + Elm test)") {
        val name = Name.fromStringClassic("valueInUSD")
        val expected = List("value", "in", "u", "s", "d")
        assertTrue(name.toList == expected, name == Name.fromList(expected))
        assertTrue(name.tokens.toSeq.forall(_.isWord))
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
    suite("fromString (v4)")(
      test("valueInUSD -> value, in, USD (Word, Word, Acronym)") {
        val name = Name.fromString("valueInUSD")
        val tokens = name.tokens.toSeq
        assertTrue(
          tokens.size == 3,
          Token.value(tokens(0)) == "value",
          Token.value(tokens(1)) == "in",
          Token.value(tokens(2)) == "USD",
          tokens(0).isWord,
          tokens(1).isWord,
          tokens(2).isAcronym
        )
      },
      test("canonical input preserves explicit acronym distinction") {
        val acronymName = Name.fromString("value-in-(usd)")
        val wordName = Name.fromString("value-in-usd")
        val acronymTokens = acronymName.tokens.toSeq
        val wordTokens = wordName.tokens.toSeq
        assertTrue(
          acronymTokens.size == 3,
          Token.value(acronymTokens(2)) == "USD",
          acronymTokens(2).isAcronym,
          wordTokens.size == 3,
          Token.value(wordTokens(2)) == "usd",
          wordTokens(2).isWord
        )
      },
      test("fold returns correct branch for Word and Acronym") {
        val name = Name.fromString("valueInUSD")
        val tokens = name.tokens.toSeq
        val wordResult  = tokens(0).fold(s => s"word:$s", s => s"acronym:$s")
        val acronymResult = tokens(2).fold(s => s"word:$s", s => s"acronym:$s")
        assertTrue(wordResult == "word:value", acronymResult == "acronym:USD")
      }
    ),
    suite("Token.value")(
      test("returns underlying string for Word and Acronym") {
        val name = Name.fromString("valueInUSD")
        val values = name.tokens.toSeq.map(Token.value)
        assertTrue(values == Seq("value", "in", "USD"))
      }
    ),
    suite("toCanonicalString")(
      test("joins tokens with hyphen, parenthesizes acronyms") {
        val name = Name.fromString("valueInUSD")
        assertTrue(name.toCanonicalString == "value-in-(usd)")
      },
      test("classic name canonical form (all words)") {
        val name = Name.fromStringClassic("valueInUSD")
        assertTrue(name.toCanonicalString == "value-in-u-s-d")
      }
    ),
    suite("Name.fold")(
      test("fromStringClassic yields ClassicName branch") {
        val name = Name.fromStringClassic("fooBar")
        val tag = Name.fold(name)(
          _ => "classic",
          _ => "canonical"
        )
        assertTrue(tag == "classic")
      },
      test("fromString yields CanonicalName branch") {
        val name = Name.fromString("valueInUSD")
        val tag = Name.fold(name)(
          _ => "classic",
          _ => "canonical"
        )
        assertTrue(tag == "canonical")
      },
      test("classicName returns ClassicName") {
        val c = Name.classicName("fooBar")
        val tag = Name.fold(c: Name)(_ => "classic", _ => "canonical")
        assertTrue(tag == "classic", c.toCanonicalString == "foo-bar")
      }
    ),
    suite("morphir-elm-aligned API")(
      test("toList") {
        val name = Name.fromStringClassic("valueInUSD")
        assertTrue(name.toList == List("value", "in", "u", "s", "d"))
      },
      test("fromList round-trip") {
        val words = List("value", "in", "u", "s", "d")
        val name = Name.fromList(words)
        assertTrue(name.toList == words)
      },
      test("toTitleCase [value,in,u,s,d] -> ValueInUSD (doc + Elm)") {
        val name = Name.fromList(List("value", "in", "u", "s", "d"))
        assertTrue(name.toTitleCase == "ValueInUSD")
      },
      test("toTitleCase [foo,bar,baz,123] -> FooBarBaz123 (Elm test)") {
        val name = Name.fromList(List("foo", "bar", "baz", "123"))
        assertTrue(name.toTitleCase == "FooBarBaz123")
      },
      test("toCamelCase [value,in,u,s,d] -> valueInUSD (doc + Elm)") {
        val name = Name.fromList(List("value", "in", "u", "s", "d"))
        assertTrue(name.toCamelCase == "valueInUSD")
      },
      test("toCamelCase [foo,bar,baz,123] -> fooBarBaz123 (Elm test)") {
        val name = Name.fromList(List("foo", "bar", "baz", "123"))
        assertTrue(name.toCamelCase == "fooBarBaz123")
      },
      test("toSnakeCase [value,in,u,s,d] -> value_in_USD (doc + Elm)") {
        val name = Name.fromList(List("value", "in", "u", "s", "d"))
        assertTrue(name.toSnakeCase == "value_in_USD")
      },
      test("toSnakeCase [foo,bar,baz,123] -> foo_bar_baz_123 (Elm test)") {
        val name = Name.fromList(List("foo", "bar", "baz", "123"))
        assertTrue(name.toSnakeCase == "foo_bar_baz_123")
      },
      test("toHumanWords [value,in,u,s,d] -> [value,in,USD] (doc + Elm)") {
        val name = Name.fromList(List("value", "in", "u", "s", "d"))
        assertTrue(name.toHumanWords == List("value", "in", "USD"))
      },
      test("toHumanWords [foo,bar,baz,123] unchanged (Elm test)") {
        val name = Name.fromList(List("foo", "bar", "baz", "123"))
        assertTrue(name.toHumanWords == List("foo", "bar", "baz", "123"))
      },
      test("toHumanWords single letter word stays as is (Elm edge case)") {
        val name = Name.fromList(List("x"))
        assertTrue(name.toHumanWords == List("x"))
      },
      test("toHumanWordsTitle [value,in,u,s,d] -> [Value,in,USD] (doc)") {
        val name = Name.fromList(List("value", "in", "u", "s", "d"))
        assertTrue(name.toHumanWordsTitle == List("Value", "in", "USD"))
      },
      test("empty name: toList/toTitleCase/toCamelCase/toSnakeCase (Elm edge cases)") {
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
