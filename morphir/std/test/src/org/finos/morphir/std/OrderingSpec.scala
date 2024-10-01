package org.finos.morphir
package std
import utest.* 

object OrderingSpec extends TestSuite:
  val tests = Tests {
    test("Ordering"){
      def checkOrdering[A](left: A, right: A, expected:Order)(using ord: Ordering[A]) =
        ord.compare(left, right) ==> expected 

      test { checkOrdering(1, 2, Order.LessThan) }
      test { checkOrdering(2, 1, Order.GreaterThan) }
      test { checkOrdering(1, 1, Order.EqualTo) }
      test { checkOrdering('a', 'b', Order.LessThan) }
      test { checkOrdering('b', 'a', Order.GreaterThan) }
      test { checkOrdering('a', 'a', Order.EqualTo) }
    }
  }

