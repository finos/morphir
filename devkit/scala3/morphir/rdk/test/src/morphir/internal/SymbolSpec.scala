package morphir.runtime.internal
import morphir.rdk.*
import morphir.cdk.IntoName.given
import zio.test.*

object SymbolSpec extends ZIOSpecDefault {

  def spec = suite("SymbolSpec")(
    suite("Variable")(
      test("Two variables with the same name and type should be equal") {
        val symbol1: Symbol[Int] = "x".intoVariable
        val symbol2 = "x".intoVariable[Int]
        assertTrue(symbol1 == symbol2)
      },
      test("Two variables with different names should not be equal") {
        val symbol1 = "x".intoVariable[Int]
        val symbol2 = "y".intoVariable[Int]
        assertTrue(symbol1 != symbol2)
      },
      test("Two variables with different types should not be equal") {
        val symbol1 = Symbol.named("x").asVariableOf[Int]
        val symbol2 = Symbol.named("x").asVariableOf[String]
        assertTrue(symbol1 != symbol2)
      }
    )
  )

}
