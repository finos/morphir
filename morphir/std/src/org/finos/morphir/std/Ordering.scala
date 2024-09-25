package org.finos.morphir
package std

trait Ordering[A]:
  def compare(x: A, y: A): std.Order
  extension (x: A) def compareTo(y: A): std.Order = compare(x, y)

object Ordering extends LowPriorityOrdering:
  def apply[A](using ord: std.Ordering[A]): std.Ordering[A] = ord
  def compare[A](x: A, y: A)(using ord: Ordering[A]): Order = ord.compare(x, y)

trait LowPriorityOrdering:
  given [A](using sOrdering: scala.Ordering[A]): std.Ordering[A] =
    new Ordering[A]:
      def compare(x: A, y: A): std.Order =
        Order.fromInt(sOrdering.compare(x, y))
