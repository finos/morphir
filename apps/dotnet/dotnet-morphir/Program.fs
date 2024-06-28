module Morphir.Tool.DotnetMorphir

open System.Diagnostics.CodeAnalysis
open Morphir.Cli
open Morphir.Cli.Commands
open Morphir.Host


[<EntryPoint>]
let main (args: string[]) =
    let config = {ApplicationName = "dotnet-morphir"}       
    CommandLineHost.Run(config, args)