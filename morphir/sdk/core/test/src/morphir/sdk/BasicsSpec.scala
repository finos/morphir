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

import zio.test.Assertion._
import zio.test._
import morphir.testing.MorphirBaseSpec

object BasicsSpec extends MorphirBaseSpec {
  def spec = suite("BasicsSpec")(
    suite("Basics.Float spec")(
      test("Construct from Float") {
        check(Gen.float) { (f: Float) =>
          val instance = Basics.Float(f)
          assert(instance)(equalTo(f.doubleValue()))
        }
      },
      test("Construct from Double") {
        check(Gen.double) { (d: Double) =>
          val instance = Basics.Float(d)
          assert(instance)(equalTo(d))
        }
      },
      test("Construct from Int") {
        check(Gen.int) { (i: Int) =>
          val instance = Basics.Float(i)
          assert(instance)(equalTo(i.doubleValue()))
        }
      }
    ),
    suite("Basics.add spec")(
      test("Add a Float value to another Float value") {
        check(Gen.double, Gen.double) { (d1: Basics.Float, d2: Basics.Float) =>
          val expected = d1 + d2
          assert(Basics.add(d1)(d2))(equalTo(expected))
        }
      }
    ),
    suite("Basics.subtract spec")(
      test("Subtract a Float value from another Float value") {
        check(Gen.double, Gen.double) { (d1: Basics.Float, d2: Basics.Float) =>
          val expected = d1 - d2
          assert(Basics.subtract(d1)(d2))(equalTo(expected))
        }
      }
    ),
    suite("Basics.multiply spec")(
      test("Multiply a Float value by another Float value") {
        check(Gen.double, Gen.double) { (d1: Basics.Float, d2: Basics.Float) =>
          val expected = d1 * d2
          assert(Basics.multiply(d1)(d2))(equalTo(expected))
        }
      }
    ),
    suite("Basics.divide spec")(
      test("Divide a Float value by another Float value") {
        check(Gen.double, Gen.double.filter(n => n != 0)) { (d1: Basics.Float, d2: Basics.Float) =>
          val expected = d1 / d2
          assert(Basics.divide(d1)(d2))(equalTo(expected))
        }
      }
    ),
    suite("Basics.power spec")(
      test("Power an Int value by another Int value") {
        check(Gen.int, Gen.int(-10, 10)) { (d1: Basics.Int, d2: Basics.Int) =>
          val expected = d1 ^ d2
          assert(Basics.power(d1)(d2))(equalTo(expected))
        }
      }
    ),
    suite("Basics.equal spec")(
      test("Equal check a Float value to itself") {
        check(Gen.double) { (dn: Double) =>
          val expected = true
          val d        = Basics.Float(dn)
          assert(Basics.equal(d)(d))(equalTo(expected))
        }
      },
      test("Equal check a Float value to a different Float value") {
        check(Gen.double) { (dn: Double) =>
          val expected = false
          val d1       = Basics.Float(dn)
          val d2       = Basics.Float(dn + 3.14)
          assert(Basics.equal(d1)(d2))(equalTo(expected))
        }
      }
    ),
    suite("Basics.notEqual spec")(
      test("Not-Equal check a Float value to itself") {
        check(Gen.double) { (dn: Double) =>
          val expected = false
          val d        = Basics.Float(dn)
          assert(Basics.notEqual(d)(d))(equalTo(expected))
        }
      },
      test("Not-Equal check a Float value to a different Float value") {
        check(Gen.double) { (dn: Double) =>
          val expected = true
          val d1       = Basics.Float(dn)
          val d2       = Basics.Float(dn + 3.14)
          assert(Basics.notEqual(d1)(d2))(equalTo(expected))
        }
      }
    ),
    suite("Basics.lessThan spec")(
      test("Performing lessThan check on Floats") {
        check(Gen.double, Gen.double) { (d1: Basics.Float, d2: Basics.Float) =>
          val expected = (d1 < d2)
          assert(Basics.lessThan(d1)(d2))(equalTo(expected))
        }
      }
    ),
    suite("Basics.greaterThan spec")(
      test("Performing lessThan check on Floats") {
        check(Gen.double, Gen.double) { (d1: Basics.Float, d2: Basics.Float) =>
          val expected = (d1 > d2)
          assert(Basics.greaterThan(d1)(d2))(equalTo(expected))
        }
      }
    ),
    suite("Basics.lessThanOrEqual spec")(
      test("Performing lessThanOrEqual check on different Floats") {
        check(Gen.double, Gen.double) { (d1: Basics.Float, d2: Basics.Float) =>
          val expected = (d1 <= d2)
          assert(Basics.lessThanOrEqual(d1)(d2))(equalTo(expected))
        }
      },
      test("Performing lessThanOrEqual check on same Float") {
        check(Gen.double) { (dn: Double) =>
          val d1       = Basics.Float(dn)
          val d2       = Basics.Float(dn)
          val expected = (d1 <= d2)
          assert(Basics.lessThanOrEqual(d1)(d1))(equalTo(expected))
        }
      }
    ),
    suite("Basics.greaterThanOrEqual spec")(
      test("Performing greaterThanOrEqual check on different Floats") {
        check(Gen.double, Gen.double) { (d1: Basics.Float, d2: Basics.Float) =>
          val expected = (d1 >= d2)
          assert(Basics.greaterThanOrEqual(d1)(d2))(equalTo(expected))
        }
      },
      test("Performing greaterThanOrEqual check on same Float") {
        check(Gen.double) { (dn: Double) =>
          val d1       = Basics.Float(dn)
          val d2       = Basics.Float(dn)
          val expected = (d1 >= d2)
          assert(Basics.lessThanOrEqual(d1)(d1))(equalTo(expected))
        }
      }
    ),
    suite("BoolSpec")(
      test("Bool xor - true xor true")(
        assert(Basics.xor(Basics.Bool(true))(Basics.Bool(true)))(isFalse)
      ),
      test("Bool xor - true xor false")(
        assert(Basics.xor(Basics.Bool(true))(Basics.Bool(false)))(isTrue)
      ),
      test("Bool xor - false xor true")(
        assert(Basics.xor(Basics.Bool(false))(Basics.Bool(true)))(isTrue)
      ),
      test("Bool xor - false xor false")(
        assert(Basics.xor(Basics.Bool(false))(Basics.Bool(false)))(isFalse)
      )
    )
  )
}
