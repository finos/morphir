package build.morphir.sdk
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
      object test extends ScalaTests with TestModule.ZioTest {
        def ivyDeps = Agg(
          ivy"dev.zio::zio-test:${V.zio}",
          ivy"dev.zio::zio-test-sbt:${V.zio}"
        )
      }
    }
  }
}
