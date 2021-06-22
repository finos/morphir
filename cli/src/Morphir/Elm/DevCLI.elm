port module Morphir.Elm.DevCLI exposing (..)

import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Morphir.Elm.Common exposing (mapOperators)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.SDK as SDK
import Morphir.IR.Type as Type exposing (Type)


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
    [ "module Morphir.IR.SDK.Basics exposing (..)"
    , "nativeFunctions : List ( String, Native.Function )"
    , "nativeFunctions = "
    , "\t["
        ++ (SDK.packageSpec.modules
                |> Dict.toList
                |> List.map
                    (\( moduleName, moduleSpec ) ->
                        moduleSpec.values
                            |> Dict.toList
                            |> List.map
                                (\( functionName, functionSpec ) ->
                                    let
                                        evalFunc =
                                            "eval" ++ (List.length functionSpec.inputs |> String.fromInt)

                                        funName =
                                            "(" ++ ((Path.toString Name.toTitleCase "." moduleName ++ "." ++ Name.toCamelCase functionName) |> mapOperators) ++ ")"

                                        inputTypes : String
                                        inputTypes =
                                            functionSpec.inputs
                                                |> List.map
                                                    (\( _, argType ) ->
                                                        "("
                                                            ++ ([ mapExpectedOrReturn "expect" argType
                                                                , argType
                                                                    |> mapTypeValue
                                                                    |> typeToString
                                                                ]
                                                                    |> List.filter (\val -> not (String.isEmpty val))
                                                                    |> String.join " "
                                                               )
                                                            ++ ")"
                                                    )
                                                |> String.join " "

                                        outputType : String
                                        outputType =
                                            "(" ++ mapExpectedOrReturn "return" functionSpec.output ++ " " ++ (functionSpec.output |> mapTypeValue |> typeToString) ++ ")"

                                        nativeExpression : String
                                        nativeExpression =
                                            [ evalFunc, funName, inputTypes, outputType ]
                                                |> List.filter (\val -> not (String.isEmpty val))
                                                |> String.join " "
                                    in
                                    "(" ++ ([ "\"" ++ Name.toCamelCase functionName ++ "\"", nativeExpression ] |> String.join ",") ++ ")"
                                )
                    )
                |> List.concat
                |> String.join ",\n\t"
           )
        ++ "]"
    ]
        |> String.join "\n"


mapTypeValue : Type () -> Type ()
mapTypeValue typeA =
    case typeA of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], moduleName, localName ) args ->
            case ( moduleName, localName, args ) of
                ( [ [ "basics" ] ], [ "bool" ], [] ) ->
                    Type.Reference () ( [ [ "morphir" ], [ "value" ] ], [ [ "native" ] ], [ "basicsBoolLiteral" ] ) []

                ( [ [ "char" ] ], [ "char" ], [] ) ->
                    Type.Reference () ( [ [ "morphir" ], [ "value" ] ], [ [ "native" ] ], [ "charLiteral" ] ) []

                ( [ [ "string" ] ], [ "string" ], [] ) ->
                    Type.Reference () ( [ [ "morphir" ], [ "value" ] ], [ [ "native" ] ], [ "stringLiteral" ] ) []

                ( [ [ "basics" ] ], [ "int" ], [] ) ->
                    Type.Reference () ( [ [ "morphir" ], [ "value" ] ], [ [ "native" ] ], [ "intLiteral" ] ) []

                ( [ [ "basics" ] ], [ "float" ], [] ) ->
                    Type.Reference () ( [ [ "morphir" ], [ "value" ] ], [ [ "native" ] ], [ "floatLiteral" ] ) []

                _ ->
                    Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], moduleName, localName ) args

        other ->
            other


typeToString : Type () -> String
typeToString typeB =
    case typeB of
        Type.Reference _ ( _, moduleName, localName ) argsList ->
            if List.length argsList > 0 then
                Name.toCamelCase localName
                    ++ "["
                    ++ (argsList |> List.map (\arg -> typeToString arg) |> String.join ",")
                    ++ "]"

            else
                Name.toCamelCase localName

        Type.Variable _ name ->
            Name.toCamelCase name

        Type.Tuple _ typeList ->
            "(" ++ (typeList |> List.map (\tpe -> typeToString tpe) |> String.join ",") ++ ")"

        Type.Record _ fieldsList ->
            "{" ++ (fieldsList |> List.map (\field -> Name.toCamelCase field.name ++ " : " ++ typeToString field.tpe) |> String.join ",") ++ "}"

        Type.Function _ argType returnType ->
            let
                uncurry : Type () -> ( Type (), List (Type ()) )
                uncurry typeZ =
                    case typeZ of
                        Type.Function _ argType1 returnType1 ->
                            let
                                ( nestedType, nestedArgs ) =
                                    uncurry returnType1
                            in
                            ( nestedType, nestedArgs ++ [ returnType1 ] )

                        _ ->
                            ( typeZ, [] )

                typeList =
                    List.length (uncurry returnType |> Tuple.second) + 1
            in
            "expectFun" ++ String.fromInt typeList

        --    "( " ++ typeToString argType ++ " -> " ++ typeToString returnType ++ " )"
        Type.Unit () ->
            "()"

        _ ->
            "Types are pending"


mapExpectedOrReturn : String -> Type () -> String
mapExpectedOrReturn expectOrReturn typeC =
    case typeC of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], moduleName, localName ) args ->
            case ( moduleName, localName, args ) of
                ( [ [ "basics" ] ], [ "bool" ], [] ) ->
                    expectOrReturn ++ "Literal"

                ( [ [ "char" ] ], [ "char" ], [] ) ->
                    expectOrReturn ++ "Literal"

                ( [ [ "string" ] ], [ "string" ], [] ) ->
                    expectOrReturn ++ "Literal"

                ( [ [ "basics" ] ], [ "int" ], [] ) ->
                    expectOrReturn ++ "Literal"

                ( [ [ "basics" ] ], [ "float" ], [] ) ->
                    expectOrReturn ++ "Literal"

                ( [ [ "list" ] ], [ "list" ], [ itemType ] ) ->
                    expectOrReturn ++ "List"

                _ ->
                    expectOrReturn ++ "Undefined"

        Type.Function _ _ _ ->
            ""

        _ ->
            "Undefined Type"
