package morphir.sdk

import zio.test.Assertion._
import zio.test._

import morphir.testing.MorphirBaseSpec
object DictSpec extends MorphirBaseSpec {
  def spec = suite("ListSpec")(
    suite("Dict.empty spec")(
      test("should create an empty dict") {
        assert(Dict.empty)(equalTo(Map.empty))
      }
    ),
    suite("Dict.singleton spec")(
      test("should create a dict with one single key value pair") {
        assert(Dict.singleton(1)("A"))(equalTo(Map(1 -> "A")))
      }
    ),
    suite("Dict.insert spec")(
      test("should insert a new field into a dict") {
        assert(Dict.insert(2)("B")(Map(1 -> "A")))(equalTo(Map(1 -> "A", 2 -> "B")))
      }
    ),
    suite("Dict.update spec")(
      test("should update value of a key") {
        assert(Dict.update(1)((_: Maybe.Maybe[String]) => Maybe.Just("C"))(Map(1 -> "A")))(equalTo(Map(1 -> "C")))
      }
    ),
    suite("Dict.remove spec")(
      test("should remove particular key and value") {
        assert(Dict.remove(1)(Map(1 -> "A", 2 -> "B")))(equalTo(Map(2 -> "B")))
      }
    ),
    suite("Dict.isEmpty spec")(
      test("should return true if a dict is empty") {
        assert(Dict.isEmpty(Map.empty))(isTrue)
      },
      test("should return false if a dict is not empty") {
        assert(Dict.isEmpty(Map(1 -> "A", 2 -> "B")))(isFalse)
      }
    ),
    suite("Dict.member spec")(
      test("should contain given key") {
        assert(Dict.member(1)(Map(1 -> "A")))(isTrue)
      }
    ),
    suite("Dict.get spec")(
      test("should return value of dict given the key") {
        assert(Dict.get(1)(Map(1 -> "A")))(equalTo(Maybe.Just("A")))
      }
    ),
    suite("Dict.size spec")(
      test("should return the size of dict") {
        assert(Dict.size(Map(1 -> "A", 2 -> "B", 3 -> "C")))(equalTo(3))
      }
    ),
    suite("Dict.keys spec")(
      test("should return a list of keys in dict") {
        assert(Dict.keys(Map(1 -> "A", 2 -> "B", 3 -> "C")))(equalTo(List(1, 2, 3)))
      }
    ),
    suite("Dict.values spec")(
      test("should return a list of values in dict") {
        assert(Dict.values(Map(1 -> "A", 2 -> "B", 3 -> "C")))(equalTo(List("A", "B", "C")))
      }
    ),
    suite("Dict.toList spec")(
      test("should convert a dict to a list") {
        assert(Dict.toList(Map(1 -> "A", 2 -> "B", 3 -> "C")))(equalTo(List((1 -> "A"), (2 -> "B"), (3 -> "C"))))
      }
    ),
    suite("Dict.fromList spec")(
      test("should convert a list to a dict") {
        assert(Dict.fromList(List((1 -> "A"), (2 -> "B"), (3 -> "C"))))(equalTo(Map(1 -> "A", 2 -> "B", 3 -> "C")))
      }
    ),
    suite("Dict.map spec")(
      test("should map over values in dict") {
        def addOne = (_: String) => (y: Int) => (y + 1)
        val b      = Map("A" -> 1, "B" -> 2, "C" -> 3)
        assert(Dict.map(addOne)(b))(equalTo(Map("A" -> 2, "B" -> 3, "C" -> 4)))
      }
    ),
    suite("Dict.foldl spec")(
      test("should foldl values in dict") {
        def sumAll = (_: String) => (v: Int) => (z: Int) => z + v
        val b      = Map("A" -> 1, "B" -> 2, "C" -> 3)
        assert(Dict.foldl(sumAll)(0)(b))(equalTo(6))
      }
    ),
    suite("Dict.foldr spec")(
      test("should foldr values in dict") {
        def sumAll = (_: String) => (v: Int) => (z: Int) => z + v
        val b      = Map("A" -> 1, "B" -> 2, "C" -> 3)
        assert(Dict.foldr(sumAll)(0)(b))(equalTo(6))
      }
    ),
    suite("Dict.filter spec")(
      test("should filter and return a key and its value in a dict") {
        val b       = Map("A" -> 1, "B" -> 2, "C" -> 3)
        def findKey = (k: String) => (_: Int) => k == "B"
        assert(Dict.filter(findKey)(b))(equalTo(Map("B" -> 2)))
      }
    ),
    suite("Dict.partition spec")(
      test("should partition a dict") {
        val b      = Map("A" -> 1, "B" -> 2, "C" -> 3, "D" -> 4)
        val result = (Map("B" -> 2, "D" -> 4), Map("A" -> 1, "C" -> 3))
        def parti  = (_: String) => (v: Int) => v % 2 == 0
        assert(Dict.partition(parti)(b))(equalTo(result))
      }
    ),
    suite("Dict.union spec")(
      test("union of two dicts") {
        assert(Dict.union(Map(1 -> "A", 2 -> "B", 3 -> "C"))(Map(4 -> "D", 5 -> "E", 6 -> "F")))(
          equalTo(Map(1 -> "A", 2 -> "B", 3 -> "C", 4 -> "D", 5 -> "E", 6 -> "F"))
        )
      }
    ),
    suite("Dict.intersect spec")(
      test("should return common field in two dicts") {
        assert(Dict.intersect(Map(1 -> "A", 2 -> "B", 3 -> "C", 4 -> "D"))(Map(4 -> "D", 1 -> "A")))(
          equalTo(Map(4 -> "D", 1 -> "A"))
        )
      }
    ),
    suite("Dict.diff spec")(
      test("should return diff in two dicts") {
        assert(Dict.diff(Map(1 -> "A", 2 -> "B", 3 -> "C", 4 -> "D"))(Map(4 -> "D", 1 -> "A")))(
          equalTo(Map(2 -> "B", 3 -> "C"))
        )
      }
    )
  )
}
