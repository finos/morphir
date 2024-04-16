package morphir.rdf.nquads
import zio.test.*

object NQuadsParsingSpec extends ZIOSpecDefault {
  def spec = suite("NQuadsParsingSpec")(
    test("Should parse a simple NQuad") {
      val nquad =
        "<http://example.org/subject> <http://example.org/predicate> <http://example.org/object> <http://example.org/graph> ."
      given parser: NQuadsParser = NQuadsParser(NQuadsParser.defaultSettings)
      val result = NQuadsParser.parse(nquad)
      assertTrue(result.isValid)
    }
  )
}
