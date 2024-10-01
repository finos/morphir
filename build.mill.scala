package build
import $meta._
import mill._, scalalib._

import com.carlosedp.aliases._
import org.finos.morphir.build._
import org.finos.morphir.build.elm._


object `package` extends RootModule with Module {
    
  trait MorphirTests extends JavaModule with MorphirTestModule {
    def sources = super.sources() ++ Seq(T.workspace / "morphir" / "shared" / "testing" / "src").map(PathRef(_))
  }
}
