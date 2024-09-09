package org.finos.morphir.trees.ir
import org.finos.morphir.testing.MorphirKyoSpecDefault
import zio.test.*

object TypeSpec extends MorphirKyoSpecDefault {
  def spec = suite("TypeSpec")(
    unitSuite
  )

  def unitSuite = suite("UnitSuite")(
    test("Should be able to create a unit type") {
      val unitType = Type.Unit(Type.Attributes.default)
      val expected = Type.Unit()
      assertTrue(unitType == expected)
    }
  )
}
