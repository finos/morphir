module Morphir.SDK.List

open Morphir.SDK.Maybe

type List<'t> = 't list

[<CompiledName("Empty")>]
let empty<'T> : List<'T> = FSharp.Collections.List.Empty

[<CompiledName("Singleton")>]
let inline singleton a = [ a ]

let inline cons a lst = a :: lst

[<CompiledName("Map")>]
let inline map mapping list =
    Microsoft.FSharp.Collections.List.map mapping list

let inline map2 mapping list1 list2 =
    Microsoft.FSharp.Collections.List.map2 mapping list1 list2

let inline map3 mapping list1 list2 list3 =
    Microsoft.FSharp.Collections.List.map3 mapping list1 list2 list3

let any = FSharp.Collections.List.exists

let filterMap (f: 'a -> Maybe<'b>) (xs: List<'a>) : List<'b> =
    let fn: 'a -> Option<'b> =
        f
        >> Maybe.Conversions.Options.maybeToOptions

    FSharp.Collections.List.choose fn xs

[<CompiledName("IsEmpty")>]
let isEmpty =
    function
    | [] -> true
    | _ -> false

let inline append list1 list2 =
    FSharp.Collections.List.append list1 list2
