module Morphir.Cli.Program

open System
open Spectre.Console.Cli
open Morphir.Cli.Commands

[<EntryPoint>]
let main argv = 
    let app = CommandApp()
    app.Configure(fun config ->
        config.SetApplicationName("morphir") |> ignore
        config.AddCommand<Build.Build>("build")
            .WithDescription("Builds the project.")         
            |> ignore
        config.AddCommand<Run.Run>("run")
            .WithDescription("Runs a model.")         
            |> ignore
        
        config.AddBranch<Dependency.DependencySettings>("dependency", fun dependency ->
            dependency.AddCommand<Dependency.Refresh>("refresh")
                .WithDescription("Refreshes dependencies.")         
                |> ignore
            ()
        ) |> ignore
    )    
    app.Run(argv)