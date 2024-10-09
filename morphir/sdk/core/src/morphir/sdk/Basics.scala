/*
Copyright 2020 Morgan Stanley

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
 */

package morphir.sdk

trait Basics {
  def append[A: Appendable](a: A)(b: A): A = Appendable[A].append(a, b)
}

object Basics extends Basics {

  sealed abstract class Order(val value: Int) extends Product with Serializable
  object Order {
    case object LT extends Order(-1)
    case object EQ extends Order(0)
    case object GT extends Order(1)
  }

  val LT: Order = Order.LT
  val EQ: Order = Order.EQ
  val GT: Order = Order.GT

  // Bool
  type Bool = Boolean
  object Bool {
    @inline def apply(value: Boolean): Bool = value
  }
  val True: Bool                          = true
  val False: Bool                         = false
  @inline def not(a: Bool): Bool          = !a
  @inline def and(a: Bool)(b: Bool): Bool = a && b
  @inline def or(a: Bool)(b: Bool): Bool  = a || b
  @inline def xor(a: Bool)(b: Bool): Bool = a ^ b

  // Equality
  @inline def equal[A](a: A)(b: A): Bool    = a == b
  @inline def notEqual[A](a: A)(b: A): Bool = a != b

  // Comparable
  @inline def lessThan[A: Ordering](a: A)(b: A): Bool           = implicitly[Ordering[A]].lt(a, b)
  @inline def lessThanOrEqual[A: Ordering](a: A)(b: A): Bool    = implicitly[Ordering[A]].lteq(a, b)
  @inline def greaterThan[A: Ordering](a: A)(b: A): Bool        = implicitly[Ordering[A]].gt(a, b)
  @inline def greaterThanOrEqual[A: Ordering](a: A)(b: A): Bool = implicitly[Ordering[A]].gteq(a, b)
  @inline def min[A: Ordering](a: A)(b: A): A                   = if (lessThan(a)(b)) a else b
  @inline def max[A: Ordering](a: A)(b: A): A                   = if (greaterThan(a)(b)) a else b

  // Int construction
  type Int = morphir.sdk.Int.Int
  val Int: morphir.sdk.Int.Int.type = morphir.sdk.Int.Int

  // Int functions
  @inline def lessThan(a: Int)(b: Int): Bool           = a < b
  @inline def lessThanOrEqual(a: Int)(b: Int): Bool    = a <= b
  @inline def greaterThan(a: Int)(b: Int): Bool        = a > b
  @inline def greaterThanOrEqual(a: Int)(b: Int): Bool = a >= b
  @inline def min(a: Int)(b: Int): Int                 = a min b
  @inline def max(a: Int)(b: Int): Int                 = a max b
  @inline def add(a: Int)(b: Int): Int                 = a + b
  @inline def subtract(a: Int)(b: Int): Int            = a - b
  @inline def multiply(a: Int)(b: Int): Int            = a * b
  @inline def integerDivide(a: Int)(b: Int): Int       = a / b
  @inline def power(a: Int)(b: Int): Int               = a ^ b
  @inline def modBy(a: Int)(b: Int): Int               = Math.floorMod(a, b)
  @inline def remainderBy(a: Int)(b: Int): Int         = a % b
  @inline def negate(a: Int): Int                      = -a
  @inline def abs(a: Int): Int                         = Math.abs(a)
  @inline def clamp(min: Int)(max: Int)(a: Int): Int =
    if (a < min) min
    else if (a > max) max
    else a

  // Float construction
  type Float = morphir.sdk.Float.Float
  @inline def Float(number: Number): Float =
    number.doubleValue()

  // Float functions
  @inline def lessThan(a: Float)(b: Float): Bool           = a < b
  @inline def lessThanOrEqual(a: Float)(b: Float): Bool    = a <= b
  @inline def greaterThan(a: Float)(b: Float): Bool        = a > b
  @inline def greaterThanOrEqual(a: Float)(b: Float): Bool = a >= b
  @inline def min(a: Float)(b: Float): Float               = a min b
  @inline def max(a: Float)(b: Float): Float               = a max b
  @inline def add(a: Float)(b: Float): Float               = a + b
  @inline def subtract(a: Float)(b: Float): Float          = a - b
  @inline def multiply(a: Float)(b: Float): Float          = a * b
  @inline def divide(a: Float)(b: Float): Float            = a / b
  @inline def power(a: Float)(b: Float): Float             = Math.pow(a, b)
  @inline def toFloat(a: Int): Float                       = a.toDouble
  @inline def round(a: Float): Int =
    a.round.intValue() // TODO: Look at truncation (need to update the SDK to return an Int64 here)
  @inline def floor(a: Float): Int =
    a.floor.intValue // TODO: Look at truncation (need to update the SDK to return an Int64 here)
  @inline def ceiling(a: Float): Int =
    a.ceil.intValue // TODO: Look at truncation (need to update the SDK to return an Int64 here)
  @inline def truncate(a: Float): Int = if (a >= 0) floor(a) else -floor(-a)
  @inline def negate(a: Float): Float = -a
  @inline def abs(a: Float): Float    = Math.abs(a)
  @inline def clamp(min: Float)(max: Float)(a: Float): Float =
    if (a < min) min
    else if (a > max) max
    else a
  @inline def logBase(base: Float)(number: Float): Float =
    divide(scala.math.log(number))(scala.math.log(base))
  @inline def e: Float =
    Math.E
  @inline def isNaN(a: Float): Bool      = a.isNaN
  @inline def isInfinite(a: Float): Bool = a.isInfinite

  type Decimal = morphir.sdk.Decimal.Decimal
  val Decimal: morphir.sdk.Decimal.Decimal.type = morphir.sdk.Decimal.Decimal

  // Utilities
  @inline def identity[A](a: A): A                                = scala.Predef.identity(a)
  @inline def always[A, B](a: A): B => A                          = _ => a
  @inline def composeLeft[A, B, C](g: B => C)(f: A => B): A => C  = a => g(f(a))
  @inline def composeRight[A, B, C](f: A => B)(g: B => C): A => C = a => g(f(a))
  def never[A](nothing: Nothing): A                               = nothing

}
