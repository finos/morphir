module Morphir.Tools.CommandLine

open Argu

type LiveArgs =
    | [<AltCommandLine>] Port
    interface IArgParserTemplate with
        member this.Usage =
            match this with
            | Port -> "The port to listen on"
and RestoreArgs =
    | [<AltCommandLine>] Path
    interface IArgParserTemplate with
        member this.Usage =
            match this with
            | Path -> "The path to restore to"
            
type Argument =
    | Version
    | [<AltCommandLine("-v")>] Verbose
    | [<CliPrefix(CliPrefix.None)>] Live of ParseResults<LiveArgs>
    | [<CliPrefix(CliPrefix.None)>] Restore of ParseResults<RestoreArgs>
    interface IArgParserTemplate with
        member this.Usage =
            match this with
            | Version -> "Print version information and exit"
            | Verbose -> "Print verbose output"
            | Live _ -> "Launch the live server"
            | Restore p -> "Restore packages and distributions"
  
type Parser =            
    static member CreateParser ?programName =
        let resolvedProgramName = defaultArg programName "morphir"
        ArgumentParser.Create<Argument>(programName = resolvedProgramName)
module Parser =
    let defaultParser = Parser.CreateParser()

