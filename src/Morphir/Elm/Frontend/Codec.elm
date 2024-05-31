module Morphir.Elm.Frontend.Codec exposing
    ( decodeOptions
    , decodePackageInfo
    , encodeDeadEnd
    , encodeSourceFile
    , encodeError
    , encodeContentLocation
    , encodeContentRange
    , encodeSourceLocation
    )

{-| Codecs for types in the `Morphir.Elm.Frontend` module.


# Options

@docs decodeOptions


# PackageInfo

@docs decodePackageInfo


# DeadEnd

@docs encodeDeadEnd


# SourceFile

@docs encodeSourceFile


# Error

@docs encodeError


# ContentLocation

@docs encodeContentLocation


# ContentRange

@docs encodeContentRange


# SourceLocation

@docs encodeSourceLocation

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.Elm.Frontend exposing (ContentLocation, ContentRange, Error(..), Options, PackageInfo, SourceFile, SourceLocation)
import Morphir.Elm.Frontend.Resolve as Resolve
import Morphir.IR.Name.Codec exposing (encodeName)
import Morphir.IR.Path as Path
import Morphir.JsonExtra as JsonExtra
import Morphir.Type.Infer.Codec as InferCodec
import Parser exposing (DeadEnd)
import Set


{-| Decode Options.
-}
decodeOptions : Decode.Decoder Options
decodeOptions =
    Decode.map Options
        (Decode.field "typesOnly" Decode.bool)


{-| Encode PackageInfo.
-}
decodePackageInfo : Decode.Decoder PackageInfo
decodePackageInfo =
    Decode.map2 PackageInfo
        (Decode.field "name"
            (Decode.string
                |> Decode.map Path.fromString
            )
        )
        (Decode.maybe
            (Decode.field "exposedModules"
                (Decode.list (Decode.string |> Decode.map Path.fromString)
                    |> Decode.map Set.fromList
                )
            )
        )


{-| Encode DeadEnd.
-}
encodeDeadEnd : DeadEnd -> Encode.Value
encodeDeadEnd deadEnd =
    Encode.list identity
        [ Encode.int deadEnd.row
        , Encode.int deadEnd.col
        ]


{-| Encode SourceFile.
-}
encodeSourceFile : SourceFile -> Encode.Value
encodeSourceFile sourceFile =
    Encode.object
        [ ( "path", Encode.string sourceFile.path ) ]


{-| Encode Error.
-}
encodeError : Error -> Encode.Value
encodeError error =
    case error of
        ParseError sourcePath deadEnds ->
            JsonExtra.encodeConstructor "ParseError"
                [ Encode.string sourcePath
                , Encode.list encodeDeadEnd deadEnds
                ]

        CyclicModules _ ->
            JsonExtra.encodeConstructor "CyclicModules" []

        ResolveError sourceLocation resolveError ->
            JsonExtra.encodeConstructor "ResolveError"
                [ encodeSourceLocation sourceLocation
                , Resolve.encodeError resolveError
                ]

        EmptyApply sourceLocation ->
            JsonExtra.encodeConstructor "EmptyApply"
                [ encodeSourceLocation sourceLocation
                ]

        NotSupported sourceLocation message ->
            JsonExtra.encodeConstructor "NotSupported"
                [ encodeSourceLocation sourceLocation
                , Encode.string message
                ]

        DuplicateNameInPattern name sourceLocation1 sourceLocation2 ->
            JsonExtra.encodeConstructor "DuplicateNameInPattern"
                [ encodeName name
                , encodeSourceLocation sourceLocation1
                , encodeSourceLocation sourceLocation2
                ]

        VariableShadowing name sourceLocation1 sourceLocation2 ->
            JsonExtra.encodeConstructor "VariableShadowing"
                [ encodeName name
                , encodeSourceLocation sourceLocation1
                , encodeSourceLocation sourceLocation2
                ]

        MissingTypeSignature sourceLocation ->
            JsonExtra.encodeConstructor "MissingTypeSignature"
                [ encodeSourceLocation sourceLocation
                ]

        RecordPatternNotSupported sourceLocation ->
            JsonExtra.encodeConstructor "RecordPatternNotSupported"
                [ encodeSourceLocation sourceLocation
                ]

        TypeInferenceError sourceLocation typeError ->
            JsonExtra.encodeConstructor "RecordPatternNotSupported"
                [ encodeSourceLocation sourceLocation
                , InferCodec.encodeTypeError typeError
                ]


{-| Encode ContentLocation.
-}
encodeContentLocation : ContentLocation -> Encode.Value
encodeContentLocation contentLocation =
    Encode.object
        [ ( "row", Encode.int contentLocation.row )
        , ( "column", Encode.int contentLocation.column )
        ]


{-| Encode ContentRange.
-}
encodeContentRange : ContentRange -> Encode.Value
encodeContentRange contentRange =
    Encode.object
        [ ( "start", encodeContentLocation contentRange.start )
        , ( "end", encodeContentLocation contentRange.end )
        ]


{-| Encode SourceLocation.
-}
encodeSourceLocation : SourceLocation -> Encode.Value
encodeSourceLocation sourceLocation =
    Encode.object
        [ ( "source", encodeSourceFile sourceLocation.source )
        , ( "range", encodeContentRange sourceLocation.range )
        ]
