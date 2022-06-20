import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions.explode
import org.scalatest.FunSuite
import sparktests.typetests.SparkJobs
import org.apache.spark.sql.types.{BooleanType, StringType, StructField, StructType}
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
