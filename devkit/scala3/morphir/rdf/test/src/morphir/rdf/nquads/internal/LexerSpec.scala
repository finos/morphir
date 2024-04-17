package morphir.rdf.nquads.internal

import zio.test.*
import parsley.Success

object LexerSpec extends ZIOSpecDefault {
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
      }
    )
  )
}
