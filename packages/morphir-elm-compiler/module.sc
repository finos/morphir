import mill._
import org.finos.morphir.build.MorphirBaseProject

object compiler extends RootModule with MorphirBaseProject {
    def restore = T {
        T.log.info("Restoring dependencies")
    }
}