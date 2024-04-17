package morphir.rdf.nquads.internal
import zio.test.*

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
        val result = lexer.LANGTAG.parse(langtag)
        assertTrue(result.isSuccess)
      },
      test("Should parse a complex LANGTAG") {
        val langtag = "@en-GB"
        val result = lexer.LANGTAG.parse(langtag)
        assertTrue(result.isSuccess)
      },
      test("Should parse a very complex LANGTAG") {
        val langtag = "@en-GB01-oxendict-1997"
        val result = lexer.LANGTAG.parse(langtag)
        assertTrue(result.isSuccess)
      }
    )
  )
}
