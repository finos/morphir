namespace Morphir.Cli

open System
open Spectre.Console.Cli
open Morphir.Cli.Commands

type HostConfig = {
    ApplicationName: string
}

type CommandLineHost(hostConfig:HostConfig) = 
    let app = CommandApp()
    do app.Configure(fun config ->
        config.SetApplicationName(hostConfig.ApplicationName) |> ignore
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
        
    member this.Run(argv) =
        app.Run(argv)

module CommandLineHost =
    let runHost (argv:string seq) (config:HostConfig) =
        let host = CommandLineHost(config)
        host.Run argv
                 
    let inline run(argv: string seq, config:HostConfig) =
        runHost argv config