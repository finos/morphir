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

import morphir.sdk.Aggregate._
import morphir.sdk.Key.Key0
import zio.test.Assertion._
import zio.test._
import morphir.testing.MorphirBaseSpec

object AggregateSpec extends MorphirBaseSpec {

  case class TestInput1(key1: String, key2: String, value: Double)

  val testDataSet: List[TestInput1] =
    List(
      TestInput1("k1_1", "k2_1", 1),
      TestInput1("k1_1", "k2_1", 2),
      TestInput1("k1_1", "k2_2", 3),
      TestInput1("k1_1", "k2_2", 4),
      TestInput1("k1_2", "k2_1", 5),
      TestInput1("k1_2", "k2_1", 6),
      TestInput1("k1_2", "k2_2", 7),
      TestInput1("k1_2", "k2_2", 8)
    )

  def spec = suite("AggregateSpec")(
    suite("Aggregate.aggregateMap spec")(
      test(
        "aggregate by single key"
      ) {
        val actualResult =
          aggregateMap[TestInput1, (TestInput1, Double), String](byKey[TestInput1, String](_.key1)(sumOf(_.value))) {
            totalValue => input =>
              (input, totalValue / input.value)
          }(testDataSet)

        val expectedResult =
          List(
            TestInput1("k1_1", "k2_1", 1) -> 10.0 / 1,
            TestInput1("k1_1", "k2_1", 2) -> 10.0 / 2,
            TestInput1("k1_1", "k2_2", 3) -> 10.0 / 3,
            TestInput1("k1_1", "k2_2", 4) -> 10.0 / 4,
            TestInput1("k1_2", "k2_1", 5) -> 26.0 / 5,
            TestInput1("k1_2", "k2_1", 6) -> 26.0 / 6,
            TestInput1("k1_2", "k2_2", 7) -> 26.0 / 7,
            TestInput1("k1_2", "k2_2", 8) -> 26.0 / 8
          )
        assert(actualResult)(equalTo(expectedResult))
      },
      test(
        "aggregate by composite key"
      ) {
        val actualResult =
          aggregateMap[TestInput1, (TestInput1, Double), (String, String)](
            byKey[TestInput1, (String, String)](a => (a.key1, a.key2))(sumOf(_.value))
          ) { totalValue => input =>
            (input, totalValue / input.value)
          }(testDataSet)

        val expectedResult =
          List(
            TestInput1("k1_1", "k2_1", 1) -> 3.0 / 1,
            TestInput1("k1_1", "k2_1", 2) -> 3.0 / 2,
            TestInput1("k1_1", "k2_2", 3) -> 7.0 / 3,
            TestInput1("k1_1", "k2_2", 4) -> 7.0 / 4,
            TestInput1("k1_2", "k2_1", 5) -> 11.0 / 5,
            TestInput1("k1_2", "k2_1", 6) -> 11.0 / 6,
            TestInput1("k1_2", "k2_2", 7) -> 15.0 / 7,
            TestInput1("k1_2", "k2_2", 8) -> 15.0 / 8
          )
        assert(actualResult)(equalTo(expectedResult))
      },
      test(
        "aggregate by no key and filter"
      ) {
        val actualResult =
          aggregateMap[TestInput1, (TestInput1, Double), Key0](
            withFilter[TestInput1, Key0](a => a.value > 3)(sumOf(_.value))
          ) { totalValue => input =>
            (input, totalValue / input.value)
          }(testDataSet)

        val expectedResult =
          List(
            TestInput1("k1_1", "k2_1", 1) -> 30.0 / 1,
            TestInput1("k1_1", "k2_1", 2) -> 30.0 / 2,
            TestInput1("k1_1", "k2_2", 3) -> 30.0 / 3,
            TestInput1("k1_1", "k2_2", 4) -> 30.0 / 4,
            TestInput1("k1_2", "k2_1", 5) -> 30.0 / 5,
            TestInput1("k1_2", "k2_1", 6) -> 30.0 / 6,
            TestInput1("k1_2", "k2_2", 7) -> 30.0 / 7,
            TestInput1("k1_2", "k2_2", 8) -> 30.0 / 8
          )
        assert(actualResult)(equalTo(expectedResult))
      },
      test(
        "aggregate 2"
      ) {
        val actualResult =
          aggregateMap2[TestInput1, (TestInput1, Double), String, String](
            byKey[TestInput1, String](_.key1)(sumOf(_.value))
          )(byKey[TestInput1, String](_.key2)(maximumOf(_.value))) { totalValue => maxValue => input =>
            (input, totalValue * maxValue / input.value)
          }(testDataSet)

        val expectedResult =
          List(
            TestInput1("k1_1", "k2_1", 1) -> 10.0 * 6 / 1,
            TestInput1("k1_1", "k2_1", 2) -> 10.0 * 6 / 2,
            TestInput1("k1_1", "k2_2", 3) -> 10.0 * 8 / 3,
            TestInput1("k1_1", "k2_2", 4) -> 10.0 * 8 / 4,
            TestInput1("k1_2", "k2_1", 5) -> 26.0 * 6 / 5,
            TestInput1("k1_2", "k2_1", 6) -> 26.0 * 6 / 6,
            TestInput1("k1_2", "k2_2", 7) -> 26.0 * 8 / 7,
            TestInput1("k1_2", "k2_2", 8) -> 26.0 * 8 / 8
          )
        assert(actualResult)(equalTo(expectedResult))
      },
      test(
        "aggregate 3"
      ) {
        val actualResult =
          aggregateMap3[TestInput1, (TestInput1, Double), String, String, (String, String)](
            byKey[TestInput1, String](_.key1)(sumOf(_.value))
          )(byKey[TestInput1, String](_.key2)(maximumOf(_.value)))(
            byKey[TestInput1, (String, String)](a => (a.key1, a.key2))(minimumOf(_.value))
          ) { totalValue => maxValue => minValue => input =>
            (input, (totalValue * maxValue) / input.value + minValue)
          }(testDataSet)

        val expectedResult =
          List(
            TestInput1("k1_1", "k2_1", 1) -> (10.0 * 6.0 / 1.0 + 1.0),
            TestInput1("k1_1", "k2_1", 2) -> (10.0 * 6 / 2 + 1.0),
            TestInput1("k1_1", "k2_2", 3) -> (10.0 * 8 / 3 + 3.0),
            TestInput1("k1_1", "k2_2", 4) -> (10.0 * 8 / 4 + 3.0),
            TestInput1("k1_2", "k2_1", 5) -> (26.0 * 6 / 5 + 5.0),
            TestInput1("k1_2", "k2_1", 6) -> (26.0 * 6 / 6 + 5.0),
            TestInput1("k1_2", "k2_2", 7) -> (26.0 * 8 / 7 + 7.0),
            TestInput1("k1_2", "k2_2", 8) -> (26.0 * 8 / 8 + 7.0)
          )
        assert(actualResult)(equalTo(expectedResult))
      },
      test(
        "aggregate 4"
      ) {
        val actualResult =
          aggregateMap4[TestInput1, (TestInput1, Double), String, String, (String, String), (String, String)](
            byKey[TestInput1, String](_.key1)(sumOf(_.value))
          )(byKey[TestInput1, String](_.key2)(maximumOf(_.value)))(
            byKey[TestInput1, (String, String)](a => (a.key1, a.key2))(minimumOf(_.value))
          )(byKey[TestInput1, (String, String)](a => (a.key1, a.key2))(averageOf(_.value))) {
            totalValue => maxValue => minValue => averageValue => input =>
              (input, (totalValue * maxValue) / input.value + minValue + averageValue)
          }(testDataSet)

        val expectedResult =
          List(
            TestInput1("k1_1", "k2_1", 1) -> (10.0 * 6.0 / 1.0 + 1.0 + 1.5),
            TestInput1("k1_1", "k2_1", 2) -> (10.0 * 6 / 2 + 1.0 + 1.5),
            TestInput1("k1_1", "k2_2", 3) -> (10.0 * 8 / 3 + 3.0 + 3.5),
            TestInput1("k1_1", "k2_2", 4) -> (10.0 * 8 / 4 + 3.0 + 3.5),
            TestInput1("k1_2", "k2_1", 5) -> (26.0 * 6 / 5 + 5.0 + 5.5),
            TestInput1("k1_2", "k2_1", 6) -> (26.0 * 6 / 6 + 5.0 + 5.5),
            TestInput1("k1_2", "k2_2", 7) -> (26.0 * 8 / 7 + 7.0 + 7.5),
            TestInput1("k1_2", "k2_2", 8) -> (26.0 * 8 / 8 + 7.0 + 7.5)
          )
        assert(actualResult)(equalTo(expectedResult))
      },
      test(
        "count by single key"
      ) {
        val actualResult =
          aggregateMap[TestInput1, (TestInput1, Double), String](byKey[TestInput1, String](_.key1)(count)) {
            totalValue => input =>
              (input, totalValue)
          }(testDataSet)

        val expectedResult =
          List(
            TestInput1("k1_1", "k2_1", 1) -> 4.0,
            TestInput1("k1_1", "k2_1", 2) -> 4.0,
            TestInput1("k1_1", "k2_2", 3) -> 4.0,
            TestInput1("k1_1", "k2_2", 4) -> 4.0,
            TestInput1("k1_2", "k2_1", 5) -> 4.0,
            TestInput1("k1_2", "k2_1", 6) -> 4.0,
            TestInput1("k1_2", "k2_2", 7) -> 4.0,
            TestInput1("k1_2", "k2_2", 8) -> 4.0
          )
        assert(actualResult)(equalTo(expectedResult))
      },
      test(
        "sum by single key"
      ) {
        val actualResult =
          aggregateMap[TestInput1, (TestInput1, Double), String](byKey[TestInput1, String](_.key1)(sumOf(_.value))) {
            totalValue => input =>
              (input, totalValue)
          }(testDataSet)

        val expectedResult =
          List(
            TestInput1("k1_1", "k2_1", 1) -> 10.0,
            TestInput1("k1_1", "k2_1", 2) -> 10.0,
            TestInput1("k1_1", "k2_2", 3) -> 10.0,
            TestInput1("k1_1", "k2_2", 4) -> 10.0,
            TestInput1("k1_2", "k2_1", 5) -> 26.0,
            TestInput1("k1_2", "k2_1", 6) -> 26.0,
            TestInput1("k1_2", "k2_2", 7) -> 26.0,
            TestInput1("k1_2", "k2_2", 8) -> 26.0
          )
        assert(actualResult)(equalTo(expectedResult))
      },
      test(
        "avg by single key"
      ) {
        val actualResult =
          aggregateMap[TestInput1, (TestInput1, Double), String](
            byKey[TestInput1, String](_.key1)(averageOf(_.value))
          ) { totalValue => input =>
            (input, totalValue)
          }(testDataSet)

        val expectedResult =
          List(
            TestInput1("k1_1", "k2_1", 1) -> 2.5,
            TestInput1("k1_1", "k2_1", 2) -> 2.5,
            TestInput1("k1_1", "k2_2", 3) -> 2.5,
            TestInput1("k1_1", "k2_2", 4) -> 2.5,
            TestInput1("k1_2", "k2_1", 5) -> 6.5,
            TestInput1("k1_2", "k2_1", 6) -> 6.5,
            TestInput1("k1_2", "k2_2", 7) -> 6.5,
            TestInput1("k1_2", "k2_2", 8) -> 6.5
          )
        assert(actualResult)(equalTo(expectedResult))
      },
      test(
        "min by single key"
      ) {
        val actualResult =
          aggregateMap[TestInput1, (TestInput1, Double), String](
            byKey[TestInput1, String](_.key1)(minimumOf(_.value))
          ) { totalValue => input =>
            (input, totalValue)
          }(testDataSet)

        val expectedResult =
          List(
            TestInput1("k1_1", "k2_1", 1) -> 1.0,
            TestInput1("k1_1", "k2_1", 2) -> 1.0,
            TestInput1("k1_1", "k2_2", 3) -> 1.0,
            TestInput1("k1_1", "k2_2", 4) -> 1.0,
            TestInput1("k1_2", "k2_1", 5) -> 5.0,
            TestInput1("k1_2", "k2_1", 6) -> 5.0,
            TestInput1("k1_2", "k2_2", 7) -> 5.0,
            TestInput1("k1_2", "k2_2", 8) -> 5.0
          )
        assert(actualResult)(equalTo(expectedResult))
      },
      test(
        "max by single key"
      ) {
        val actualResult =
          aggregateMap[TestInput1, (TestInput1, Double), String](
            byKey[TestInput1, String](_.key1)(maximumOf(_.value))
          ) { totalValue => input =>
            (input, totalValue)
          }(testDataSet)

        val expectedResult =
          List(
            TestInput1("k1_1", "k2_1", 1) -> 4.0,
            TestInput1("k1_1", "k2_1", 2) -> 4.0,
            TestInput1("k1_1", "k2_2", 3) -> 4.0,
            TestInput1("k1_1", "k2_2", 4) -> 4.0,
            TestInput1("k1_2", "k2_1", 5) -> 8.0,
            TestInput1("k1_2", "k2_1", 6) -> 8.0,
            TestInput1("k1_2", "k2_2", 7) -> 8.0,
            TestInput1("k1_2", "k2_2", 8) -> 8.0
          )
        assert(actualResult)(equalTo(expectedResult))
      },
      test(
        "weighted average by single key"
      ) {
        val actualResult =
          aggregateMap[TestInput1, (TestInput1, Double), String](
            byKey[TestInput1, String](_.key1)(weightedAverageOf(_.value, _.value))
          ) { totalValue => input =>
            (input, totalValue)
          }(testDataSet)

        val expectedResult =
          List(
            TestInput1("k1_1", "k2_1", 1) -> 3.0,
            TestInput1("k1_1", "k2_1", 2) -> 3.0,
            TestInput1("k1_1", "k2_2", 3) -> 3.0,
            TestInput1("k1_1", "k2_2", 4) -> 3.0,
            TestInput1("k1_2", "k2_1", 5) -> 174.0 / 26.0,
            TestInput1("k1_2", "k2_1", 6) -> 174.0 / 26.0,
            TestInput1("k1_2", "k2_2", 7) -> 174.0 / 26.0,
            TestInput1("k1_2", "k2_2", 8) -> 174.0 / 26.0
          )
        assert(actualResult)(equalTo(expectedResult))
      }
    )
  )
}
