package morphir.sdk

import UUID.WrongFormat
import memeid4s.{UUID => MUUID}
import morphir.testing.MorphirBaseSpec
import zio.test._
import zio.test.Assertion._

object UUIDSpec extends MorphirBaseSpec {
  def spec = suite("UUID Tests")(
    suite("parse Tests")(
      test("Generate UUID from valid String using parse") {
        val namespace = MUUID.V4.random
        val uuid      = UUID.forName("test", namespace)

        assert(UUID.parse(uuid.toString))(isRight(equalTo(uuid)))
        assertTrue(uuid.version == 5)
      },
      test("Return Throwable from invalid String using parse") {
        assert(UUID.parse("0f769c4185a634208b09bb63bce12014"))(
          isLeft(equalTo(WrongFormat("Invalid UUID string: 0f769c4185a634208b09bb63bce12014", null)))
        )
      }
    ),
    suite("fromString Tests")(
      test("Generate UUID from valid String using fromString") {
        val namespace = MUUID.V4.random
        val uuid      = UUID.forName("test", namespace)

        assert(UUID.fromString(uuid.toString))(isSome(equalTo(uuid)))
        assertTrue(uuid.version == 5)
      },
      test("Return None from invalid String") {
        assert(UUID.fromString("0f769c4185a634208b09bb63bce12014"))(isNone)
      }
    ),
    test("UUID from msb and lsb") {
      check(Gen.long) { msb =>
        assertEquals(UUID.from(msb, 0xc000000000000000L), MUUID.from(msb, 0xc000000000000000L))
      }
    },
    test("Nil check returns true for Nil String") {
      assertTrue(UUID.isNilString("00000000-0000-0000-0000-000000000000"))
    },
    test("Nil check returns false for non Nil String") {
      assertTrue(!UUID.isNilString("10000000-0000-0000-0000-000000000000"))
    },
    suite("V5 UUID")(
      test("Generate same V5 UUID for same namespace and name") {
        val namespace = MUUID.V4.random
        val name      = "Test Name!"
        val u1        = UUID.forName(name, namespace)
        val u2        = UUID.forName(name, namespace)
        assertEquals(u1, u2)
      },
      test("Generate unique V5 UUID for unique namespace") {
        val namespace1 = MUUID.V4.random
        val namespace2 = MUUID.V4.random
        val name       = "Test Name!"
        val u1         = UUID.forName(name, namespace1)
        val u2         = UUID.forName(name, namespace2)
        assertTrue(u1 != u2)
      },
      test("Generate unique V5 UUID for unique names") {
        val namespace = MUUID.V4.random
        val name1     = "Test Name!"
        val name2     = "Test Name 2!"
        val u1        = UUID.forName(name1, namespace)
        val u2        = UUID.forName(name2, namespace)
        assertTrue(u1 != u2)
      }
    )
  )

}
