import sparktests.listmembertests.SparkJobs
import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions.explode
import org.apache.spark.sql.types._
import org.scalatest.FunSuite


class listMemberTest extends FunSuite {

  val localTestSession =
    SparkSession.builder().master("local").appName("ReadCsv").getOrCreate()

  import localTestSession.implicits._

  val antique_product_schema = new StructType()
    .add("product", StringType, false)

  val antique_product_test_data = localTestSession.read.format("csv")
    .option("header", "true")
    .schema(antique_product_schema)
    .load("spark/test/src/spark_test_data/antique_product_data.csv")


  test("testEnumListMember") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(antique_product_schema)
      .load("spark/test/src/spark_test_data/expected_results_testEnumListMember.csv")
    
    val df_actual_results = SparkJobs.testEnumListMember(antique_product_test_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }


  val antique_age_schema = new StructType()
    .add("ageOfItem", FloatType, false)

  val antique_age_test_data = localTestSession.read.format("csv")
    .option("header", "true")
    .schema(antique_age_schema)
    .load("spark/test/src/spark_test_data/antique_age_data.csv")


  test("testIntListMember") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(antique_age_schema)
      .load("spark/test/src/spark_test_data/expected_results_testIntListMember.csv")
    
    val df_actual_results = SparkJobs.testIntListMember(antique_age_test_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  val antique_name_schema = new StructType()
    .add("name", StringType, false)

  val antique_name_test_data = localTestSession.read.format("csv")
    .option("header", "true")
    .schema(antique_name_schema)
    .load("spark/test/src/spark_test_data/antique_name_data.csv")


  test("testStringListMember") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(antique_name_schema)
      .load("spark/test/src/spark_test_data/expected_results_testStringListMember.csv")
    
    val df_actual_results = SparkJobs.testStringListMember(antique_name_test_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

 }

