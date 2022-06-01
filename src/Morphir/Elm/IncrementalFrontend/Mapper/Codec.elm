module Morphir.Elm.IncrementalFrontend.Mapper.Codec exposing (..)

import Elm.Syntax.Range as Range
import Json.Encode as Encode
import Morphir.Elm.IncrementalFrontend.Mapper exposing (Error(..), SourceLocation)
import Morphir.Elm.IncrementalResolve.Codec as IncrementalResolveCodec
import Morphir.IR.Path.Codec exposing (encodePath)
import Morphir.Type.Infer.Codec exposing (encodeTypeError)
import Set


encodeError : Error -> Encode.Value
encodeError error =
    case error of
        EmptyApply sourceLocation ->
            Encode.list identity
                [ Encode.string "EmptyApply"
                , encodeSourceLocation sourceLocation
                ]

        NotSupported sourceLocation string ->
            Encode.list identity
                [ Encode.string "EmptyApply"
                , encodeSourceLocation sourceLocation
                ]

        RecordPatternNotSupported sourceLocation ->
            Encode.list identity
                [ Encode.string "EmptyApply"
                , encodeSourceLocation sourceLocation
                ]

        ResolveError sourceLocation err ->
            Encode.list identity
                [ Encode.string "ResolveError"
                , encodeSourceLocation sourceLocation
                , IncrementalResolveCodec.encodeError err
                ]

        SameNameAppearsMultipleTimesInPattern sourceLocation names ->
            Encode.list identity
                [ Encode.string "SameNameAppearsMultipleTimesInPattern"
                , encodeSourceLocation sourceLocation
                , names |> Set.toList |> Encode.list Encode.string
                ]

        VariableNameCollision sourceLocation varName ->
            Encode.list identity
                [ Encode.string "VariableNameCollision"
                , encodeSourceLocation sourceLocation
                , Encode.string varName
                ]

        UnresolvedVariable sourceLocation varName ->
            Encode.list identity
                [ Encode.string "UnresolvedVariable"
                , encodeSourceLocation sourceLocation
                , Encode.string varName
                ]

        TypeCheckError moduleName typeError ->
            Encode.list identity
                [ Encode.string "TypeCheckError"
                , encodePath moduleName
                , encodeTypeError typeError
                ]


encodeSourceLocation : SourceLocation -> Encode.Value
encodeSourceLocation sourceLocation =
    Encode.object
        [ ( "location", Range.encode sourceLocation.location )
        , ( "moduleName", Encode.list Encode.string sourceLocation.moduleName )
        ]
