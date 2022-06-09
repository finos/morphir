port module Morphir.Elm.DevCLI exposing (..)

import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Morphir.Elm.Common exposing (appendBraces, mapOperators)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path
import Morphir.IR.SDK as SDK
import Morphir.IR.Type as Type exposing (Type, collectVariables)
import Set


port request : (Decode.Value -> msg) -> Sub msg


port respond : Encode.Value -> Cmd msg


main : Platform.Program () () Msg
main =
    Platform.worker
        { init = \_ -> ( (), Cmd.none )
        , update = update
        , subscriptions = subscriptions
        }


type alias Model =
    ()


type Msg
    = Request Decode.Value


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Request bodyJson ->
            let
                _ =
                    Debug.log "request body" (Encode.encode 4 bodyJson)
            in
            ( model, respond (Encode.string nativeFun) )


subscriptions : Model -> Sub Msg
subscriptions model =
    request Request


nativeFun : String
nativeFun =
    [ "module Morphir.IR.SDK.SDKNativeFunctions exposing (..)"
    , "import Morphir.IR.Literal exposing (Literal(..))"
    , "import Morphir.Value.Native as Native exposing (..)"
    , "nativeFunctions : List ( String, String, Native.Function )"
    , "nativeFunctions = "
    , "["
        ++ (SDK.packageSpec.modules
                |> Dict.toList
                |> List.map
                    (\( moduleName, moduleSpec ) ->
                        moduleSpec.values
                            |> Dict.toList
                            |> List.filter
                                (\( _, functionSpec ) ->
                                    let
                                        filterFunction : Type () -> Bool
                                        filterFunction typeInfo =
                                            case typeInfo of
                                                Type.Function _ _ _ ->
                                                    False

                                                other ->
                                                    collectVariables other |> Set.isEmpty
                                    in
                                    List.all filterFunction (functionSpec.value.inputs |> List.map Tuple.second) && filterFunction functionSpec.value.output
                                )
                            |> List.map
                                (\( functionName, functionSpec ) ->
                                    let
                                        evalFunc =
                                            "eval" ++ (List.length functionSpec.value.inputs |> String.fromInt)

                                        funName =
                                            (Path.toString Name.toTitleCase "." moduleName ++ "." ++ Name.toCamelCase functionName) |> mapOperators

                                        inputTypes : String
                                        inputTypes =
                                            functionSpec.value.inputs
                                                |> List.map
                                                    (\( _, argType ) ->
                                                        [ mapEncodeOrDecode "decode" argType
                                                        , argType |> mapTypeValue "decode"
                                                        ]
                                                            |> List.filter (\val -> not (String.isEmpty val))
                                                            |> String.join " "
                                                            |> appendBraces
                                                    )
                                                |> String.join " "

                                        outputType : String
                                        outputType =
                                            [ mapEncodeOrDecode "encode" functionSpec.value.output
                                            , functionSpec.value.output |> mapTypeValue "encode"
                                            ]
                                                |> List.filter (\val -> not (String.isEmpty val))
                                                |> String.join " "
                                                |> appendBraces

                                        nativeExpression : String
                                        nativeExpression =
                                            [ evalFunc, funName, inputTypes, outputType ]
                                                |> List.filter (\val -> not (String.isEmpty val))
                                                |> String.join " "
                                    in
                                    ([ "\"" ++ Path.toString Name.toTitleCase "." moduleName ++ "\"", "\"" ++ Name.toCamelCase functionName ++ "\"", nativeExpression ]
                                        |> String.join ","
                                    )
                                        |> appendBraces
                                )
                    )
                |> List.concat
                |> String.join ",\n"
           )
        ++ "]"
    ]
        |> String.join "\n"


mapTypeValue : String -> Type () -> String
mapTypeValue encodeOrDecode typeA =
    let
        isEncodingOrDecoding : String -> String -> String
        isEncodingOrDecoding encodedValue decodedValue =
            case encodeOrDecode of
                "encode" ->
                    decodedValue

                _ ->
                    encodedValue
    in
    case typeA of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], moduleName, localName ) args ->
            case ( moduleName, localName, args ) of
                ( [ [ "basics" ] ], [ "bool" ], [] ) ->
                    isEncodingOrDecoding "boolLiteral" "BoolLiteral"

                ( [ [ "char" ] ], [ "char" ], [] ) ->
                    isEncodingOrDecoding "charLiteral" "CharLiteral"

                ( [ [ "string" ] ], [ "string" ], [] ) ->
                    isEncodingOrDecoding "stringLiteral" "StringLiteral"

                ( [ [ "basics" ] ], [ "int" ], [] ) ->
                    isEncodingOrDecoding "intLiteral" "WholeNumberLiteral"

                ( [ [ "basics" ] ], [ "float" ], [] ) ->
                    isEncodingOrDecoding "floatLiteral" "FloatLiteral"

                ( [ [ "list" ] ], [ "list" ], [ itemType ] ) ->
                    [ mapEncodeOrDecode encodeOrDecode itemType, mapTypeValue encodeOrDecode itemType ]
                        |> List.filter (\val -> not (String.isEmpty val))
                        |> String.join " "
                        |> appendBraces

                ( [ [ "maybe" ] ], [ "maybe" ], [ itemType ] ) ->
                    [ mapEncodeOrDecode encodeOrDecode itemType, mapTypeValue encodeOrDecode itemType ]
                        |> List.filter (\val -> not (String.isEmpty val))
                        |> String.join " "
                        |> appendBraces

                _ ->
                    Name.toCamelCase localName

        Type.Tuple _ typeList ->
            (typeList
                |> List.map
                    (\tpe ->
                        [ mapEncodeOrDecode encodeOrDecode tpe, mapTypeValue encodeOrDecode tpe ]
                            |> List.filter (\val -> not (String.isEmpty val))
                            |> String.join " "
                            |> appendBraces
                    )
                |> String.join ","
            )
                |> appendBraces

        Type.Record _ fieldsList ->
            "{" ++ (fieldsList |> List.map (\field -> Name.toCamelCase field.name ++ " : " ++ mapTypeValue encodeOrDecode field.tpe) |> String.join ",") ++ "}"

        Type.Unit () ->
            "()"

        _ ->
            "Types are pending"


mapEncodeOrDecode : String -> Type () -> String
mapEncodeOrDecode encodeOrDecode typeC =
    case typeC of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], moduleName, localName ) args ->
            case ( moduleName, localName, args ) of
                ( [ [ "basics" ] ], [ "bool" ], [] ) ->
                    encodeOrDecode ++ "Literal"

                ( [ [ "char" ] ], [ "char" ], [] ) ->
                    encodeOrDecode ++ "Literal"

                ( [ [ "string" ] ], [ "string" ], [] ) ->
                    encodeOrDecode ++ "Literal"

                ( [ [ "basics" ] ], [ "int" ], [] ) ->
                    encodeOrDecode ++ "Literal"

                ( [ [ "basics" ] ], [ "float" ], [] ) ->
                    encodeOrDecode ++ "Literal"

                ( [ [ "list" ] ], [ "list" ], [ itemType ] ) ->
                    encodeOrDecode ++ "List"

                ( [ [ "maybe" ] ], [ "maybe" ], [ itemType ] ) ->
                    encodeOrDecode ++ "Maybe"

                _ ->
                    encodeOrDecode ++ "Undefined"

        Type.Tuple _ typeList ->
            encodeOrDecode ++ "Tuple2"

        _ ->
            "Undefined Type"
