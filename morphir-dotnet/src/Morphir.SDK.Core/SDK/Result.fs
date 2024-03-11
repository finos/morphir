namespace Morphir.SDK

module Result =

    type Result<'TError, 'TValue> = FSharp.Core.Result<'TValue, 'TError>

    let (|Ok|Err|) =
        function
        | Error err -> Err err
        | Ok value -> Ok value

    let Err error = Error error

    let withDefault defaultValue (result: Result<'Error, 'Value>) =
        match result with
        | Ok value -> value
        | Err _ -> defaultValue
