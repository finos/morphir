import mill._, scalalib._, scalajslib._, scalanativelib._, publish._
import $ivy.`io.eleven19.mill::mill-crossbuild::0.1.0`
import io.eleven19.mill.crossbuild._

object morphir extends CrossPlatform {
  object cdk extends CrossPlatform {
    trait Shared extends ScalaProject with PlatformScalaModule {
      def ivyDeps =
        Agg(Deps.dev.zio.`izumi-reflect`, Deps.io.github.kitlangton.neotype)
    }
    object jvm extends Shared {
      object test extends ScalaTests with TestModule.ZioTest {
        def ivyDeps = Agg(
          Deps.dev.zio.`zio-test`,
          Deps.dev.zio.`zio-test-sbt`
        )
      }
    }
    object js extends Shared with ScalaJSProject {
      object test extends ScalaJSTests with TestModule.ZioTest {
        def ivyDeps = Agg(
          Deps.dev.zio.`zio-test`,
          Deps.dev.zio.`zio-test-sbt`
        )
      }
    }
  }

  object rdf extends CrossPlatform {
    trait Shared extends ScalaProject with PlatformScalaModule
    object jvm extends Shared {
      object test extends ScalaTests with TestModule.ZioTest {
        def ivyDeps = Agg(
          Deps.dev.zio.`zio-test`,
          Deps.dev.zio.`zio-test-sbt`
        )
      }
    }
    object js extends Shared with ScalaJSProject {
      object test extends ScalaJSTests with TestModule.ZioTest {
        def ivyDeps = Agg(
          Deps.dev.zio.`zio-test`,
          Deps.dev.zio.`zio-test-sbt`
        )
      }
    }
  }

  object rdk extends CrossPlatform {
    trait Shared extends ScalaProject with PlatformScalaModule
    object jvm extends Shared {
      def moduleDeps = Seq(morphir.cdk.jvm)
      object test extends ScalaTests with TestModule.ZioTest {
        def ivyDeps = Agg(
          Deps.dev.zio.`zio-test`,
          Deps.dev.zio.`zio-test-sbt`
        )
      }
    }
    object js extends Shared with ScalaJSProject {

      def moduleDpes = Seq(morphir.cdk.js)
    }
  }

  trait Shared extends ScalaProject with PlatformScalaModule
  object jvm extends Shared
  object js extends Shared with ScalaJSProject
}

trait ScalaProject extends ScalaModule {
  def scalaVersion = Versions.scala
}

trait ScalaJSProject extends ScalaJSModule {
  def scalaJSVersion = Versions.scalaJS
}

//---------------------------------------------------------------------
// Dependencies and Versions
//---------------------------------------------------------------------
object Deps {
  case object dev {
    case object zio {
      val `izumi-reflect` =
        ivy"dev.zio::izumi-reflect::${Versions.`izumi-reflect`}"
      val zio: Dep = ivy"dev.zio::zio::${Versions.zio}"
      val `zio-cli` = ivy"dev.zio::zio-cli::${Versions.`zio-cli`}"
      val `zio-config` = config()
      val `zio-interop-cats` =
        ivy"dev.zio::zio-interop-cats::${Versions.`zio-interop-cats`}"
      val `zio-json`: Dep = ivy"dev.zio::zio-json::${Versions.`zio-json`}"
      val `zio-json-golden` =
        ivy"dev.zio::zio-json-golden::${Versions.`zio-json`}"
      val `zio-parser` = ivy"dev.zio::zio-parser::${Versions.`zio-parser`}"
      val `zio-nio` = ivy"dev.zio::zio-nio::${Versions.`zio-nio`}"
      val `zio-prelude` = prelude()
      val `zio-prelude-macros` = prelude.macros
      val `zio-process` = ivy"dev.zio::zio-process::${Versions.`zio-process`}"
      val `zio-streams` = ivy"dev.zio::zio-streams::${Versions.zio}"
      val `zio-test` = ivy"dev.zio::zio-test::${Versions.zio}"
      val `zio-test-magnolia` = ivy"dev.zio::zio-test-magnolia::${Versions.zio}"
      val `zio-test-sbt` = ivy"dev.zio::zio-test-sbt::${Versions.zio}"

      object config {
        def apply(): Dep = ivy"dev.zio::zio-config::${Versions.`zio-config`}"
        val magnolia =
          ivy"dev.zio::zio-config-magnolia::${Versions.`zio-config`}"
        val refined = ivy"dev.zio::zio-config-refined::${Versions.`zio-config`}"
        val typesafe =
          ivy"dev.zio::zio-config-typesafe::${Versions.`zio-config`}"
      }

      case object prelude {
        def apply(): Dep = ivy"dev.zio::zio-prelude::${Versions.`zio-prelude`}"
        val macros = ivy"dev.zio::zio-prelude-macros::${Versions.`zio-prelude`}"
      }

      case object schema {
        val `avro` = ivy"dev.zio::zio-schema-avro::${Versions.`zio-schema`}"
        val `bson` = ivy"dev.zio::zio-schema-bson::${Versions.`zio-schema`}"
        val `core` = ivy"dev.zio::zio-schema-core::${Versions.`zio-schema`}"
        val `derivation` =
          ivy"dev.zio::zio-schema-derivation::${Versions.`zio-schema`}"
        val `json` = ivy"dev.zio::zio-schema-json::${Versions.`zio-schema`}"
        val `msg-pack` =
          ivy"dev.zio::zio-schema-msg-pack::${Versions.`zio-schema`}"
      }
    }
  }

  case object io {
    case object github {
      case object kitlangton {
        val `neotype` = ivy"io.github.kitlangton::neotype::${Versions.neotype}"

      }
    }
  }

  case object org {
    case object wvlet {
      case object airframe {
        val `airframe-surface` =
          ivy"org.wvlet.airframe::airframe-surface:${Versions.airframe}"
      }
    }
  }
}

object Versions {
  val airframe = "24.4.0"
  val neotype = "0.2.5"
  val `izumi-reflect` = "2.3.8"
  val scala = "3.3.3"
  val scalaJS = "1.16.0"
  val zio = "2.0.21"
  val `zio-cli` = "0.5.0"
  val `zio-config` = "4.0.1"
  val `zio-interop-cats` = "23.1.0.1"
  val `zio-json` = "0.6.2"
  val `zio-nio` = "2.0.2"
  val `zio-parser` = "0.1.9"
  val `zio-prelude` = "1.0.0-RC23"
  val `zio-process` = "0.7.2"
  val `zio-schema` = "0.4.12"
}
