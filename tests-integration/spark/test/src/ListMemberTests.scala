import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions.explode
import org.scalatest.FunSuite
import sparktests.listmembertests.SparkJobs

class listMemberTest extends FunSuite {

  val localTestSession =
  SparkSession.builder().master("local").appName("ListMemberTest").getOrCreate()
  import localTestSession.implicits._

  val columns = Seq("name","ageOfItem", "product", "report")
  val data = Seq(("Bowie Knife", 20, "Knife", "Rusty blade"), ("Upright Chair", 19, "Furniture", "Chipped legs"))
  val rdd = localTestSession.sparkContext.parallelize(data)

    test("testEnumListMember") {
      val dfFromRDD = rdd.toDF("name","ageOfItem", "product", "report")
      val res = SparkJobs.testEnumListMember(dfFromRDD)
      assert(res.count() == 1)
      assert(res.columns(0) == "name")
      assert(res.columns(1) == "ageOfItem")
      assert(res.columns(2) == "product")
      assert(res.columns(3) == "report")
      val rows = res.collect()

      val row0 = rows(0)
      assert(row0(0) == "Bowie Knife")
      assert(row0(1) == 20)
      assert(row0(2) == "Knife")
      assert(row0(3) == "Rusty blade")
    }
    
    test("testStringListMember") {
      val dfFromRDD = rdd.toDF("name","ageOfItem", "product", "report")
      val res = SparkJobs.testStringListMember(dfFromRDD)
      assert(res.count() == 1)
      assert(res.columns(0) == "name")
      assert(res.columns(1) == "ageOfItem")
      assert(res.columns(2) == "product")
      assert(res.columns(3) == "report")
      val rows = res.collect()

      val row0 = rows(0)
      assert(row0(0) == "Upright Chair")
      assert(row0(1) == 19)
      assert(row0(2) == "Furniture")
      assert(row0(3) == "Chipped legs")
    }
    
    test("testIntListMember") {
      val dfFromRDD = rdd.toDF("name","ageOfItem", "product", "report")
      val res = SparkJobs.testIntListMember(dfFromRDD)
      assert(res.count() == 2)
      assert(res.columns(0) == "name")
      assert(res.columns(1) == "ageOfItem")
      assert(res.columns(2) == "product")
      assert(res.columns(3) == "report")
      val rows = res.collect()

      val row0 = rows(0)
      assert(row0(0) == "Bowie Knife")
      assert(row0(1) == 20)
      assert(row0(2) == "Knife")
      assert(row0(3) == "Rusty blade")

      val row1 = rows(1)
      assert(row1(0) == "Upright Chair")
      assert(row1(1) == 19)
      assert(row1(2) == "Furniture")
      assert(row1(3) == "Chipped legs")
    }
}

