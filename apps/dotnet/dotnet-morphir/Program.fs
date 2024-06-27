module Morphir.Tool.DotnetMorphir

open Morphir.Cli
open Morphir.Cli.CommandLineHost

[<EntryPoint>]
let main (args: string[]) = 
    {ApplicationName = "dotnet-morphir"}       
    |> CommandLineHost.runHost args