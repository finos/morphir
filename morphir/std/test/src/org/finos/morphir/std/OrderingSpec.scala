package org.finos.morphir
package std
import org.finos.morphir.testing.*

import zio.test.*
import zio.test.Assertion.*

object OrderingSpec extends MorphirSpecDefault:
  def spec = suite("OrderingSpec")(
    test("A morphir std Ordering should be available when a Scala Ordering is in scope") {
      val ordering = summon[Ordering[Int]]
      assertTrue(ordering.compare(1, 2) == Order.LessThan) &&
      assertTrue(ordering.compare(2, 1) == Order.GreaterThan) &&
      assertTrue(ordering.compare(1, 1) == Order.EqualTo) &&
      assertTrue(Ordering[Char].compare('a', 'b') == Order.LessThan) &&
      assertTrue(Ordering[Char].compare('b', 'a') == Order.GreaterThan) &&
      assertTrue(Ordering[Char].compare('a', 'a') == Order.EqualTo)
    }
  )
