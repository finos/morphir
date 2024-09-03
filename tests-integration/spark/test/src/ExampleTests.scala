import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions.explode
import org.scalatest.FunSuite

case class School(id: String, name: String)
case class Student(firstName: String, lastname: String, email: String, age: Int)
case class SchoolWithStudents(school: School, students: Seq[Student])

class test extends FunSuite {
  val localTestSession =
    SparkSession.builder().master("local").appName("Example").getOrCreate()
  import localTestSession.implicits._

  val school = School("1234", "Eaton Square")
  val student = Student("John", "Clark", "john@mail.com", 18)
  val schoolWithStudents = SchoolWithStudents(school, Seq(student))
  val schoolWithStudentsSeq = Seq(schoolWithStudents)

  test("test initializing spark context") {
    val list = List(1, 2, 3, 4)
    val rdd = localTestSession.sparkContext.parallelize(list)

    assert(rdd.count === list.length)
  }

  test("First colunm should be John") {
    val df1 = schoolWithStudentsSeq.toDF()
    val explodeDF = df1.select(explode($"students"))
    val flattenDF = explodeDF
      .select($"col.firstName")
      .filter($"firstName" === "John")
      .first()
      .get(0)

    assert(flattenDF === "John")
  }

}
