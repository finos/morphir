package org.finos.morphir.build

import mill._
import mill.scalalib._
import de.tobiasroeser.mill.vcs.version.{VcsVersion, VcsState}
import com.github.lolgab.mill.mima._
import coursier.ivy.Pattern.Chunk.Opt

trait PubMod extends PublishModule with JavaModule with Mima {
  import mill.scalalib.publish._

  def publishVersion = versionHead() + versionSuffix()

  def customVersionTag: T[Option[String]] = T(None)

  def versionHead = T {
    val vcsState = VcsVersion.vcsState()
    val tag      = customVersionTag().orElse(vcsState.lastTag).getOrElse("0.0.0")
    tagModifier(vcsState, tag)
  }

  def versionSuffix = T {
    val vcsState = VcsVersion.vcsState()
    calcVcsSuffix(vcsState)()
  }

  def packageDescription: String =
    s"Morphir provides a set of tools and languages for building and working with domain-specific languages (DSLs). "
  def pomSettings = PomSettings(
    description = packageDescription,
    organization = "org.finos.morphir",
    url = "https://github.com/finos/morphir",
    licenses = Seq(License.`Apache-2.0`),
    versionControl = VersionControl.github("finos", "morphir"),
    developers = Seq(
      Developer(
        "DamianReeves",
        "Damian Reeves",
        "https://github.com/damianreeves"
      )
    )
  )

  def tagModifier(vcsState: VcsState, tag: String): String = vcsState.stripV(tag)

  def calcVcsSuffix(vcsState: VcsState)(
    countSep: String = "-",
    commitCountPad: Byte = 0,
    revSep: String = "-",
    revHashDigits: Int = 6,
    dirtySep: String = "-DIRTY",
    dirtyHashDigits: Int = 8,
    untaggedSuffix: String = ""
  ): String = {
    import vcsState._
    val isUntagged = lastTag.isEmpty || commitsSinceLastTag > 0

    val commitCountPart = if (isUntagged)
      s"$countSep${
          if (commitCountPad > 0)
            (10000000000000L + commitsSinceLastTag).toString().substring(14 - commitCountPad, 14)
          else if (commitCountPad == 0) commitsSinceLastTag
          else ""
        }"
    else ""

    val revisionPart = if (isUntagged)
      s"$revSep${currentRevision.take(revHashDigits)}"
    else ""

    val dirtyPart = dirtyHash match {
      case None    => ""
      case Some(d) => dirtySep + d.take(dirtyHashDigits)
    }

    val snapshotSuffix = if (isUntagged) untaggedSuffix else ""

    s"$commitCountPart$revisionPart$dirtyPart$snapshotSuffix"
  }
}