import $file.integrations.buildtools.`mill-morphir`.{build => mill_morphir}
import $file.scripts.build.keepachangelog, keepachangelog._
import mill._
import mill.scalalib._
import mill.scalalib.scalafmt._
import mill.scalalib.publish._

object integrations extends Module {
   object buildtools extends Module {
      object `mill-morphir` extends Module {
        def ci(buildType:String) = T.command {
           mill_morphir.ci(buildType)
        }
      }
   }
}

object apps extends ChangelogModule {}
