namespace Morphir.Cli.Commands.Run

open Spectre.Console
open Spectre.Console.Cli
open Dumpify

type RunSettings() = 
    inherit CommandSettings()

    [<CommandOption("-i|--include")>]
    member val includes:string[] =  Array.empty with get, set    

type Run() =
    inherit Command<RunSettings>()
    interface ICommandLimiter<RunSettings>

    override _.Execute(_context, settings) =
        settings.Dump() |> ignore
        0