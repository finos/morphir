namespace Morphir.Cli.Commands.Dependency

open Spectre.Console
open Spectre.Console.Cli

type DependencySettings() = 
    inherit CommandSettings()
    
type RefreshSettings() = 
    inherit DependencySettings()

    [<CommandArgument(0, "[workspace-or-project-path]")>]
    member val Path:string option = None with get, set
    
type Refresh() =
    inherit Command<RefreshSettings>()
    interface ICommandLimiter<DependencySettings>
    interface ICommandLimiter<RefreshSettings>
    
    

    override _.Execute(_context, settings) =
        AnsiConsole.MarkupLine($"Refreshing dependencies... {settings}") //|> AnsiConsole.Write
        0