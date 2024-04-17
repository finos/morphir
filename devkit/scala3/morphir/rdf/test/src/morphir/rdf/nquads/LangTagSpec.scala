package morphir.rdf.nquads

import zio.test.*

object LangTagSpec extends ZIOSpecDefault:
  def spec = suite("LangTagSpec")(
    test("A langtag should be creatable from a string without the '@' symbol") {
        val actual = LangTag("en")
        val expected = LangTag.unsafeMake("en")
        assertTrue(actual == expected)
    }
  )
end LangTagSpec