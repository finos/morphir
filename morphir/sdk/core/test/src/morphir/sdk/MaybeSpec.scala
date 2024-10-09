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

import morphir.sdk.Maybe.Maybe
import zio.test.Assertion._
import zio.test._
import morphir.testing.MorphirBaseSpec

object MaybeSpec extends MorphirBaseSpec {
  def spec = suite("MaybeSpec")(
    suite("Just specs")(
      test("Just should be convertible to Some") {
        check(Gen.alphaNumericChar) { input =>
          val maybe = Maybe.Just(input)
          assert(Maybe.toOption(maybe))(isSome(equalTo(input)))
        }
      },
      suite("Calling withDefault")(
        test("Should produce the default value when the value is 'Nothing'") {
          assert(Maybe.withDefault("DEFAULT")(Maybe.Nothing))(
            equalTo("DEFAULT")
          )
        },
        test("Should produce the original value if the original is 'Just'") {
          assert(Maybe.withDefault("DEFAULT")(Maybe.just("Fish Sticks")))(
            equalTo("Fish Sticks")
          )
        }
      ),
      suite("Calling map")(
        test("Should return a mapped value when the SUT is a 'Just'") {
          val sut = Maybe.just(42)
          assert(Maybe.map((v: Int) => v * 2)(sut))(
            equalTo(Maybe.just(84))
          )
        },
        test(
          "Should be capable of returning a mapped value of another type when the SUT is a 'Just'"
        ) {
          val sut = Maybe.just(42)
          assert(Maybe.map((_: Int) => "Forty Two")(sut))(
            equalTo(Maybe.just("Forty Two"))
          )
        },
        test(
          "Should be capable of returning a mapped value of a non-primitive type when the SUT is a 'Just'"
        ) {
          val sut = Maybe.just(42)
          assert(Maybe.map((_: Int) => Wrapped(42))(sut))(
            equalTo(Maybe.just(Wrapped(42)))
          )
        },
        test("Should return 'Nothing' value when the SUT is 'Nothing'") {
          val sut = Maybe.Nothing
          assert(Maybe.map((v: Int) => v * 2)(sut))(
            equalTo(Maybe.Nothing)
          )
        }
      ),
      suite("Calling andThen")(
        test("Should return a mapped 'Just' value for an input that is 'Just'") {
          check(Gen.int(0, 255)) { input =>
            val sut = Maybe.just(input.toString())
            assert(Maybe.andThen((v: String) => Maybe.Just(v.toInt))(sut))(
              equalTo(Maybe.just(input))
            )
          }

        }
      ),
      suite("Foreach spec")(
        test("Given a Just foreach should execute the given function") {
          var entries              = List.empty[String]
          def push(entry: String)  = entries = entry :: entries
          val maybe: Maybe[String] = Maybe.just("Hello")
          maybe.foreach(push)
          assert(entries)(equalTo(List("Hello")))
        },
        test("Given a Nothing foreach should NOT execute the given function") {
          var entries              = List.empty[String]
          def push(entry: String)  = entries = entry :: entries
          val maybe: Maybe[String] = Maybe.Nothing
          maybe.foreach(push)
          assert(entries)(equalTo(List.empty))
        }
      ),
      suite("For comprehension spec")(
        test("Basic for loop should be supported") {
          var entries              = List.empty[String]
          def push(entry: String)  = entries = entry :: entries
          val maybe: Maybe[String] = Maybe.just("Hello")
          for {
            m <- maybe
          } push(m)

          assert(entries)(equalTo(List("Hello")))
        },
        test("yield should be supported") {
          val result = for {
            a <- Maybe.Just(42)
          } yield 2 * a
          assert(result)(equalTo(Maybe.Just(84)))
        },
        test("Multiple generators should be supported") {
          check(Gen.alphaNumericString, Gen.alphaNumericString) { (part1, part2) =>
            val result = for {
              a <- Maybe.Just(part1)
              b <- Maybe.Just(part2)
            } yield s"$a-$b"

            assert(result)(equalTo(Maybe.just(s"$part1-$part2")))
          }
        },
        test("if expressions shoud be supported") {
          val result = for {
            a <- Maybe.just(42)
            if (a % 2 == 0)
            b <- Maybe.just(8)
          } yield a + b

          assert(result)(equalTo(Maybe.just(50)))
        }
      )
    )
  )

  case class Wrapped[A](value: A)
}
