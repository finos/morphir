package build.morphir.ir
import mill._, scalalib._
import io.eleven19.mill.crossbuild._
import org.finos.morphir.build._

object `package` extends RootModule {

  val crossVersions = Seq(V.Scala.scala3LTSVersion, V.Scala.scala2Version)

  object core extends Cross[CoreCross](crossVersions)

  trait CoreCross extends Cross.Module[String] with CrossPlatform {
    trait Shared extends PlatformAwareCrossScalaProject with CrossValue {
      def ivyDeps = Agg(
        ivy"org.scala-lang.modules::scala-collection-contrib:${V.`scala-collection-contrib`}"
      )

    }
    object jvm extends CrossScalaJvmProject with Shared {
      def ivyDeps = super.ivyDeps() ++ Agg(
        ivy"com.47deg::memeid4s:${V.memeid4s}"
      )

      def moduleDeps = Seq(build.morphir.sdk.core(crossValue).jvm)

      object test extends ScalaTests with TestModule.ZioTest {
        def ivyDeps = Agg(
          ivy"dev.zio::zio-test:${V.zio}",
          ivy"dev.zio::zio-test-sbt:${V.zio}"
        )
      }
    }
  }

  object `jsoniter-scala` extends Cross[JsoniterScalaModule](crossVersions)
  trait JsoniterScalaModule extends Cross.Module[String] {
    object core extends CrossPlatform with CrossValue { jsonitorScalaCore =>
      trait Shared extends PlatformAwareCrossScalaProject with CrossValue {
        def ivyDeps = super.ivyDeps() ++ Agg(
          ivy"com.github.plokhotnyuk.jsoniter-scala::jsoniter-scala-core::${V.`jsoniter-scala`}"
        )

        def compileIvyDeps = super.compileIvyDeps() ++ Agg(
          ivy"com.github.plokhotnyuk.jsoniter-scala::jsoniter-scala-macros::${V.`jsoniter-scala`}"
        )

        def platformSpecificModuleDeps = Seq(build.morphir.ir.core(crossValue))
      }

      object jvm extends CrossScalaJvmProject with Shared {
        // def moduleDeps = super.moduleDeps ++ Seq(build.morphir.sdk.core(crossValue).jvm)

        object test extends ScalaTests with TestModule.ZioTest {
          def ivyDeps = super.ivyDeps() ++ Agg(
            ivy"dev.zio::zio-test:${V.zio}",
            ivy"dev.zio::zio-test-sbt:${V.zio}"
          )

          def compileIvyDeps = super.compileIvyDeps() ++ Agg(
            ivy"com.github.plokhotnyuk.jsoniter-scala::jsoniter-scala-macros::${V.`jsoniter-scala`}"
          )
        }
      }
    }
  }
}
