import mill._
import mill.runner.MillBuildRootModule
import mill.scalalib._

object build extends MillBuildRootModule {
  override def ivyDeps = Agg(
    ivy"de.tototec::de.tobiasroeser.mill.vcs.version::0.4.0",
    ivy"com.github.lolgab::mill-mima::0.1.1",
    ivy"com.lihaoyi::mill-contrib-buildinfo:${mill.api.BuildInfo.millVersion}",
    ivy"com.goyeau::mill-scalafix::0.4.0",
    ivy"io.github.alexarchambault.mill::mill-native-image::0.1.26",
    ivy"io.eleven19.mill::mill-crossbuild::0.3.0",
    ivy"com.carlosedp::mill-aliases::0.4.1",
  )

}
