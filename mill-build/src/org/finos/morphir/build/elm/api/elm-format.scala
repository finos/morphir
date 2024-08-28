package org.finos.morphir.build.elm.api

import upickle.default.{ReadWriter => RW, macroRW}
import org.finos.morphir.build._

final case class ElmFormatOptions(
    output: Option[String] = None,
    yes: Boolean = false,
    validate: Boolean = false,
    stdin: Boolean = false,
    elmVersion: Option[String] = None,
    input: List [String] = "./src" :: Nil
) { self =>
    
    def withInput(input: String*): ElmFormatOptions = copy(input = input.toList)
    def withInput(input: List[String]): ElmFormatOptions = copy(input = input)
    def appendInputPaths(input: String*): ElmFormatOptions = copy(input = input.toList ++ self.input)
}

object ElmFormatOptions {
    val default:ElmFormatOptions = ElmFormatOptions()
    val defaultCheck:ElmFormatOptions = ElmFormatOptions(validate = true)

    implicit val rw: RW[ElmFormatOptions] = macroRW

    implicit val toCommandLine: ToCommandLine[ElmFormatOptions] = { options: ElmFormatOptions =>
        val output = options.output.map(Seq("--output", _)).getOrElse(Seq.empty)
        val yes = if (options.yes) Seq("--yes") else Seq.empty
        val validate = if (options.validate) Seq("--validate") else Seq.empty
        val stdin = if (options.stdin) Seq("--stdin") else Seq.empty
        val elmVersion = options.elmVersion.map(Seq("--elm-version", _)).getOrElse(Seq.empty)
        val input = options.input

        val args = output ++ yes ++ validate ++ stdin ++ elmVersion

        CommandLine(
            command = "elm-format",
            args = Args(args),
            afterArgs = AfterArgs(input)
        )
    }
}