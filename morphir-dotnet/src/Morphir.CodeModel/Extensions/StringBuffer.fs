[<AutoOpen>]
module Morphir.Extensions.StringBuffer

open System.Text

type StringBuffer = StringBuilder -> unit

type StringBufferBuilder() =
    member inline _.Yield(txt: string) =
        fun (b: StringBuilder) -> Printf.bprintf b "%s" txt

    member inline _.Yield(c: char) =
        fun (b: StringBuilder) -> Printf.bprintf b "%c" c

    member inline _.Yield(strings: #seq<string>) =
        fun (b: StringBuilder) ->
            for s in strings do
                Printf.bprintf b "%s\n" s

    member inline _.YieldFrom([<InlineIfLambda>] f: StringBuffer) = f

    member inline _.Combine([<InlineIfLambda>] f, [<InlineIfLambda>] g) =
        fun (b: StringBuilder) ->
            f b
            g b

    member inline _.Delay([<InlineIfLambda>] f) = fun (b: StringBuilder) -> (f ()) b
    member inline _.Zero() = ignore

    member inline _.For(xs: 'a seq, [<InlineIfLambda>] f: 'a -> StringBuffer) =
        fun (b: StringBuilder) ->
            use e = xs.GetEnumerator()

            while e.MoveNext() do
                (f e.Current) b

    member inline _.While([<InlineIfLambda>] p: unit -> bool, [<InlineIfLambda>] f: StringBuffer) =
        fun (b: StringBuilder) ->
            while p () do
                f b

    member inline _.Run([<InlineIfLambda>] f: StringBuffer) =
        let b = StringBuilder()
        do f b
        b.ToString()

let stringBuffer = new StringBufferBuilder()

type StringBufferBuilder with

    member inline __.Yield(b: byte) =
        fun (sb: StringBuilder) -> Printf.bprintf sb "%02x " b
