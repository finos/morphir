/*
  Copyright 2022 Morgan Stanley

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


import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions.explode
import org.apache.spark.sql.types._
import org.scalatest.FunSuite
import sparktests.returntypetests.SparkJobs

class returnTypeTest extends FunSuite {
  val localTestSession =
    SparkSession.builder().master("local").appName("ReadCsv").getOrCreate()

  import localTestSession.implicits._

  val schema = new StructType()
    .add("foo", DoubleType, false)

  val df_test_data = localTestSession.read.format("csv")
    .option("header", "true")
    .schema(schema)
    .load("spark/test/src/spark_test_data/foo_float_data.csv")

  val df_age_test_data = localTestSession.read.format("csv")
    .option("header", "true")
    .schema(new StructType().add("ageOfItem", DoubleType, false))
    .load("spark/test/src/spark_test_data/antique_age_data.csv")

  test("testReturnListRecords") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(new StructType().add("foo", DoubleType, false))
      .load("spark/test/src/spark_test_data/expected_results_testReturnListRecords.csv")

    val df_actual_results = SparkJobs.testReturnListRecords(df_test_data)

    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testReturnValue1") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(new StructType().add("foo", DoubleType, false))
      .load("spark/test/src/spark_test_data/expected_results_testReturnValue1.csv")

    val df_actual_results = SparkJobs.testReturnValue1(df_test_data)

    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testReturnValue2") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(new StructType().add("foo", IntegerType, false))
      .load("spark/test/src/spark_test_data/expected_results_testReturnValue2.csv")

    val df_actual_results = SparkJobs.testReturnValue2(df_test_data)

    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testReturnMaybe") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(new StructType().add("foo", DoubleType, true))
      .load("spark/test/src/spark_test_data/expected_results_testReturnMaybe.csv")

    val df_actual_results = SparkJobs.testReturnMaybe(df_test_data)

    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testReturnRecord") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(new StructType()
        .add("min", DoubleType, true)
        .add("sum", DoubleType, false))
      .load("spark/test/src/spark_test_data/expected_results_testReturnRecord.csv")

    val df_actual_results = SparkJobs.testReturnRecord(df_age_test_data)

    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert(df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testReturnApplyRecord") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(new StructType()
        .add("min", DoubleType, true)
        .add("sum", DoubleType, false))
      .load("spark/test/src/spark_test_data/expected_results_testReturnApplyRecord.csv")

    val df_actual_results = SparkJobs.testReturnApplyRecord(df_age_test_data)

    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert(df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testReturnInlineApplyRecord") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(new StructType()
        .add("min", DoubleType, true)
        .add("sum", DoubleType, false))
      .load("spark/test/src/spark_test_data/expected_results_testReturnInlineApplyRecord.csv")

    val df_actual_results = SparkJobs.testReturnInlineApplyRecord(df_age_test_data)

    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert(df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }
}
