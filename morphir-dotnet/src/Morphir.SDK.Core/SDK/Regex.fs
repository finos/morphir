module Morphir.SDK.Regex

open Morphir.SDK
open System
open System.Text.RegularExpressions
open Morphir.SDK.Maybe

type private RE = System.Text.RegularExpressions.Regex

type Regex = Regex of RE

type Match = {
    Match: string
    Index: int
    Number: int
    Submatches: Maybe<string> list
}

type Options = {
    CaseInsensitive: Boolean
    Multiline: Boolean
}

let never: Regex = Regex(RE(".^"))

let fromStringWith options string =
    let opts =
        match (options.CaseInsensitive, options.Multiline) with
        | (true, true) ->
            RegexOptions.IgnoreCase
            &&& RegexOptions.Multiline
        | (true, false) -> RegexOptions.IgnoreCase
        | (false, true) -> RegexOptions.Multiline
        | _ -> RegexOptions.None

    try
        Regex.Regex(RE(string, opts))
        |> Maybe.Just
    with _ ->
        Maybe.Nothing

let inline fromString (string: string) =
    fromStringWith
        {
            CaseInsensitive = false
            Multiline = false
        }
        string

let contains (re: Regex) (string: String) =
    let (Regex regEx) = re
    regEx.IsMatch(string)

let splitAtMost (n: int) (re: Regex) (str: string) =
    let (Regex regEx) = re

    regEx.Split(str, n + 1)
    |> List.ofArray

let split (re: Regex) (str: string) =
    let (Regex regEx) = re

    regEx.Split(str)
    |> List.ofArray

let find (re: Regex) (str: string) : Match list =
    let (Regex regEx) = re

    [
        for m in regEx.Matches(str) do
            yield {
                Match = m.Value
                Index = m.Index
                Number = m.Length
                Submatches = []
            }
    ]
