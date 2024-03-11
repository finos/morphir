namespace Morphir.IR


module Path =
    open Morphir.IR.Name
    open Morphir.SDK.List
    open Morphir.SDK

    /// <summary>
    /// Type that represents a path as a list of names.
    /// </summary>
    [<Struct>]
    type Path =
        | Path of Parts: Name list

        static member Combine(Path this, Path other) = Path.FromList(this @ other)
        member this.Combine(other) = Path.Combine(this, other)

        static member FromList(names: Name list) : Path = Path names

        static member FromList(input: string list list) : Path =
            input |> List.map Name.fromList |> Path.FromList

        member this.Names =
            match this with
            | Path names -> names

    let inline combine left right = Path.Combine(left, right)
    let inline fromList (names: List<Name>) : Path = Path names

    let inline toList (Path names) : List<Name> = names

    let toString nameToString sep path =
        path |> toList |> List.map nameToString |> String.join sep

    let fromString string =
        let separatorRegex = Regex.fromString "[^\\w\\s]+" |> Maybe.withDefault Regex.never in

        Regex.split separatorRegex string |> List.map Name.fromString |> fromList

    let rec isPrefixOf (Path path) (Path prefix) =
        let rec loop path prefix =
            match (path, prefix) with
            // empty path is a prefix of any other path
            | ([], _) -> true
            // empty path has no prefixes except the empty prefix captured above
            | (_, []) -> false
            // for any other case compare the head and recurse
            | (pathHead :: pathTail, prefixHead :: prefixTail) ->
                if prefixHead = pathHead then
                    loop prefixTail pathTail
                else
                    false

        loop path prefix

    let inline isPrefixFor prefix path = isPrefixOf path prefix

[<AutoOpen>]
module PathDsl =
    open Name
    open Path

    [<RequireQualifiedAccess>]
    type PathBuilderStep =
        | Names of Name list
        | PathString of string

    type PathBuilder() =

        member inline _.Combine(newStep: PathBuilderStep, previousSteps: PathBuilderStep list) =
            newStep :: previousSteps

        member inline _.Delay(f: unit -> PathBuilderStep list) = f ()
        member inline _.Delay(f: _ -> PathBuilderStep) = [ f () ]

        member inline this.For(step, f) = this.Combine(step, f ())

        [<CustomOperation("name")>]
        member inline _.Name((), nameStr: string) =
            [ [ Name.fromString nameStr ] |> PathBuilderStep.Names ]

        [<CustomOperation("name")>]
        member inline _.Name(steps: PathBuilderStep list, nameStr: string) =
            PathBuilderStep.Names [ Name.fromString nameStr ] :: steps

        [<CustomOperation("names")>]
        member inline _.Names((), names: string list) =
            names |> List.map Name.fromString |> PathBuilderStep.Names

        [<CustomOperation("names")>]
        member inline _.Names(step: PathBuilderStep, names: string list) =
            (names |> List.map Name.fromString |> PathBuilderStep.Names) :: step :: []

        [<CustomOperation("names")>]
        member inline _.Names(steps: PathBuilderStep list, names: string list) =
            (names |> List.map Name.fromString |> PathBuilderStep.Names) :: steps

        member inline _.Run(steps: PathBuilderStep list) : Path =
            let emptyPath = Path.fromList []

            steps
            |> List.fold
                (fun (Path namesInPath) step ->
                    match step with
                    | PathBuilderStep.Names names -> names @ namesInPath |> Path.fromList
                    | PathBuilderStep.PathString str -> Path.fromString str)
                emptyPath

        member inline this.Run(step: PathBuilderStep) = this.Run([ step ])

        member inline _.Yield(()) = ()
        member inline _.Yield(pathStr: string) = PathBuilderStep.PathString pathStr
