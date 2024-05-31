import mill._, scalalib._, scalajslib._
import mill.scalajslib.api._

object root extends RootModule with ScalaJSModule {
  def scalaVersion = "3.4.2"
  def scalaJSVersion = "1.16.0"
  def moduleKind = ModuleKind.ESModule

}
