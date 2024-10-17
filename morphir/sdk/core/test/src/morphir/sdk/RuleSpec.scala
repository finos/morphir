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

object RuleSpec extends MorphirBaseSpec {
  def spec = suite("RuleSpec")(
    suite("Rule.chain specs")(
      chainTests(
        (List(), Char.from('a'), Maybe.Nothing),
        (List((_: Char.Char) => Maybe.Nothing), Char.from('a'), Maybe.Nothing),
        (
          List((_: Char.Char) => Maybe.Nothing, (a: Char.Char) => Maybe.Just(a)),
          Char.from('a'),
          Maybe.Just(Char.from('a'))
        ),
        (
          List((_: Char.Char) => Maybe.Just(Char.from('b')), (a: Char.Char) => Maybe.Just(a)),
          Char.from('a'),
          Maybe.Just(Char.from('b'))
        )
      ): _*
    ),
    suite("Rule.any specs")(
      test("Calling any on anything should return True") {
        check(Gen.alphaNumericChar)(input => assert(Rule.any(input))(equalTo(Basics.True)))
      }
    ),
    suite("Rule.is specs")(
      test("Calling is by passing in the same value twice should return True") {
        check(Gen.alphaNumericChar)(input => assert(Rule.is(input)(input))(equalTo(Basics.True)))
      },
      test("Calling is by passing in two different values should return False") {
        val gen =
          for {
            ref   <- Gen.alphaNumericString
            input <- Gen.alphaNumericString
            if ref != input
          } yield (ref, input)
        check(gen) { case (ref, input) =>
          assert(Rule.is(ref)(input))(equalTo(Basics.False))
        }
      }
    ),
    suite("Rule.anyOf specs")(
      test("Calling anyOf by passing in a list and a member should return True") {
        val gen =
          for {
            ref <- Gen.listOf(Gen.alphaNumericString)
            if ref.nonEmpty
          } yield (ref, ref.head)
        check(gen) { case (ref, input) =>
          assert(Rule.anyOf(ref)(input))(equalTo(Basics.True))
        }
      },
      test("Calling anyOf by passing in a list and a non-member should return False") {
        val gen =
          for {
            ref   <- Gen.listOf(Gen.alphaNumericString)
            input <- Gen.alphaNumericString
            if !ref.contains(input)
          } yield (ref, input)
        check(gen) { case (ref, input) =>
          assert(Rule.anyOf(ref)(input))(equalTo(Basics.False))
        }
      }
    ),
    suite("Rule.noneOf specs")(
      test("Calling noneOf by passing in a list and a member should return False") {
        val gen =
          for {
            ref <- Gen.listOf(Gen.alphaNumericString)
            if ref.nonEmpty
          } yield (ref, ref.head)
        check(gen) { case (ref, input) =>
          assert(Rule.noneOf(ref)(input))(equalTo(Basics.False))
        }
      },
      test("Calling noneOf by passing in a list and a non-member should return True") {
        val gen =
          for {
            ref   <- Gen.listOf(Gen.alphaNumericString)
            input <- Gen.alphaNumericString
            if !ref.contains(input)
          } yield (ref, input)
        check(gen) { case (ref, input) =>
          assert(Rule.noneOf(ref)(input))(equalTo(Basics.True))
        }
      }
    )
  )

  def chainTests(cases: (List[Rule.Rule[Char.Char, Char.Char]], Char.Char, Maybe.Maybe[Char.Char])*) =
    cases.map { case (rules, input, expectedResult) =>
      test(
        s"Given the rules: '$rules' passing in input: '$input' chain should return '$expectedResult'"
      ) {
        assert(Rule.chain(rules)(input))(equalTo(expectedResult))
      }
    }

}
