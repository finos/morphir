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

import zio.test._
import zio._
import zio.test.Assertion._
import zio.test.TestAspect.timeout
import morphir.testing.MorphirBaseSpec

object ListSpec extends MorphirBaseSpec {
  def spec = suite("ListSpec")(
    suite("List.all spec")(
      test(
        "all - should return true if all members meet the predicate condition"
      ) {
        def isEven(n: Int) = Int.modBy(2)(n) == 0
        assert(List.all(isEven)(List(2, 4)))(isTrue)
      },
      test(
        "all - should return false if any member DOES NOT meet the predicate condition"
      ) {
        def isEven(n: Int) = Int.modBy(2)(n) == 0
        assert(List.all(isEven)(List(2, 3)))(isFalse)
      },
      test(
        "all - should return true if the list is empty"
      ) {
        def isEven(n: Int) = Int.modBy(2)(n) == 0
        assert(List.all(isEven)(List.empty))(isTrue)
      }
    ),
    suite("List.any spec")(
      test(
        "any - should return true if any members meet the predicate condition"
      ) {
        def isEven(n: Int) = Int.modBy(2)(n) == 0
        assert(List.any(isEven)(List(2, 3)))(isTrue)
      },
      test(
        "any - should return false if none of the members meet the predicate condition"
      ) {
        def isEven(n: Int) = Int.modBy(2)(n) == 0
        assert(List.any(isEven)(List(1, 3)))(isFalse)
      },
      test(
        "any - should return false if the list is empty"
      ) {
        def isEven(n: Int) = Int.modBy(2)(n) == 0
        assert(List.any(isEven)(List.empty))(isFalse)
      }
    ),
    suite("List.append spec")(
      test("append should combine 2 lists") {
        assert(List.append(List(1, 1, 2))(List(3, 5, 8)))(
          equalTo(List(1, 1, 2, 3, 5, 8))
        )
      }
    ),
    suite("List.concat spec")(
      test("concat - should concatenate many lists") {
        assert(List.concat(List(List(1, 2), List(3), List(4, 5))))(
          equalTo(List(1, 2, 3, 4, 5))
        )
      }
    ),
    suite("List.concatMap spec")(
      test("concatMap - should map and flatten a list") {
        def doubleIt(n: Int) = List(n * 2)
        val xs               = List(1, 2, 3, 4, 5)
        assert(List.concatMap(doubleIt)(xs))(
          equalTo(List.concat(List.map(doubleIt)(xs)))
        )
      }
    ),
    suite("List.intersperse specs")(
      test("intersperse - should place the value between all elements") {
        assert(List.intersperse("on")(List("turtles", "turtles", "turtles")))(
          equalTo(List("turtles", "on", "turtles", "on", "turtles"))
        )
      },
      test("intersperse - should place the value between all elements(2)") {
        assert(List.intersperse(",")(List("A", "B", "C", "D")))(
          equalTo(List("A", ",", "B", ",", "C", ",", "D"))
        )
      }
    ),
    suite("List.filter spec")(
      test("filter should remove items that don't satisfy the given predicate") {
        val sut            = List(1, 2, 3, 4, 5, 6)
        def isEven(n: Int) = n % 2 == 0
        assert(List.filter(isEven)(sut))(equalTo(List(2, 4, 6)))
      }
    ),
    suite("List.filterMap spec")(
      test("filterMap should filter out non-ints") {
        val sut = List("3", "hi", "12", "4th", "May")
        assert(List.filterMap(String.toInt)(sut))(
          equalTo(List[Basics.Int](3, 12))
        )
      }
    ) @@ timeout(10.seconds),
    suite("List.foldl spec")(
      test("foldl should reduce a list from the left") {
        assert(List.foldl(List.cons[Int])(List.empty[Int])(List(1, 2, 3)))(
          equalTo(List(3, 2, 1))
        )
      }
    ),
    suite("List.foldr spec")(
      test("foldr should reduce a list from the right") {
        assert(List.foldr(List.cons[Int])(List.empty[Int])(List(1, 2, 3)))(
          equalTo(List(1, 2, 3))
        )
      }
    ),
    suite("List.map2 spec")(
      test("Given lists of the same length") {
        val xs = List(1, 2, 3, 4, 5)
        val ys = List('A', 'B', 'C', 'D', 'E')
        assert(List.map2((x: Int) => (y: Char) => (x, y))(xs)(ys))(
          equalTo(List(1 -> 'A', 2 -> 'B', 3 -> 'C', 4 -> 'D', 5 -> 'E'))
        )
      },
      test(
        "Given lists where the first list is shorter than second, it should not fail"
      ) {
        val xs = List("alice", "bob", "chuck")
        val ys = List(2, 5, 7, 8)
        assert(List.map2((x: String) => (y: Int) => (x, y))(xs)(ys))(
          equalTo(List(("alice", 2), ("bob", 5), ("chuck", 7)))
        )
      },
      test(
        "Given lists where the first list is longer than second, it should not fail"
      ) {
        val xs = List("alice", "bob", "chuck", "debbie")
        val ys = List(2, 5, 7)
        assert(List.map2((x: String) => (y: Int) => (x, y))(xs)(ys))(
          equalTo(List(("alice", 2), ("bob", 5), ("chuck", 7)))
        )
      }
    ),
    suite("List.map3 specs")(
      test("Given lists of the same length") {
        val xs = List(1, 2, 3, 4, 5)
        val ys = List('A', 'B', 'C', 'D', 'E')
        val zs = List("V", "W", "X", "Y", "Z")
        assert(
          List
            .map3((x: Int) => (y: Char) => (z: String) => s"$x$y$z")(xs)(ys)(zs)
        )(
          equalTo(List("1AV", "2BW", "3CX", "4DY", "5EZ"))
        )
      },
      test(
        "Given lists where the first list is shorter than the rest, it should not fail"
      ) {
        val xs = List("alice", "bob", "chuck")
        val ys = List(2, 5, 7, 8)
        val zs = List('F', 'M', 'M', 'F', 'F')
        assert(
          List.map3((x: String) => (y: Int) => (z: scala.Char) => (x, y, z))(
            xs
          )(ys)(zs)
        )(
          equalTo(List(("alice", 2, 'F'), ("bob", 5, 'M'), ("chuck", 7, 'M')))
        )
      },
      test(
        "Given lists where the second list is shorter than the rest, it should not fail"
      ) {
        val xs = List("alice", "bob", "chuck")
        val ys = List(2, 5)
        val zs = List('F', 'M', 'M', 'F', 'F')
        assert(
          List.map3((x: String) => (y: Int) => (z: scala.Char) => (x, y, z))(
            xs
          )(ys)(zs)
        )(
          equalTo(List(("alice", 2, 'F'), ("bob", 5, 'M')))
        )
      },
      test(
        "Given lists where the third list is shorter than the rest, it should not fail"
      ) {
        val xs = List("alice", "bob", "chuck", "debbie")
        val ys = List(2, 5, 7, 8)
        val zs = List('F', 'M', 'M')
        assert(
          List.map3((x: String) => (y: Int) => (z: scala.Char) => (x, y, z))(
            xs
          )(ys)(zs)
        )(
          equalTo(List(("alice", 2, 'F'), ("bob", 5, 'M'), ("chuck", 7, 'M')))
        )
      }
    ),
    suite("List.member spcs")(
      test(
        "member should return false when the List does not contains the item"
      ) {
        assert(List.member(9)(List(1, 2, 3, 4)))(equalTo(false))
      },
      test("member should return true when the List contains the item") {
        assert(List.member(4)(List(1, 2, 3, 4)))(equalTo(true))
      }
    ),
    suite("List.reverse specs")(
      test("reverse should reverse a list") {
        assert(List.reverse(List(1, 2, 3, 4)))(equalTo(List(4, 3, 2, 1)))
      }
    ),
    suite("List.innerJoin specs")(
      test("innerJoin should join two lists discarding non-matching rows") {
        assert(List.innerJoin(List(1, 2, 3, 4))((a: Int) => (b: Int) => a == b)(List(4, 3, 2)))(
          equalTo(List((4, 4), (3, 3), (2, 2)))
        )
      }
    ),
    suite("List.leftJoin specs")(
      test("leftJoin should join two lists including non-matching rows with a value of Maybe.Nothing") {
        assert(List.leftJoin(List(2, 3, 4))((a: Int) => (b: Int) => a == b)(List(4, 3, 2, 1)))(
          equalTo(List((4, Maybe.just(4)), (3, Maybe.just(3)), (2, Maybe.just(2)), (1, Maybe.nothing)))
        )
      }
    )
  )
}
