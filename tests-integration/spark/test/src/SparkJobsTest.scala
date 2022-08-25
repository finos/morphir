import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions.explode
import org.scalatest.FunSuite
import sparktests.functiontests.SparkJobs

class test1 extends FunSuite {

  val localTestSession =
    SparkSession.builder().master("local").appName("Example").getOrCreate()
  import localTestSession.implicits._

  val columns = Seq("name","report", "ageOfItem", "product")
  val data = Seq(("Bowie Knife", "Rusty blade", 20.0, "Knife"), ("Wooden Chair", "Chipped legs", 19.0, "Furniture"))
  val rdd = localTestSession.sparkContext.parallelize(data)

  test("testCaseBool") {
    val df = localTestSession.sparkContext.parallelize(Seq(
      (true),
      (false),
    )).toDF("foo")
    val res = SparkJobs.testCaseBool(df)
    val rows = res.collect()
    assert(res.count() == 1)
    assert(rows(0)(0) == false)
  }

  test("testCaseEnum") {
      val dfFromRDD = rdd.toDF("name", "report", "ageOfItem", "product")
      val res = SparkJobs.testCaseEnum(dfFromRDD)
      val rows = res.collect()
      assert(res.count() == 1)
      assert(rows(0)(0) == "Wooden Chair")
      assert(rows(0)(1) == "Chipped legs")
      assert(rows(0)(2) == 19.0)
      assert(rows(0)(3) == "Furniture")
  }

  test("testCaseFloat") {
    val dfFromRDD = rdd.toDF("name", "report", "ageOfItem", "product")
    val res = SparkJobs.testCaseFloat(dfFromRDD)
    val rows = res.collect()
    assert(res.count() == 1)
    assert(rows(0)(0) == "Bowie Knife")
    assert(rows(0)(1) == "Rusty blade")
    assert(rows(0)(2) == 20.0)
    assert(rows(0)(3) == "Knife")
  }

  test("testCaseInt") {
    val df = localTestSession.sparkContext.parallelize(Seq(
      (20.0),
      (5.0),
    )).toDF("foo")
    val res = SparkJobs.testCaseInt(df)
    val rows = res.collect()
    assert(res.count() == 1)
    assert(rows(0)(0) == 20)
  }

  test("testCaseString") {
      val dfFromRDD = rdd.toDF("name", "report", "ageOfItem", "product")
      val res = SparkJobs.testCaseString(dfFromRDD)
      val rows = res.collect()
      assert(res.count() == 1)
      assert(rows(0)(0) == "Bowie Knife")
      assert(rows(0)(1) == "Rusty blade")
      assert(rows(0)(2) == 20.0)
      assert(rows(0)(3) == "Knife")
  }

  test("testFrom") {
      val dfFromRDD = rdd.toDF("name", "report", "ageOfItem", "product")
      val res = SparkJobs.testFrom(dfFromRDD)
      assert(res.count() == 2)
      assert(res.columns(0) == "name")
      assert(res.columns(1) == "report")
      assert(res.columns(2) == "ageOfItem")
      assert(res.columns(3) == "product")
      val rows = res.collect()

      val row0 = rows(0)
      assert(row0(0) == "Bowie Knife")
      assert(row0(1) == "Rusty blade")
      assert(row0(2) == 20.0)
      assert(row0(3) == "Knife")

      val row1 = rows(1)
      assert(row1(0) == "Wooden Chair")
      assert(row1(1) == "Chipped legs")
      assert(row1(2) == 19.0)
    }

  test("testListMinimum") {
    val dfFromRDD = rdd.toDF("name", "report", "ageOfItem", "product")
    val res = SparkJobs.testListMinimum(dfFromRDD)
    assert(res.count() == 1)
    assert(res.columns(0) == "min")
    assert(res.collect()(0)(0) == 19.0)
  }

  test("testListMaximum") {
    val dfFromRDD = rdd.toDF("name", "report", "ageOfItem", "product")
    val res = SparkJobs.testListMaximum(dfFromRDD)
    assert(res.count() == 1)
    assert(res.columns(0) == "max")
    assert(res.collect()(0)(0) == 20.0)
  }

  test("testNameMaximum") {
    val dfFromRDD = rdd.toDF("name", "report", "ageOfItem", "product")
    val res = SparkJobs.testNameMaximum(dfFromRDD)
    assert(res.count() == 1)
    assert(res.columns(0) == "max")
    assert(res.collect()(0)(0) == "Wooden Chair")
  }

  test("testSelect1") {
      val dfFromRDD = rdd.toDF("name", "report", "ageOfItem", "product")
      val res = SparkJobs.testSelect1(dfFromRDD)
      assert(res.count() == 2)
      assert(res.columns(0) == "foo")
      assert(res.columns(1) == "newName")
      assert(res.columns(2) == "newReport")
      assert(res.columns(3) == "product")

      val rows = res.collect()

      val row0 = rows(0)
      assert(row0(0) == "old")
      assert(row0(1) == "Bowie Knife")
      assert(row0(2) == "Rusty blade")
      assert(row0(3) == "Knife")

      val row1 = rows(1)
      assert(row1(0) == "new")
      assert(row1(1) == "Wooden Chair")
      assert(row1(2) == "Chipped legs")
      assert(row1(3) == "Furniture")
    }

  test("testWhere1") {
      val dfFromRDD = rdd.toDF("name", "report", "ageOfItem", "product")
      val res = SparkJobs.testWhere1(dfFromRDD)
      assert(res.count() == 1)
      assert(res.columns(0) == "name")
      assert(res.columns(1) == "report")
      assert(res.columns(2) == "ageOfItem")
      assert(res.columns(3) == "product")
      val rows = res.collect()

      val row0 = rows(0)
      assert(row0(0) == "Bowie Knife")
      assert(row0(1) == "Rusty blade")
      assert(row0(2) == 20.0)
      assert(row0(3) == "Knife")
    }

  test("testWhere2") {
      val dfFromRDD = rdd.toDF("name", "report", "ageOfItem", "product")
      val res = SparkJobs.testWhere2(dfFromRDD)
      assert(res.count() == 1)
      assert(res.columns(0) == "name")
      assert(res.columns(1) == "report")
      assert(res.columns(2) == "ageOfItem")
      assert(res.columns(3) == "product")
      val rows = res.collect()

      val row0 = rows(0)
      assert(row0(0) == "Wooden Chair")
      assert(row0(1) == "Chipped legs")
      assert(row0(2) == 19.0)
      assert(row0(3) == "Furniture")
    }

  test("testListSum") {
    val dfFromRDD = rdd.toDF("name", "report", "ageOfItem", "product")
    val res = SparkJobs.testListSum(dfFromRDD)
    assert(res.count() == 1)
    assert(res.columns(0) == "agesum")
    assert(res.collect()(0)(0) == 39)
  }

  test("testListLength") {
    val dfFromRDD = rdd.toDF("name", "report", "ageOfItem", "product")
    val res = SparkJobs.testListLength(dfFromRDD)
    assert(res.count() == 1)
    assert(res.columns(0) == "listlength")
    assert(res.collect()(0)(0) == 2)
  }
}


