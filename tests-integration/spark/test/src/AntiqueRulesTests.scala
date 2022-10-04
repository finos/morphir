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
import sparktests.antiquerulestests.SparkJobs
import sparktests.rules.income.antique.SparkJobs.report

class antiqueRulesTest extends FunSuite {

  val localTestSession =
    SparkSession.builder().master("local").appName("ReadCsv").getOrCreate()

  import localTestSession.implicits._

  val schema = new StructType()
    .add("category", StringType, true)
    .add("product", StringType, false)
    .add("priceValue",DoubleType, false)
    .add("ageOfItem", DoubleType, false)
    .add("handMade", BooleanType, false)
    .add("requiresExpert", BooleanType, false)
    .add("expertFeedBack", StringType, true)
    .add("report", StringType, true)

  val df_test_data = localTestSession.read.format("csv")
    .option("header", "true")
    .schema(schema)
    .load("spark/test/src/spark_test_data/antiques_data.csv")


  test("antiqueItems") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(schema)
      .load("spark/test/src/spark_test_data/expected_results_is_item_antique.csv")

    val df_actual_results = SparkJobs.antiqueItems(df_test_data)

    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("vintageItems") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(schema)
      .load("spark/test/src/spark_test_data/expected_results_is_item_vintage.csv")

    val df_actual_results = SparkJobs.vintageItems(df_test_data)

    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("worthThousandsItems") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(schema)
      .load("spark/test/src/spark_test_data/expected_results_is_item_worth_thousands.csv")

    val df_actual_results = SparkJobs.worthThousandsItems(df_test_data)

    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("worthMillionsItems") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(schema)
      .load("spark/test/src/spark_test_data/expected_results_is_item_worth_millions.csv")

    val df_actual_results = SparkJobs.worthMillionsItems(df_test_data)

    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("seizedItems") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(schema)
      .load("spark/test/src/spark_test_data/expected_results_seize_item.csv")

    val df_actual_results = SparkJobs.seizedItems(df_test_data)

    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("report") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(new StructType()
        .add("antiqueValue", DoubleType, false)
        .add("seizedValue", DoubleType, false)
        .add("vintageValue", DoubleType, false))
      .load("spark/test/src/spark_test_data/expected_results_testAntiqueReport.csv")

    val df_actual_results = report(df_test_data)

    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert(df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }
}


