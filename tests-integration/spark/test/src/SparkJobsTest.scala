import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions.explode
import org.scalatest.FunSuite
import sparktests.functiontests.SparkJobs

class test1 extends FunSuite {

  val localTestSession =
    SparkSession.builder().master("local").appName("Example").getOrCreate()
  import localTestSession.implicits._

  val columns = Seq("firstName","lastName", "age")
  val data = Seq(("Jane", "Doe", 13), ("John", "Smith", 12))
  val rdd = localTestSession.sparkContext.parallelize(data)

  test("testFrom") {
      val dfFromRDD = rdd.toDF("firstName", "lastName", "age")
      val res = SparkJobs.testFrom(dfFromRDD)
      assert(res.count() == 2)
      assert(res.columns(0) == "firstName")
      assert(res.columns(1) == "lastName")
      assert(res.columns(2) == "age")
      val rows = res.collect()

      val row0 = rows(0)
      assert(row0(0) == "Jane")
      assert(row0(1) == "Doe")
      assert(row0(2) == 13)

      val row1 = rows(1)
      assert(row1(0) == "John")
      assert(row1(1) == "Smith")
      assert(row1(2) == 12)
    }

  test("testSelect1") {
      val dfFromRDD = rdd.toDF("firstName", "lastName", "age")
      val res = SparkJobs.testSelect1(dfFromRDD)
      assert(res.count() == 2)
      assert(res.columns(0) == "nickname")
      assert(res.columns(1) == "familyName")
      assert(res.columns(2) == "foo")

      val rows = res.collect()

      val row0 = rows(0)
      assert(row0(0) == "Jane")
      assert(row0(1) == "Doe")
      assert(row0(2) == "bar")

      val row1 = rows(1)
      assert(row1(0) == "John")
      assert(row1(1) == "Smith")
      assert(row1(2) == "baz")
    }

  test("testWhere1") {
      val dfFromRDD = rdd.toDF("firstName", "lastName", "age")
      val res = SparkJobs.testWhere1(dfFromRDD)
      assert(res.count() == 1)
      assert(res.columns(0) == "firstName")
      assert(res.columns(1) == "lastName")
      assert(res.columns(2) == "age")
      val rows = res.collect()

      val row0 = rows(0)
      assert(row0(0) == "Jane")
      assert(row0(1) == "Doe")
      assert(row0(2) == 13)
    }

  test("testWhere2") {
      val dfFromRDD = rdd.toDF("firstName", "lastName", "age")
      val res = SparkJobs.testWhere2(dfFromRDD)
      assert(res.count() == 1)
      assert(res.columns(0) == "firstName")
      assert(res.columns(1) == "lastName")
      assert(res.columns(2) == "age")
      val rows = res.collect()

      val row0 = rows(0)
      assert(row0(0) == "John")
      assert(row0(1) == "Smith")
      assert(row0(2) == 12)
    }
}


