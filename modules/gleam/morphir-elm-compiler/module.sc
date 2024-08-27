import mill._, scalalib._ 
import org.finos.morphir.build._ 

object compiler extends RootModule with MorphirBaseProject {
    def restore = T {
        T.log.info("Restoring dependencies")
    }
}