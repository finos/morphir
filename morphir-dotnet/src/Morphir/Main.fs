module Morphir.Main

open Argu
open Morphir.Tools
open System

open Extism.Sdk
open Extism.Sdk.Native


let runExtism argv = 
    let uri = Uri("https://github.com/extism/plugins/releases/latest/download/count_vowels.wasm")
    let manifest = Manifest(new UrlWasmSource(uri))

    let plugin = new Plugin(manifest, Array.Empty<HostFunction>(), withWasi = true)

    let output = plugin.Call("count_vowels", "Hello, World!")
    printfn "%s" output
    0
    
[<EntryPoint>]    
let main argv =
    let parser = CommandLine.Parser.defaultParser
    try
        let commandLine = parser.ParseCommandLine(inputs = argv, raiseOnUsage = true)
        printfn "Command line: %A" commandLine
        0
    with :? ArguParseException as e -> eprintfn "%s" e.Message; 1
    //runExtism argv    