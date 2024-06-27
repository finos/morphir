open Spectre.Console.Cli
open Commands

[<EntryPoint>]
let main argv = 
    let app = CommandApp()
    app.Configure(fun config ->
        config.AddCommand<Build.Build>("build")
            .WithDescription("Builds the project.")         
            |> ignore
        config.AddCommand<Run.Run>("run")
            .WithDescription("Runs a model.")         
            |> ignore
        
    )    
    app.Run(argv)