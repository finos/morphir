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

import morphir.sdk
import morphir.sdk.Int._
import zio.test.Assertion._
import zio.test._

import morphir.testing.MorphirBaseSpec
object IntSpec extends MorphirBaseSpec {
  def spec = suite("IntSpec")(
    suite("Int.divide spec")(
      test("Dividing an Int8 value by an Int8 value") {
        check(Gen.byte, Gen.byte.filter(n => n != 0)) { (x: Int8, y: Int8) =>
          val expected: scala.Int = x / y
          assert(sdk.Int.divide(x)(y).toInt)(equalTo(expected))
        }
      },
      test("Dividing an Int16 value by an Int16 value") {
        check(Gen.short, Gen.short.filter(n => n != 0)) { (x: Int16, y: Int16) =>
          val expected: scala.Int = x / y
          assert(sdk.Int.divide(x)(y).toInt)(equalTo(expected))
        }
      },
      test("Dividing an Int32 value by an Int32 value") {
        check(Gen.int, Gen.int.filter(n => n != 0)) { (x: Int32, y: Int32) =>
          val expected: scala.Int = x / y
          assert(sdk.Int.divide(x)(y))(equalTo(expected))
        }
      },
      test("Dividing an Int64 value by an Int64 value") {
        check(Gen.long, Gen.long.filter(n => n != 0)) { (x: Int64, y: Int64) =>
          val expected: scala.Long = x / y
          assert(sdk.Int.divide(x)(y))(equalTo(expected))
        }
      },
      test("Dividing an Int value by an Int value") {
        check(Gen.long, Gen.long.filter(n => n != 0)) { (x: Int64, y: Int64) =>
          val expected: Long = x / y
          assert(sdk.Int.divide(x)(y))(equalTo(expected))
        }
      }
    ),
    suite("Int.modBy spec")(
      test("Performing ModBy on Int8s") {
        check(Gen.byte.filter(n => n != 0), Gen.byte) { (divisor, dividend) =>
          val expected: scala.Int = (dividend % divisor).abs
          assert(sdk.Int.modBy(divisor)(dividend).toInt)(equalTo(expected))
        }
      },
      test("Performing ModBy on Int16s") {
        check(Gen.short.filter(n => n != 0), Gen.short) { (divisor, dividend) =>
          val expected: scala.Int = (dividend % divisor).abs
          assert(sdk.Int.modBy(divisor)(dividend).toInt)(equalTo(expected))
        }
      },
      test("Performing ModBy on Int32s") {
        check(Gen.int.filter(n => n != 0), Gen.int) { (divisor, dividend) =>
          val expected: scala.Int = (dividend % divisor).abs
          assert(sdk.Int.modBy(divisor)(dividend))(equalTo(expected))
        }
      },
      test("Performing ModBy on Int64s") {
        check(Gen.long.filter(n => n != 0), Gen.long) { (divisor, dividend) =>
          val expected: scala.Long = (dividend % divisor).abs
          assert(sdk.Int.modBy(divisor)(dividend))(equalTo(expected))
        }
      },
      test("Performing ModBy on Ints") {
        check(Gen.long.filter(n => n != 0), Gen.long) { (longDivisor, longDividend) =>
          val divisor       = sdk.Int.fromInt64(longDivisor)
          val dividend      = sdk.Int.fromInt64(longDividend)
          val expected: Int = (dividend % divisor).abs
          assert(sdk.Int.modBy(divisor)(dividend))(equalTo(expected))
        }
      }
    ),
    suite("Int.remainderBy spec")(
      test("Performing remainderBy on Int8s") {
        check(Gen.byte.filter(n => n != 0), Gen.byte) { (divisor, dividend) =>
          val expected: scala.Int = dividend % divisor
          assert(sdk.Int.remainderBy(divisor)(dividend).toInt)(
            equalTo(expected)
          )
        }
      },
      test("Performing remainderBy on Int16s") {
        check(Gen.short.filter(n => n != 0), Gen.short) { (divisor, dividend) =>
          val expected: scala.Int = dividend % divisor
          assert(sdk.Int.remainderBy(divisor)(dividend).toInt)(
            equalTo(expected)
          )
        }
      },
      test("Performing remainderBy on Int32s") {
        check(Gen.int.filter(n => n != 0), Gen.int) { (divisor, dividend) =>
          val expected: scala.Int = dividend % divisor
          assert(sdk.Int.remainderBy(divisor)(dividend))(equalTo(expected))
        }
      },
      test("Performing remainderBy on Int64s") {
        check(Gen.long.filter(n => n != 0), Gen.long) { (divisor, dividend) =>
          val expected: scala.Long = dividend % divisor
          assert(sdk.Int.remainderBy(divisor)(dividend))(equalTo(expected))
        }
      },
      test("Performing remainderBy on Ints") {
        check(Gen.long.filter(n => n != 0), Gen.long) { (longDivisor, longDividend) =>
          val divisor       = sdk.Int.fromInt64(longDivisor)
          val dividend      = sdk.Int.fromInt64(longDividend)
          val expected: Int = dividend % divisor
          assert(sdk.Int.remainderBy(divisor)(dividend))(equalTo(expected))
        }
      }
    )
  )
}
