package org.finos.morphir.build

object V {

  val borer            = "1.14.1"
  val cats             = "2.12.0"
  val `case-app`       = "2.1.0-M29"
  val `just-semver`    = "1.0.0"
  val kyo              = "0.11.1"
  val iron             = "2.6.0" 
  val metaconfig       = "0.13.0" 
  val oslib            = "0.10.4"
  val pprint           = "0.9.0"
  val neotype          = "0.3.0"
  val `scala-uri`      = "4.0.3"
  val `graal-polyglot` = "24.0.2"
  val scalatest        = "3.2.19"
  val zio              = "2.1.9"

  object Scala {
    val scala3LTSVersion       = "3.3.3"
    val scala3_4_version       = "3.4.3"
    val scala3_5_version       = "3.5.0"
    val scala3LatestVersion   = scala3_5_version
    val scala2Version          = "2.13.14"     
    val libraryScalaVersion    = scala3LTSVersion
    val executableScalaVersion = scala3_5_version
  }

  object ScalaJS {
    val scalaJsVersion = "1.16.0"
  }
}