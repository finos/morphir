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
import sparktests.aggregationtests.SparkJobs

class aggregationTest extends FunSuite {

  val localTestSession =
    SparkSession.builder().master("local").appName("ReadCsv").getOrCreate()

  import localTestSession.implicits._

  val schema = new StructType()
    .add("category", StringType, true)
    .add("product", StringType, false)
    .add("priceValue", DoubleType, false)
    .add("ageOfItem", DoubleType, false)
    .add("handMade", BooleanType, false)
    .add("requiresExpert", BooleanType, false)
    .add("expertFeedBack", StringType, true)
    .add("report", StringType, true)

  val df_test_data = localTestSession.read.format("csv")
    .option("header", "true")
    .schema(schema)
    .load("spark/test/src/spark_test_data/antiques_data.csv")

  test("aggregateAverage") {
    val out_schema = new StructType()
      .add("product", StringType, false)
      .add("average", DoubleType, false)
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(out_schema)
      .load("spark/test/src/spark_test_data/expected_results_testAggregateAverage.csv")

    val df_actual_results = SparkJobs.testAggregateAverage(df_test_data)

    df_actual_results.show(false)
    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert(df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("aggregateCount") {
    val out_schema = new StructType()
      .add("product", StringType, false)
      .add("count", DoubleType, false)
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(out_schema)
      .load("spark/test/src/spark_test_data/expected_results_testAggregateCount.csv")

    val df_actual_results = SparkJobs.testAggregateCount(df_test_data)

    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert(df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("aggregateFilterAll") {
    val out_schema = new StructType()
      .add("product", StringType, false)
      .add("count", DoubleType, false)
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(out_schema)
      .load("spark/test/src/spark_test_data/expected_results_testAggregateFilterAll.csv")

    val df_actual_results = SparkJobs.testAggregateFilterAll(df_test_data)

    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert(df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }
  
  test("aggregateFilterOneCount") {
    val out_schema = new StructType()
      .add("product", StringType, false)
      .add("all", DoubleType, false)
      .add("vintage", DoubleType, false)

    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(out_schema)
      .load("spark/test/src/spark_test_data/expected_results_testAggregateFilterOneCount.csv")

    val df_actual_results = SparkJobs.testAggregateFilterOneCount(df_test_data)

    df_expected_results.printSchema()
    df_expected_results.show(false)
    df_actual_results.printSchema()
    df_actual_results.show(false)

    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert(df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("aggregateFilterOneMin") {
    val out_schema = new StructType()
      .add("product", StringType, false)
      .add("youngest_qualifying", DoubleType, false)

    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(out_schema)
      .load("spark/test/src/spark_test_data/expected_results_testAggregateFilterOneMin.csv")

    val df_actual_results = SparkJobs.testAggregateFilterOneMin(df_test_data)

    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert(df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("aggregateSum") {
    val out_schema = new StructType()
      .add("product", StringType, false)
      .add("sum", DoubleType, false)
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(out_schema)
      .load("spark/test/src/spark_test_data/expected_results_testAggregateSum.csv")

    val df_actual_results = SparkJobs.testAggregateSum(df_test_data)

    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert(df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("aggregateMaximum") {
    val out_schema = new StructType()
      .add("product", StringType, false)
      .add("maximum", DoubleType, false)
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(out_schema)
      .load("spark/test/src/spark_test_data/expected_results_testAggregateMaximum.csv")

    val df_actual_results = SparkJobs.testAggregateMaximum(df_test_data)

    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert(df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("aggregateMinimum") {
    val out_schema = new StructType()
      .add("product", StringType, false)
      .add("minimum", DoubleType, false)
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(out_schema)
      .load("spark/test/src/spark_test_data/expected_results_testAggregateMinimum.csv")

    val df_actual_results = SparkJobs.testAggregateMinimum(df_test_data)

    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert(df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

}


