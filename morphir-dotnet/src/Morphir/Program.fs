open System

open Extism.Sdk
open Extism.Sdk.Native

let uri = Uri("https://github.com/extism/plugins/releases/latest/download/count_vowels.wasm")
let manifest = Manifest(new UrlWasmSource(uri))

let plugin = new Plugin(manifest, Array.Empty<HostFunction>(), withWasi = true)

let output = plugin.Call("count_vowels", "Hello, World!")
System.Console.WriteLine(output)