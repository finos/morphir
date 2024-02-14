module MyPlugin

open System
open System.Runtime.InteropServices
open System.Text.Json
open Extism

[<UnmanagedCallersOnly(EntryPoint = "greet")>]
let Greet () : int32 =
    let name = Pdk.GetInputString()
    let greeting = $"Hello, {name}!"
    Pdk.SetOutput(greeting)
    0
    
[<EntryPoint>]
let Main args  =
    // Note: an `EntryPoint` function is required for the app to compile
    0