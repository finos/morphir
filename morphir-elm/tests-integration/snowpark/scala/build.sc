// build.sc
import mill._
import scalalib._


object snowparkExample extends ScalaModule{
  def scalaVersion = "2.12.9"

  val paths = Seq(
    millSourcePath / os.up / "src" / "main" / "scala"
  )
  def sources = T.sources {
    paths.map(p => PathRef(p))
  }

  def ivyDeps = Agg(
    ivy"com.snowflake:snowpark:1.8.0",
    ivy"org.ini4j:ini4j:0.5.4",
    ivy"org.scala-lang.modules::scala-collection-compat:2.3.1"
  )
}
