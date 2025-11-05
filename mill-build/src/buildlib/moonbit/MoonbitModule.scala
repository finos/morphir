package buildlib.moonbit
import mill.* 
import mill.api.BuildCtx
import mill.scalalib.* 

trait MoonbitModule extends Module:
    def targetDir = Task { PathRef(Task.dest) }

    def build = Task {
        val targetDirPath = targetDir().path
        val cmd = Seq("moon", "build", "-C", moduleDir.toString(), "--target-dir", targetDirPath.toString)
        os.proc(cmd).call()
        PathRef(targetDirPath)
    }
    

    def test = Task {
        val targetDir = build().path
        val cmd = Seq("moon", "test", "-C", moduleDir.toString(), "--target-dir", targetDir.toString)
        os.proc(cmd).call()
        PathRef(targetDir)
    }
end MoonbitModule
