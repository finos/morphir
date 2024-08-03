import mill._
import mill.scalalib._
import mill.scalalib.scalafmt._
import mill.scalalib.publish._
import mill.scalalib.api.ZincWorkerUtil._
import os.Path

import $ivy.`com.carlosedp::mill-aliases::0.4.1`
import com.carlosedp.aliases._
import $ivy.`de.tototec::de.tobiasroeser.mill.integrationtest::0.7.1`
import de.tobiasroeser.mill.integrationtest._
import $ivy.`com.goyeau::mill-scalafix::0.3.1`
import com.goyeau.mill.scalafix.ScalafixModule
import $ivy.`io.chris-kipp::mill-ci-release::0.1.9`
import io.kipp.mill.ci.release._
import de.tobiasroeser.mill.vcs.version.VcsVersion

val mill_0_11_10 = "0.11.10"
val millVersions = Seq(mill_0_11_10)

val scala213     = "2.13.14"
val pluginName   = "mill-morphir"

object plugin extends Cross[Plugin](millVersions) 
trait Plugin extends Cross.Module[String] with ScalaModule with Publish with ScalafmtModule with ScalafixModule {
   val millVersion  = crossValue
   def scalaVersion = scala213
   def artifactName = s"${pluginName}_mill${scalaNativeBinaryVersion(millVersion)}"
}

trait Publish extends CiReleaseModule {
    def pomSettings = PomSettings(
        description = "A mill plugin for working with Morphir projects and workspaces.",
        organization = "org.finos.morphir.buildtools",
        url = "https://github.com/finos/morphir/integrations/buildtools/mill-morphir",
        licenses = Seq(License.`Apache-2.0`),
        versionControl = VersionControl.github("finos", "morphir"),
        developers = Seq(
            Developer(
                "DamianReeves",
                "Damian Reeves",
                "https://github.com/DamianReeves",
            )
        ),
    )
    def publishVersion = VcsVersion.vcsState().format()
    def sonatypeHost   = Some(SonatypeHost.s01)
}

def ci(buildType:String) = T.command {
   plugin(mill_0_11_10).publishLocal()
}