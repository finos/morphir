// build.sc
import mill._, scalalib._

object generated extends Module {
  object refModel extends Module {
    object spark extends ScalaModule {
      def scalaVersion = "2.12.12"
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
  def ivyDeps = Agg(
    ivy"org.apache.spark::spark-core:3.2.1",
    ivy"org.apache.spark::spark-sql:3.2.1",
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