package org.finos.morphir.build
import mill._
import mill.scalalib._
import mill.define.ExternalModule
import mill.define.Discover
object CI extends ExternalModule {
  lazy val millDiscover = mill.define.Discover[this.type]

  def isCI = T.input {
    val result = sys.env.getOrElse("CI", "false")
    Seq("true", "1", "yes").contains(result)
  }

}
