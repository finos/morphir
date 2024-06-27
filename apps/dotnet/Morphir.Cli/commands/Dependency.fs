namespace Morphir.Cli.Commands.Dependency

open Spectre.Console
open Spectre.Console.Cli

type DependencySettings() as self = 
    inherit CommandSettings()
    
type RefreshSettings() as self = 
    inherit DependencySettings()

    [<CommandArgument(0, "[workspace-or-project-path]")>]
    member val Path:string option = None with get, setpw
    
type Refresh() =
    inherit Command<RefreshSettings>()
    interface ICommandLimiter<DependencySettings>
    interface ICommandLimiter<RefreshSettings>
    
    

    override _.Execute(_context, settings) =
        AnsiConsole.MarkupLine($"Refreshing dependencies... {settings}") //|> AnsiConsole.Write
        0