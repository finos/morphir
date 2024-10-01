package build.morphir.lang.elm
import mill._, scalalib._
import io.eleven19.mill.crossbuild._
import org.finos.morphir.build._

object `package` extends RootModule with CrossPlatform {
    trait Shared extends ScalaLibraryModule with PlatformAwareScalaProject with MorphirLibraryPublishModule {
        def scalaVersion = V.Scala.scala3LTSVersion
    }

    object jvm extends ScalaJvmProject with Shared {
        
        override def ivyDeps = super.ivyDeps() ++ Agg(        
            // ivy"io.github.bonede:tree-sitter:${V.`tree-sitter-ng`}",
            // ivy"io.github.bonede:tree-sitter-elm:5.7.0a",    
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