module Morphir.SDK.Maybe

open System.Runtime.CompilerServices

type Maybe<'a> =
    | Just of 'a
    | Nothing

and Maybe =
    static member op_Implicit(maybeValue: Maybe<'a>) : 'a option =
        match maybeValue with
        | Just value -> Some value
        | Nothing -> None

    static member op_Implicit(value: 'a option) : Maybe<'a> =
        match value with
        | Some value -> Just value
        | None -> Nothing

[<CompiledName("Just")>]
let just value = Just value

[<CompiledName("Nothing")>]
let nothing = Nothing

[<CompiledName("WithDefault")>]
let withDefault default' =
    function
    | Just value -> value
    | Nothing -> default'

[<CompiledName("Map")>]
let map f =
    function
    | Just value -> Just(f value)
    | Nothing -> Nothing

let map2 func ma mb =
    match ma with
    | Nothing -> Nothing
    | Just a ->
        match mb with
        | Nothing -> Nothing
        | Just b -> Just(func a b)

let map3 func ma mb mc =
    match ma with
    | Nothing -> Nothing
    | Just a ->
        match mb with
        | Nothing -> Nothing
        | Just b ->
            match mc with
            | Nothing -> Nothing
            | Just c -> Just(func a b c)

let map4 func ma mb mc md =
    match ma with
    | Nothing -> Nothing
    | Just a ->
        match mb with
        | Nothing -> Nothing
        | Just b ->
            match mc with
            | Nothing -> Nothing
            | Just c ->
                match md with
                | Nothing -> Nothing
                | Just d -> Just(func a b c d)

let map5 func ma mb mc md me =
    match ma with
    | Nothing -> Nothing
    | Just a ->
        match mb with
        | Nothing -> Nothing
        | Just b ->
            match mc with
            | Nothing -> Nothing
            | Just c ->
                match md with
                | Nothing -> Nothing
                | Just d ->
                    match me with
                    | Nothing -> Nothing
                    | Just e -> Just(func a b c d e)

let andThen callback =
    function
    | Just value -> callback value
    | Nothing -> Nothing

[<CompiledName("IsJust")>]
let isJust =
    function
    | Just _ -> true
    | Nothing -> false

[<CompiledName("IsNothing")>]
let isNothing =
    function
    | Just _ -> false
    | Nothing -> true

let destruct defaultValue func maybe =
    match maybe with
    | Just a -> func a
    | Nothing -> defaultValue

module Conversions =
    [<AutoOpen>]
    module Options =
        [<CompiledName("MaybeToOptions")>]
        let maybeToOptions =
            function
            | Just value -> Some value
            | Nothing -> None

        [<CompiledName("OptionsToMaybe")>]
        let optionsToMaybe =
            function
            | Some value -> Just value
            | None -> Nothing
