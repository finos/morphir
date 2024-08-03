import $ivy.`cx.cad.keepachangelog:changelog-parser:0.1.3`

import mill._ 
import mill.scalalib._
import cx.cad.keepachangelog.ChangelogParser
import com.github.zafarkhaja.semver.Version 

import upickle.default.{ReadWriter => RW, readwriter, macroRW}

trait ChangelogModule extends Module {    
    def changelogFileName: T[String] = T {
        "CHANGELOG.md"
    }

    def changelogContents = T {
        val path = changelogPath().path
        if(os.exists(path)) {
            Option(os.read(path))
        } else {
            None
        }        
    }

    def changelogPath: T[PathRef] = T.source { 
        discoverChangeLogPath() getOrElse PathRef(T.ctx().workspace / "CHANGELOG.md") 
    }

    def discoverChangeLogPath = T.input {
        var changelogPath: Option[os.Path] = None
        var candidateDir = millSourcePath        
        do {
            val candidatePath = candidateDir / changelogFileName()
            if (os.exists(candidatePath)) {
                changelogPath = Some(candidatePath)
            } else {
                candidateDir = candidateDir/os.up
            }
        } while (!shouldTerminate(changelogPath, candidateDir, discoveryTerminator()))
        changelogPath.map(PathRef(_))                
    }

    def discoveryTerminator: T[ChangeLogPathDiscoveryTerminator] = T {
        ChangeLogPathDiscoveryTerminator.GitRoot
    }

    protected def shouldTerminate(maybeChangelogPath: Option[os.Path], candidateDir: os.Path, terminator: ChangeLogPathDiscoveryTerminator): Boolean = {
        maybeChangelogPath match {
            case Some(changelogPath) => true
            case None => terminator match {
                case ChangeLogPathDiscoveryTerminator.Root => candidateDir.segments.length == 0
                case ChangeLogPathDiscoveryTerminator.GitRoot => os.exists(candidateDir / ".git")
                case ChangeLogPathDiscoveryTerminator.File(name) => os.exists(candidateDir / name) && os.isFile(candidateDir / name)
                case ChangeLogPathDiscoveryTerminator.Dir(name) => os.exists(candidateDir / name) && os.isDir(candidateDir / name)
            }
        }        
    }
}

sealed abstract class ChangeLogPathDiscoveryTerminator extends Product with Serializable
object ChangeLogPathDiscoveryTerminator {    
    implicit val rw: RW[ChangeLogPathDiscoveryTerminator] = RW.merge(
        Root.rw,
        GitRoot.rw,
        File.rw,
        Dir.rw
    )

    type Root = Root.type
    case object Root extends ChangeLogPathDiscoveryTerminator {
        implicit lazy val rw: RW[Root] = macroRW
    }
    
    type GitRoot = GitRoot.type
    case object GitRoot extends ChangeLogPathDiscoveryTerminator {
        implicit lazy val rw: RW[GitRoot] = macroRW
    }
    
    case class File(name: String) extends ChangeLogPathDiscoveryTerminator
    object File {
        implicit val rw: RW[File] = macroRW
    }

    case class Dir(name: String) extends ChangeLogPathDiscoveryTerminator
    object Dir {
        implicit val rw: RW[Dir] = macroRW
    }
}

case class SemVer(underlying:Version)
object SemVer {
    def parseUnsafe(versionStr:String):SemVer = {
        SemVer(Version.valueOf(versionStr))
    }

    implicit val rw:RW[SemVer] = readwriter[String].bimap[SemVer](
        _.underlying.toString, 
        parseUnsafe(_)
    )
}