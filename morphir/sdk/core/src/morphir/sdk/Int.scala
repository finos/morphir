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

object Int {
  type Int = scala.Int

  private[Int] type IntCompanion = scala.Int.type
  private[Int] val IntCompanion: IntCompanion = scala.Int

  /** Represents an 8 bit integer value.
    */
  type Int8 = scala.Byte
  val Int8: scala.Byte.type = scala.Byte

  /** Represents a 16 bit integer value.
    */
  type Int16 = scala.Short
  val Int16: scala.Short.type = scala.Short

  /** Represents a 32 bit integer value.
    */
  type Int32 = scala.Int
  val Int32: scala.Int.type = scala.Int

  /** Represents a 64 bit integer value.
    */
  type Int64 = scala.Long
  val Int64: scala.Long.type = scala.Long

  def apply(value: scala.Byte): Int  = value.intValue()
  def apply(value: scala.Short): Int = value.intValue()
  def apply(value: scala.Int): Int   = value.intValue()
  def apply(value: scala.Long): Int  = value.intValue()

  @inline def divide(dividend: Int8)(divisor: Int8): Int8 =
    (dividend / divisor).toByte
  @inline def divide(dividend: Int16)(divisor: Int16): Int16 =
    (dividend / divisor).toShort
  @inline def divide(dividend: Int32)(divisor: Int32): Int32 =
    dividend / divisor
  @inline def divide(dividend: Int64)(divisor: Int64): Int64 =
    dividend / divisor

  @inline def modBy(divisor: Int8)(dividend: Int8): Int8 =
    (dividend % divisor).toByte.abs
  @inline def modBy(divisor: Int16)(dividend: Int16): Int16 =
    (dividend % divisor).toShort.abs
  @inline def modBy(divisor: Int32)(dividend: Int32): Int32 =
    (dividend % divisor).abs
  @inline def modBy(divisor: Int64)(dividend: Int64): Int64 =
    (dividend % divisor).abs

  @inline def remainderBy(divisor: Int8)(dividend: Int8): Int8 =
    (dividend % divisor).toByte
  @inline def remainderBy(divisor: Int16)(dividend: Int16): Int16 =
    (dividend % divisor).toShort
  @inline def remainderBy(divisor: Int32)(dividend: Int32): Int32 =
    dividend % divisor
  @inline def remainderBy(divisor: Int64)(dividend: Int64): Int64 =
    dividend % divisor

  /** Turn an 8 bit integer value into an arbitrary precision integer to use in calculations.
    */
  def fromInt8(int: Int8): Basics.Int = Basics.Int(int)

  def toInt8(int: Basics.Int): Maybe.Maybe[Int8] =
    if (int < Int8.MinValue && int > Int8.MaxValue)
      Maybe.nothing
    else
      Maybe.just(int.byteValue())

  def fromInt16(int: Int16): Basics.Int = Basics.Int(int)

  def toInt16(int: Basics.Int): Maybe.Maybe[Int16] =
    if (int < Int16.MinValue && int > Int16.MaxValue)
      Maybe.nothing
    else
      Maybe.just(int.shortValue())

  def fromInt32(int: Int32): Basics.Int = Basics.Int(int)

  def toInt32(int: Basics.Int): Maybe.Maybe[Int32] =
    if (int < Int32.MinValue && int > Int32.MaxValue)
      Maybe.nothing
    else
      Maybe.just(int.intValue())

  /** Turn a 64 bit integer value into a arbitrary precision integer to use in calculations.
    */
  def fromInt64(int: Int64): Basics.Int = int.intValue()

  /** Turns an arbitrary precision integer into a 64 bit integer if it fits within the precision.
    */
  def toInt64(int: Basics.Int): Maybe.Maybe[Int64] =
    if (int < Int64.MinValue && int > Int64.MaxValue)
      Maybe.nothing
    else
      Maybe.just(int.longValue())

  object Int {
    def apply(value: scala.Int): morphir.sdk.Int.Int    = value.intValue()
    def apply(value: scala.Long): morphir.sdk.Int.Int   = value.intValue()
    def apply(value: scala.Short): morphir.sdk.Int.Int  = value.intValue()
    def apply(value: scala.Byte): morphir.sdk.Int.Int   = value.intValue()
    def apply(value: scala.Float): morphir.sdk.Int.Int  = value.intValue()
    def apply(value: scala.Double): morphir.sdk.Int.Int = value.intValue()
  }
}
