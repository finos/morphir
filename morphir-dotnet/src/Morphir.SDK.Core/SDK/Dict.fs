module Morphir.SDK.Dict

open Morphir.SDK
open Morphir.SDK.Maybe
open Morphir.SDK.List

type Dict<'K, 'V when 'K: comparison> = Map<'K, 'V>

[<CompiledName("Empty")>]
let empty: Dict<'K, 'V> = Map.empty

let get (key: 'Key) (dict: Dict<'Key, 'Value>) =
    match Map.tryFind key dict with
    | Some value -> Just value
    | None -> Nothing

let map (f: 'k -> 'a -> 'b) (dict: Dict<'k, 'a>) : Dict<'k, 'b> = Map.map f dict

let inline ``member`` (key: 'Key) (dict: Dict<'Key, 'Value>) = Map.containsKey key dict

let inline size (dict: Dict<'Key, 'Value>) = Map.count dict

[<CompiledName("IsEmpty")>]
let inline isEmpty (dict: Dict<'Key, 'Value>) = Map.isEmpty dict

let inline insert (key: 'Key) (value: 'Value) (dict: Dict<'Key, 'Value>) : Dict<'Key, 'Value> =
    Map.add key value dict

let inline keys (dict: Dict<'Key, 'Value>) : List<'Key> =
    Map.toList dict
    |> List.map (fun (k, _) -> k)

[<CompiledName("Values")>]
let inline values (dict: Dict<'Key, 'Value>) : List<'Value> =
    Map.toList dict
    |> List.map (fun (_, v) -> v)

[<CompiledName("ToList")>]
let inline toList (dict: Dict<'Key, 'Value>) : List<'Key * 'Value> = Map.toList dict

let inline fromList assocs : Dict<'Key, 'Value> = Map.ofList assocs
