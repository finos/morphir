import sparktests.functiontests.SparkJobs
import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions.explode
import org.apache.spark.sql.types._
import org.scalatest.FunSuite

class test1 extends FunSuite {

  val localTestSession =
    SparkSession.builder().master("local").appName("Example").getOrCreate()
  import localTestSession.implicits._


  val foo_float_schema = new StructType()
    .add("foo", FloatType, false)

  val foo_int_data = localTestSession.read.format("csv")
    .option("header", "true")
    .schema(foo_float_schema)
    .load("spark/test/src/spark_test_data/foo_int_data.csv")


  val foo_bool_schema = new StructType()
    .add("foo", BooleanType, false)

  val foo_bool_data = localTestSession.read.format("csv")
    .option("header", "true")
    .schema(foo_bool_schema)
    .load("spark/test/src/spark_test_data/foo_bool_data.csv")


  val antiqueSS_schema = new StructType()
    .add("name", StringType, false)
    .add("ageOfItem", FloatType, false)
    .add("product", StringType, false)
    .add("report", StringType, false)

  val antiqueSS_data = localTestSession.read.format("csv")
    .option("header", "true")
    .schema(antiqueSS_schema)
    .load("spark/test/src/spark_test_data/antique_subset_data.csv")


  val antiqueSS_select1_schema = new StructType()
    .add("newName", StringType, false)
    .add("newReport", StringType, false)
    .add("foo", StringType, false)
    .add("product", StringType, false)
  
  val antiqueSS_select3_schema = new StructType()
    .add("ageOfItem", FloatType, false)

  val antiqueSS_select4_schema = new StructType()
    .add("float", FloatType, false)
  
  val foo_string_schema = new StructType()
    .add("foo", StringType, false)
  
  val foo_int_schema = new StructType()
    .add("foo", IntegerType, false)
  
  val product_schema = new StructType()
    .add("product", StringType, false)

  //////////////////////////////////////////////////////////////////

  test("testCaseInt") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(foo_int_schema)
      .load("spark/test/src/spark_test_data/expected_results_testCaseInt.csv")
    
    val df_actual_results = SparkJobs.testCaseInt(foo_int_data)

 
    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testCaseString") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(antiqueSS_schema)
      .load("spark/test/src/spark_test_data/expected_results_testCaseString.csv")
    
    val df_actual_results = SparkJobs.testCaseString(antiqueSS_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testCaseEnum") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(antiqueSS_schema)
      .load("spark/test/src/spark_test_data/expected_results_testCaseEnum.csv")
    
    val df_actual_results = SparkJobs.testCaseEnum(antiqueSS_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testFrom") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(antiqueSS_schema)
      .load("spark/test/src/spark_test_data/expected_results_testFrom.csv")
    
    val df_actual_results = SparkJobs.testFrom(antiqueSS_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }


  test("testWhere1") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(antiqueSS_schema)
      .load("spark/test/src/spark_test_data/expected_results_testWhere1.csv")
    
    val df_actual_results = SparkJobs.testWhere1(antiqueSS_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }


  test("testWhere2") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(antiqueSS_schema)
      .load("spark/test/src/spark_test_data/expected_results_testWhere2.csv")
    
    val df_actual_results = SparkJobs.testWhere2(antiqueSS_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }


  test("testWhere3") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(antiqueSS_schema)
      .load("spark/test/src/spark_test_data/expected_results_testWhere3.csv")
    
    val df_actual_results = SparkJobs.testWhere3(antiqueSS_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testSelect1") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(antiqueSS_select1_schema)
      .load("spark/test/src/spark_test_data/expected_results_testSelect1.csv")
    
    val df_actual_results = SparkJobs.testSelect1(antiqueSS_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testSelect3") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(antiqueSS_select3_schema)
      .load("spark/test/src/spark_test_data/expected_results_testSelect3.csv")
    
    val df_actual_results = SparkJobs.testSelect3(antiqueSS_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testSelect4") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(antiqueSS_select4_schema)
      .load("spark/test/src/spark_test_data/expected_results_testSelect4.csv")
    
    val df_actual_results = SparkJobs.testSelect4(antiqueSS_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testFilter2") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(antiqueSS_schema)
      .load("spark/test/src/spark_test_data/expected_results_testFilter2.csv")
    
    val df_actual_results = SparkJobs.testFilter2(antiqueSS_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testListMinimum") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(foo_float_schema)
      .load("spark/test/src/spark_test_data/expected_results_testListMinimum.csv")
    
    val df_actual_results = SparkJobs.testListMinimum(antiqueSS_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testListMaximum") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(foo_float_schema)
      .load("spark/test/src/spark_test_data/expected_results_testListMaximum.csv")
    
    val df_actual_results = SparkJobs.testListMaximum(antiqueSS_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testNameMaximum") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(foo_string_schema)
      .load("spark/test/src/spark_test_data/expected_results_testNameMaximum.csv")
    
    val df_actual_results = SparkJobs.testNameMaximum(antiqueSS_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

 /// NOT CURRENTLY TRNASPILED IN TO SPARK CODE 
  // test("testBadAnnotation") {
  //   val df_expected_results = localTestSession.read.format("csv")
  //     .option("header", "true")
  //     .schema(product_schema)
  //     .load("spark/test/src/spark_test_data/expected_results_testBadAnnotation.csv")
    
  //   val df_actual_results = SparkJobs.testBadAnnotation(antiqueSS_data)

  //   df_expected_results.show(false)
  //   df_actual_results.show(false)
  //   assert(df_actual_results.columns.length == df_expected_results.columns.length)
  //   assert (df_actual_results.count == df_expected_results.count)
  //   assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  
  // }

  test("testLetBinding") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(antiqueSS_schema)
      .load("spark/test/src/spark_test_data/expected_results_testLetBinding.csv")
    
    val df_actual_results = SparkJobs.testLetBinding(antiqueSS_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testListSum") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(foo_float_schema)
      .load("spark/test/src/spark_test_data/expected_results_testListSum.csv")
    
    val df_actual_results = SparkJobs.testListSum(antiqueSS_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }

  test("testListLength") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(foo_int_schema)
      .load("spark/test/src/spark_test_data/expected_results_testListLength.csv")
    
    val df_actual_results = SparkJobs.testListLength(antiqueSS_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }
  test("testForLetDef") {
     val df_expected_results = localTestSession.read.format("csv")
        .option("header", "true")
        .schema(antiqueSS_schema)
        .load("spark/test/src/spark_test_data/expected_results_testLetDef.csv")
            
     val df_actual_results = SparkJobs.testLetDef(antiqueSS_data)

     assert(df_actual_results.columns.length == df_expected_results.columns.length)
     assert(df_actual_results.count == df_expected_results.count)
     assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)   

  }
}


