module Morphir.Cli.Program

open Morphir.Cli

[<EntryPoint>]
let main argv =
    let config = {ApplicationName = "morphir"}
    
    config
    |> CommandLineHost.runHost argv