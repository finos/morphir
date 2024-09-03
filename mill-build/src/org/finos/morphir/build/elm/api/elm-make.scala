package org.finos.morphir.build.elm.api
import upickle.default.{ReadWriter => RW, macroRW}
import org.finos.morphir.build._

final case class ElmMakeOptions(    
    @mainargs.arg(doc = "Turn on the time-traveling debugger")
    debug:Boolean = false,
    @mainargs.arg(doc = "Turn on optimizations to make code smaller and faster.")
    optimize:Boolean = false,
    output:Option[String] = None,
    @mainargs.arg(doc="You can say --report=json to get error messages as JSON.")
    report:Option[String] = None,
    @mainargs.arg(doc = "Generate a JSON file of documentation for a package.")
    docs:Option[String] = None,
    elmFiles:List[String] 
)
object ElmMakeOptions {
    implicit val toCommandLine:ToCommandLine[ElmMakeOptions] = {options:ElmMakeOptions =>
        val debug = if(options.debug) Seq("--debug") else Seq.empty
        val optimize = if(options.optimize) Seq("--optimize") else Seq.empty
        val output = options.output.map(Seq("--output", _)).getOrElse(Seq.empty)
        val report = options.report.map(Seq("--report", _)).getOrElse(Seq.empty)
        val docs = options.docs.map(Seq("--docs", _)).getOrElse(Seq.empty)
        val elmFiles = options.elmFiles
        val args = debug ++ optimize ++ output ++ report ++ docs
        
        val cmdLine = 
            CommandLine(
                command = "elm", 
                subcommandArgs = SubcommandArgs("make"),
                args = Args(args),
                afterArgs = AfterArgs(elmFiles)
            )
        cmdLine
    }

    implicit val rw:RW[ElmMakeOptions] = macroRW
}