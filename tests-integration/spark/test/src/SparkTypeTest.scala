import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions.explode
import org.scalatest.FunSuite
import sparktests.typetests.SparkJobs
import org.apache.spark.sql.types.{BooleanType, FloatType, IntegerType, StringType, StructField, StructType}
import org.apache.spark.sql.Row

class SparkTypeTest extends FunSuite {
  val localTestSession =
    SparkSession.builder().master("local").appName("Example").getOrCreate()
  import localTestSession.implicits._

  test("testBool") {
    val bad_value = true
    val good_value = false
    val data = Seq((bad_value), (good_value))
    val rdd = localTestSession.sparkContext.parallelize(data)
    val df = rdd.toDF("foo")
    val result = SparkJobs.testBool(df)
    assert(result.count() == 1)
    assert(result.collect()(0)(0) == good_value)
  }

  test("testFloat") {
    val bad_value = 12.34
    val good_value = 9.99
    val data = Seq((bad_value), (good_value))
    val rdd = localTestSession.sparkContext.parallelize(data)
    val df = rdd.toDF("foo")
    val result = SparkJobs.testFloat(df)
    assert(result.count() == 1)
    assert(result.collect()(0)(0) == good_value)
  }

  test("testInt") {
    val bad_value = 12
    val good_value = 13
    val data = Seq((bad_value), (good_value))
    val rdd = localTestSession.sparkContext.parallelize(data)
    val df = rdd.toDF("foo")
    val result = SparkJobs.testInt(df)
    assert(result.count() == 1)
    assert(result.collect()(0)(0) == good_value)
  }

  test("testMaybeFloat") {
    val data = Seq(Row(9.99f, "bax"), Row(5.55f, "bar"), Row(null, "baz"))
    val schema = StructType(List(
      StructField("foo", FloatType, true),
      StructField("bar", StringType, false),
    ))
    val rdd = localTestSession.sparkContext.parallelize(data)
    val df = localTestSession.createDataFrame(rdd, schema)
    val result = SparkJobs.testMaybeFloat(df)
    assert(result.count() == 2)
    assert(result.collect()(0)(0) == 9.99f)
    assert(result.collect()(1)(0) == 5.55f)
  }

  test("testMaybeInt") {
    val data = Seq(Row(13, "bax"), Row(8, "bar"), Row(null, "baz"))
    val schema = StructType(List(
      StructField("foo", IntegerType, true),
      StructField("bar", StringType, false),
    ))
    val rdd = localTestSession.sparkContext.parallelize(data)
    val df = localTestSession.createDataFrame(rdd, schema)
    val result = SparkJobs.testMaybeInt(df)
    assert(result.count() == 2)
    assert(result.collect()(0)(0) == 13)
    assert(result.collect()(1)(0) == 8)
  }

  test("testMaybeMapDefault") {
    val data = Seq(Row(null, "bax"), Row(true, "bay"), Row(false, "baz"))
    val schema = StructType(List(
      StructField("foo", BooleanType, true),
      StructField("bar", StringType, false),
    ))
    val rdd = localTestSession.sparkContext.parallelize(data)
    val df = localTestSession.createDataFrame(rdd, schema)
    val result = SparkJobs.testMaybeMapDefault(df)
    assert(result.count() == 1)
    assert(result.collect()(0)(0) == false)
    assert(result.collect()(0)(1) == "baz")
  }

  test("testMaybeBoolConditional") {
    val data = Seq(Row(null, "baz"), Row(true, "baz"))
    val schema = StructType(List(
      StructField("foo", BooleanType, true),
      StructField("bar", StringType, false),
    ))
    val rdd = localTestSession.sparkContext.parallelize(data)
    val df = localTestSession.createDataFrame(rdd, schema)
    val result = SparkJobs.testMaybeBoolConditional(df)
    assert(result.count() == 1)
    assert(result.collect()(0)(0) == true)
  }

  test("testMaybeBoolConditonalNull") {
    val data = Seq(Row(null, "baz"), Row(true, "baz"))
    val schema = StructType(List(
      StructField("foo", BooleanType, true),
      StructField("bar", StringType, false),
    ))
    val rdd = localTestSession.sparkContext.parallelize(data)
    val df = localTestSession.createDataFrame(rdd, schema)
    val result = SparkJobs.testMaybeBoolConditionalNull(df)
    assert(result.count() == 1)
    assert(result.collect()(0)(0) == null)
  }

  test("testMaybeBoolConditonalNotNull") {
    val data = Seq(Row(null, "baz"), Row(true, "baz"))
    val schema = StructType(List(
      StructField("foo", BooleanType, true),
      StructField("bar", StringType, false),
    ))
    val rdd = localTestSession.sparkContext.parallelize(data)
    val df = localTestSession.createDataFrame(rdd, schema)
    val result = SparkJobs.testMaybeBoolConditionalNotNull(df)
    assert(result.count() == 1)
    assert(result.collect()(0)(0) == true)
  }

  test("testMaybeString") {
    val data = Seq(Row("foo"), Row("bar"), Row(null))
    val schema = StructType(List(
      StructField("foo", StringType, true),
    ))
    val rdd = localTestSession.sparkContext.parallelize(data)
    val df = localTestSession.createDataFrame(rdd, schema)
    val result = SparkJobs.testMaybeString(df)
    assert(result.count() == 2)
    assert(result.collect()(0)(0) == "foo")
    assert(result.collect()(1)(0) == "bar")
  }

  test("testString") {
    val bad_value = "baz"
    val good_value = "bar"
    val data = Seq((bad_value), (good_value))
    val rdd = localTestSession.sparkContext.parallelize(data)
    val df = rdd.toDF("foo")
    val result = SparkJobs.testString(df)
    assert(result.count() == 1)
    assert(result.collect()(0)(0) == good_value)
  }

  test("testEnum") {
    val bad_value = "VP"
    val good_value = "ED"
    val data = Seq((bad_value), (good_value))
    val rdd = localTestSession.sparkContext.parallelize(data)
    val df = rdd.toDF("title")
    val result = SparkJobs.testEnum(df)
    assert(result.count() == 1)
    assert(result.collect()(0)(0) == good_value)
  }

}
