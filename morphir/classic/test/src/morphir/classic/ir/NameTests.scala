package morphir.classic.ir
import zio.test.* 

object NameTests extends ZIOSpecDefault:
  def spec = suite("NameTests")(
    suite("fromStringClassic")(
      test("parses like morphir-elm baseline") {
        val name = Name.fromStringClassic("valueInUSD")
        assertTrue(name.toList == List("value", "in", "u", "s", "d"))
      },
      test("strips non matching chars and lowercases") {
        val name = Name.fromStringClassic("fooBar_baz 123")
        assertTrue(name.toList == List("foo", "bar", "baz", "123"))
      }
    ),
    test("apply delegates to classic parsing") {
      val name = Name("valueInUSD")
      assertTrue(name.toList == List("value", "in", "u", "s", "d"))
    },
    test("canonical output stays classic (no v4 acronym grouping)") {
      val name = Name.fromStringClassic("valueInUSD")
      assertTrue(name.toCanonicalString == "value-in-u-s-d")
    }
  )
