package morphir.rdf.nquads.internal

import zio.test.*
import zio.test.TestAspect.{ignore, tag}
import parsley.Success
import parsley.Failure
import scala.util.matching.Regex

object LexerSpec extends ZIOSpecDefault:
  def spec = suite("LexerSpec")(
    suite("UCHAR")(
      test("Should parse a simple UCHAR (4)") {
        val uchar = "\\u0041"
        val result = lexer.UCHAR.parse(uchar)
        assertTrue(result.isSuccess)
      }
    ),
    suite("LANGTAG")(
      test("Should parse a simple LANGTAG") {
        val langtag = "@en"
        val actual = lexer.LANGTAG.parse(langtag)
        val expected = Success("en")
        assertTrue(actual == expected)
      },
      test("Should parse a complex LANGTAG") {
        val langtag = "@en-GB"
        val actual = lexer.LANGTAG.parse(langtag)
        val expected = Success("en-GB")
        assertTrue(actual == expected)
      },
      test("Should parse a very complex LANGTAG") {
        val langtag = "@en-GB01-oxendict-1997"
        val actual = lexer.LANGTAG.parse(langtag)
        val expected = Success("en-GB01-oxendict-1997")
        assertTrue(actual == expected)
      }
    ),
    suite("IRIREF")(
      test("Should parse a simple IRIREF") {
        val iriRef = "<http://example.org>"
        val actual = lexer.IRIREF.parse(iriRef)
        val expected = Success("http://example.org")
        assertTrue(actual == expected)
      },
      test("Should parse a complex IRIREF") {
        val iriRef = "<http://example.org/ontology#Person>"
        val actual = lexer.IRIREF.parse(iriRef)
        val expected = Success("http://example.org/ontology#Person")
        assertTrue(actual == expected)
      },
      test("Should fail to parse an IRIREF containing invalid characters") {
        val iriRef = "<http://example.org/ontology#Person|Place>"
        val actual = lexer.IRIREF.parse(iriRef): @unchecked
        assertTrue(actual.isFailure) && assertTrue(
          checks.FailureAt.unapply(actual).contains((1, 36))
        )
      }
    ),
    suite("STRING_LITERAL_QUOTE")(
      test("Should parse a simple STRING_LITERAL_QUOTE") {
        val stringLiteralQuote = "\"Hello, World!\""
        val actual = lexer.STRING_LITERAL_QUOTE.parse(stringLiteralQuote)
        val expected = Success("Hello, World!")
        assertTrue(actual == expected)
      },
      test("Should parse a complex STRING_LITERAL_QUOTE") {
        val stringLiteralQuote = """"Hello, \u0041!""""
        val actual = lexer.STRING_LITERAL_QUOTE.parse(stringLiteralQuote)
        val expected = Success("""Hello, \u0041!""")
        assertTrue(actual == expected)
      },
      test(
        "Should fail to parse a STRING_LITERAL_QUOTE containing invalid characters"
      ) {
        val stringLiteralQuote = "\"Hello, \\u0041!\\u0041!\""
        val actual =
          lexer.STRING_LITERAL_QUOTE.parse(stringLiteralQuote): @unchecked
        assertTrue(actual.isFailure) && assertTrue(
          checks.FailureAt.unapply(actual).contains((1, 18))
        )
      } @@ ignore @@ tag("Need to create proper test case")
    )
  )

  object checks:
    object FailureAt:
      // A regular expression that extracts the line and column from a string that looks like (line 1, column 20):
      val positionPattern: Regex =
        """^\(line (\d+), column (\d+)\):""".r.unanchored

      def unapply[A](result: parsley.Result[String, A]): Option[(Int, Int)] =
        result match
          case parsley.Failure[String](positionPattern(line, column)) =>
            Some((line.toInt, column.toInt))
          case _ => None
