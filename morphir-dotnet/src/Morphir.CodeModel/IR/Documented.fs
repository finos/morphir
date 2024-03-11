module Morphir.IR.Documented

/// <summary>
/// Type that represents a value that is documented value.
/// </summary>
type Documented<'T> = { Doc: string; Value: 'T }

/// <summary>
/// Maps a function over the value of a documented value.
/// </summary>
[<CompiledName("Map")>]
let map (f: 'a -> 'b) (d: Documented<'a>) = { Doc = d.Doc; Value = f d.Value }

[<CompiledName("Value")>]
let inline value (d: Documented<'a>) = d.Value

let inline documented (doc: string) (value: 'a) : Documented<'a> = { Doc = doc; Value = value }

let (|Doc|) documented = documented.Doc
let (|Value|) documented = documented.Value
