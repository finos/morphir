module Morphir.Runtime.RuntimeExtension

open System
open System.Runtime.InteropServices
open Extism

[<UnmanagedCallersOnly(EntryPoint = "eval")>]
let Eval () : int32 =
    let input = Pdk.GetInputString()
    let greeting = $"Hello, the input is {input}!"
    Pdk.SetOutput greeting
    0
