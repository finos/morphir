import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions.explode

case class School(id: String, name: String)
case class Student(firstName: String, lastname: String, email: String, age: Int)
case class SchoolWithStudents(school: School, students: Seq[Student])

object Example extends App {
  val spark =
    SparkSession.builder().master("local").appName("Example").getOrCreate()
  import spark.implicits._

  val school = School("1234", "Eaton Square")

  val student1 = Student("John", "Clark", "john@mail.com", 18)
  val student2 = Student("Thomas", "Kent", "thomas@mail.com", 19)
  val student3 = Student("Lewis", "Hamilton", "lewis@mail.com", 20)
  val student4 = Student("Max", "Verstappen", "max@mail.com", 20)

  val schoolWithStudents =
    SchoolWithStudents(school, Seq(student1, student2, student3, student4))

  //creating dataframe
  val schoolWithStudentsSeq = Seq(schoolWithStudents)

  val df1 = schoolWithStudentsSeq.toDF()
  df1.show()

  //flatten employee class into columns
  val explodeDF = df1.select(explode($"students"))
  explodeDF.show()

  val flattenDF = explodeDF.select($"col.*")
  flattenDF.show()

  //filter rows
  val filterDF =
    flattenDF.filter($"firstName" === "Lewis").sort($"lastName".asc)
  filterDF.show()

}
