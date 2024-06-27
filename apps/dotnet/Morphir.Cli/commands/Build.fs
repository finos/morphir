namespace Morphir.Cli.Commands.Build

open Spectre.Console
open Spectre.Console.Cli


type BuildSettings() as self = 
    inherit CommandSettings()

    [<CommandOption("-t|--target")>]
    member val target = "Release" with get, set    

    override _.Validate() =
        if self.target <> "Release" && self.target <> "Debug" then
            ValidationResult.Error("Invalid target specified.")
        else
            ValidationResult.Success()

type Build() =
    inherit Command<BuildSettings>()
    interface ICommandLimiter<BuildSettings>

    override _.Execute(_context, settings) =
        printfn "Building %s..." settings.target        
        0