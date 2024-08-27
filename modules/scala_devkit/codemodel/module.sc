import mill._, scalalib._
import io.eleven19.mill.crossbuild._
import org.finos.morphir.build._

object build extends RootModule with CrossPlatform {
        trait Shared extends ScalaLibraryModule with PlatformAwareScalaProject with MorphirLibraryPublishModule {
          def artifactNameParts = Seq("morphir", "codemodel")
        }
        
        object jvm extends ScalaJvmProject with Shared {
          object test extends ScalaTests with TestModule.ScalaTest {
            def ivyDeps = Agg(
              ivy"org.scalatest::scalatest::3.2.19"
            )
          }
        }
}