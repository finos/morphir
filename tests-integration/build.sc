// build.sc
import mill._
import scalalib._

object generated extends Module {
  object sparkModel extends Module {
    object spark extends ScalaModule {
        def scalaVersion = "2.12.12"
        val paths = Seq(
          millSourcePath / os.up / "src" / "spark" / "sparktests"
        )
        def sources = T.sources {
          paths.map(p => PathRef(p))
        }
        def ivyDeps = Agg(
          ivy"org.morphir::morphir-sdk-core:0.6.1",
          ivy"org.apache.spark::spark-core:3.2.1",
          ivy"org.apache.spark::spark-sql:3.2.1",
          ivy"org.scalatest::scalatest:3.0.2"

        )
    }
  }
}
object spark extends ScalaModule {
  def scalaVersion = "2.12.12"
  def moduleDeps = Seq(generated.sparkModel.spark)
  def ivyDeps = Agg(
    ivy"org.apache.spark::spark-core:3.2.1",
    ivy"org.apache.spark::spark-sql:3.2.1"
  )

  object test extends Tests {
    def ivyDeps = Agg(
      ivy"org.apache.spark::spark-core:3.2.1",
      ivy"org.apache.spark::spark-sql:3.2.1",
      ivy"org.scalatest::scalatest:3.0.2"
    )
    def testFrameworks = Seq("org.scalatest.tools.Framework")
  }
}


object codecs extends ScalaModule{
  def scalaVersion = "2.12.12"

  def ivyDeps = Agg(
    ivy"io.circe::circe-core:0.14.1",
    ivy"org.scala-lang.modules::scala-collection-compat:2.3.1"
  )
}
