namespace Morphir.SDK.Extensions

open System.Runtime.CompilerServices

[<Extension>]
module MaybeExtensions =
    open Morphir.SDK.Maybe
    open Morphir.SDK.Maybe.Conversions

    [<Extension>]
    let ToOption (self: Maybe<'T>) = maybeToOptions self
