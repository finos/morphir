package build.morphir.std 
import mill._, scalalib._
import build._
import org.finos.morphir.build._
import org.finos.morphir.build.elm._
import io.eleven19.mill.crossbuild._

object `package` extends RootModule with CrossPlatform {

    trait Shared extends ScalaLibraryModule with PlatformAwareScalaProject with MorphirLibraryPublishModule {
      def scalaVersion = V.Scala.scala3LTSVersion
    }

    object jvm extends ScalaJvmProject with Shared {
        
        override def ivyDeps = super.ivyDeps() ++ Agg(
            ivy"dev.dirs:directories:${V.`directories-jvm`}"
        )
    
        object test extends ScalaTests with TestModule.Utest {
            def ivyDeps = super.ivyDeps() ++ Agg(
                ivy"com.lihaoyi::utest:${V.utest}",
                ivy"io.github.kitlangton::neotype-jsoniter:0.3.5",
                ivy"com.github.plokhotnyuk.jsoniter-scala::jsoniter-scala-macros:${V.`jsoniter-scala`}"
            )
        }
    }
}
