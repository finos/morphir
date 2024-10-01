package org.finos.morphir.build

object V {

  val borer             = "1.14.1"
  val caliban           = "2.8.1"
  val cats              = "2.12.0"
  val `directories-jvm` = "26"
  val `case-app`        = "2.1.0-M29"
  val `graal-polyglot`  = "24.0.2"
  val iron              = "2.6.0"
  val `jsoniter-scala`  = "2.30.11"
  val `just-semver`     = "1.0.0"
  val kyo               = "0.12.0"
  val literally         = "1.2.0"
  val metaconfig        = "0.13.0"
  val oslib             = "0.10.6"
  val parsley           = "4.5.2"
  val pprint            = "0.9.0"
  val neotype           = "0.3.5"
  val `scala-uri`       = "4.0.3"
  val scribe            = "3.15.0"
  val scalatest         = "3.2.19"
  val t2                = "2.0.0"
  val utest             = "0.8.4"
  val zio               = "2.1.9"

  object Scala {
    val scala3LTSVersion       = "3.3.3"
    val scala3_4_version       = "3.4.3"
    val scala3_5_version       = "3.5.0"
    val scala3LatestVersion    = scala3_5_version
    val scala2Version          = "2.13.14"
    val libraryScalaVersion    = scala3LTSVersion
    val executableScalaVersion = scala3_5_version
  }

  object ScalaJS {
    val scalaJsVersion = "1.16.0"
  }
}
