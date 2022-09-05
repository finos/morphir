import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions.explode
import org.apache.spark.sql.types._
import org.scalatest.FunSuite
import sparktests.typetests.SparkJobs
import org.apache.spark.sql.types.{BooleanType, DoubleType, IntegerType, StringType, StructField, StructType}
import org.apache.spark.sql.Row

class SparkTypeTest extends FunSuite {
  val localTestSession =
    SparkSession.builder().master("local").appName("Example").getOrCreate()
  import localTestSession.implicits._

  val foo_float_schema = new StructType()
    .add("foo", DoubleType, true)

  val foo_float_data = localTestSession.read.format("csv")
    .option("header", "true")
    .schema(foo_float_schema)
    .load("spark/test/src/spark_test_data/foo_float_data.csv")


  val foo_int_schema = new StructType()
    .add("foo", IntegerType, true)

  val foo_int_data = localTestSession.read.format("csv")
    .option("header", "true")
    .schema(foo_int_schema)
    .load("spark/test/src/spark_test_data/foo_int_data.csv")


  val foo_bool_schema = new StructType()
    .add("foo", BooleanType, true)

  val foo_bool_data = localTestSession.read.format("csv")
    .option("header", "true")
    .schema(foo_bool_schema)
    .load("spark/test/src/spark_test_data/foo_bool_data.csv")


  val foo_string_schema = new StructType()
    .add("foo", StringType, true)

  val foo_string_data = localTestSession.read.format("csv")
    .option("header", "true")
    .schema(foo_string_schema)
    .load("spark/test/src/spark_test_data/foo_string_data.csv")


  val product_schema = new StructType()
    .add("product", StringType, false)

  val product_data = localTestSession.read.format("csv")
    .option("header", "true")
    .schema(product_schema)
    .load("spark/test/src/spark_test_data/antique_product_data.csv")


//////////////////////////////////////////////////////////////////////////////

  test("testBool") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(foo_bool_schema)
      .load("spark/test/src/spark_test_data/expected_results_testBool.csv")
    
    val df_actual_results = SparkJobs.testBool(foo_bool_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }


  test("testInt") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(foo_int_schema)
      .load("spark/test/src/spark_test_data/expected_results_testInt.csv")
    
    val df_actual_results = SparkJobs.testInt(foo_int_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }


  test("testFloat") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(foo_float_schema)
      .load("spark/test/src/spark_test_data/expected_results_testFloat.csv")
    
    val df_actual_results = SparkJobs.testFloat(foo_float_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testString") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(foo_string_schema)
      .load("spark/test/src/spark_test_data/expected_results_testString.csv")
    
    val df_actual_results = SparkJobs.testString(foo_string_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testEnum") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(product_schema)
      .load("spark/test/src/spark_test_data/expected_results_testEnum.csv")
    
    val df_actual_results = SparkJobs.testEnum(product_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testMaybeString") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(foo_string_schema)
      .load("spark/test/src/spark_test_data/expected_results_testMaybeString.csv")
    
    val df_actual_results = SparkJobs.testMaybeString(foo_string_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testMaybeInt") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(foo_int_schema)
      .load("spark/test/src/spark_test_data/expected_results_testMaybeInt.csv")
    
    val df_actual_results = SparkJobs.testMaybeInt(foo_int_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testMaybeFloat") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(foo_float_schema)
      .load("spark/test/src/spark_test_data/expected_results_testMaybeFloat.csv")
    
    val df_actual_results = SparkJobs.testMaybeFloat(foo_float_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testMaybeBoolConditional") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(foo_bool_schema)
      .load("spark/test/src/spark_test_data/expected_results_testMaybeBoolConditional.csv")
    
    val df_actual_results = SparkJobs.testMaybeBoolConditional(foo_bool_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testMaybeBoolConditionalNull") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(foo_bool_schema)
      .load("spark/test/src/spark_test_data/expected_results_testMaybeBoolConditionalNull.csv")
    
    val df_actual_results = SparkJobs.testMaybeBoolConditionalNull(foo_bool_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testMaybeBoolConditionalNotNull") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(foo_bool_schema)
      .load("spark/test/src/spark_test_data/expected_results_testMaybeBoolConditionalNotNull.csv")
    
    val df_actual_results = SparkJobs.testMaybeBoolConditionalNotNull(foo_bool_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testMaybeMapDefault") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(foo_bool_schema)
      .load("spark/test/src/spark_test_data/expected_results_testMaybeMapDefault.csv")
    
    val df_actual_results = SparkJobs.testMaybeMapDefault(foo_bool_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

}
