package org.finos.morphir.build.elm
import mill._ 
import mill.scalalib._ 
import org.finos.morphir.build.elm.api.ElmFormatOptions
import org.finos.morphir.build.CommandLine
import org.finos.morphir.build.ToCommandLine

trait ElmFormatModule extends ElmModule {
    def elmFormat = T{
        // Adding this so that we have a dependency relationship to all elm files.
        val _elmFiles = elmFormatFiles()
        val commandLine = elmFormatCheckCommandLine().toSeq
        os.proc(commandLine).call(cwd = elmJsonDir(), stdout = os.Inherit, stderr = os.Inherit)
    }
    def elmFormatOptions:T[ElmFormatOptions] = T{
        ElmFormatOptions.default
            .withInput(elmFormatFiles().map(_.path.toString):_*)
    }
    def elmFormatCommandLine:T[CommandLine] = T{
        ToCommandLine[ElmFormatOptions].toCommandLine(elmFormatOptions())
    }
    
    def elmFormatFiles = T{ allElmSourceFiles() }
    
    def elmFormatCheckOptions = T{
        ElmFormatOptions
            .defaultCheck
            .withInput(elmFormatFiles().map(_.path.toString):_*)
    }

    def elmFormatCheckCommandLine = T{
        ToCommandLine[ElmFormatOptions].toCommandLine(elmFormatCheckOptions())
    }

    def elmFormatCheck = T{
        // Adding this so that we have a dependency relationship to all elm files.
        val _elmFiles = elmFormatFiles()
        val commandLine = elmFormatCheckCommandLine().toSeq
        os.proc(commandLine).call(cwd = elmJsonDir(), stdout = os.Inherit, stderr = os.Inherit)
    }


    
}