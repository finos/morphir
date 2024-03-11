module Morphir.SDK.String

open Morphir.SDK
open Morphir.SDK.Maybe

let inline isEmpty string = System.String.IsNullOrEmpty(string)

let length =
    function
    | null -> 0
    | (str: string) -> str.Length

let reverse (str: string) = str |> Seq.rev |> System.String.Concat

let repeat (x: int) (str: string) = String.replicate x str

let replace (before: string) (after: string) (str: string) = str.Replace(before, after)

let append (str1: string) (str2: string) = str1 + str2

let split (sep: string) (str: string) =
    str.Split([| sep |], System.StringSplitOptions.None) |> Array.toList

let join (sep: string) (chunks: Morphir.SDK.List.List<string>) = System.String.Join(sep, chunks)

let concat (strings: string list) = join "" strings

let words (str: string) = split " " str

let lines (str: string) = split "\n" str

let slice (startIndex: int) (endIndex: int) (str: string) =
    let start =
        if startIndex >= 0 then
            startIndex
        else
            str.Length + startIndex

    let last =
        if endIndex >= 0 then
            endIndex - 1
        else
            (str.Length + endIndex - 1)

    str.[start..last]

let left (n: int) (str: string) = if n < 1 then "" else slice 0 n str

let right (n: int) (str: string) =
    if n < 1 then "" else slice -n (length str) str

let dropLeft (n: int) (str: string) =
    if n < 1 then str else slice n (length str) str

let dropRight (n: int) (str: string) = if n < 1 then str else slice 0 -n str

let contains (substring: string) (str: string) = str.Contains substring

let startsWith (substring: string) (str: string) = str.StartsWith substring

let endsWith (substring: string) (str: string) = str.EndsWith substring

let rec indexesHelp (substring: string) (str: string) (curr: int) (result: int list) =
    let idx = str.IndexOf substring

    if (idx = -1) then
        result
    else
        indexesHelp substring (slice (idx + 1) str.Length str) (curr + idx + 1) (result @ [ curr + idx ])

let indexes (substring: string) (str: string) = indexesHelp substring str 0 []

let indices (substring: string) (str: string) = indexes substring str

let toInt (str: string) =
    match System.Int32.TryParse str with
    | (true, result) -> Some(result)
    | (false, _) -> None

let fromInt (n: int) = string n

let toFloat (str: string) =
    match System.Double.TryParse str with
    | (true, result) -> Some(result)
    | (false, _) -> None

let fromFloat (n: float) = string n

let fromChar (ch: char) = string ch

let cons (ch: char) (string: string) = sprintf "%c%s" ch string

let uncons (string: string) =
    match string with
    | null -> Maybe.Nothing
    | "" -> Maybe.Nothing
    | str when (str.Length = 1) -> Maybe.Just(str.[0], System.String.Empty)
    | str -> Maybe.Just(str.[0], str.[1..])

let toList (str: string) = Seq.toList str

let fromList (chs: char list) =
    System.String.Concat(Array.ofList (chs))

let inline toUpper (str: string) = str.ToUpperInvariant()

let inline toLower (str: string) = str.ToLowerInvariant()

let pad (n: int) (ch: char) (str: string) =
    let half: float = float (n - length str) / 2.0

    repeat (ceil half |> int) (fromChar ch)
    + str
    + repeat (floor half |> int) (fromChar ch)

let padLeft (n: int) (ch: char) (str: string) =
    repeat (n - length str) (fromChar ch) + str

let padRight (n: int) (ch: char) (str: string) =
    str + repeat (n - length str) (fromChar ch)

let trim (str: string) = str.Trim()

let trimLeft (str: string) = str.TrimStart()

let trimRight (str: string) = str.TrimEnd()

let map func str = String.map func str

let filter isGood str = String.filter isGood str

let foldl (folder: char -> 'b -> 'b) (state: 'b) (str: string) : 'b =
    let mutable state = state

    for c in str do
        state <- folder c state

    state

let foldr (folder: char -> 'b -> 'b) (state: 'b) (str: string) : 'b = foldl folder state (reverse str)

let any isGood str =
    match List.tryFind isGood (toList str) with
    | None -> false
    | _ -> true

let all isGood str =
    if (List.filter isGood (toList str)).Length = str.Length then
        true
    else
        false

// Checks the exact length of a string and wraps it using the specified constructor.
let ofLength (length: int) (ctor: string -> 'a) (value: string) =
    if String.length value = length then
        Some(ctor value)
    else
        None

// Checks the max length of a string and wraps it using the specified constructor.
let ofMaxLength (maxLength: int) (ctor: string -> 'a) (value: string) =
    if String.length value <= maxLength then
        Some(ctor value)
    else
        None

let capitalize string : string =
    match uncons string with
    | Just(headChar, tailString) -> cons (Char.toUpper headChar) tailString
    | Nothing -> string
