module Morphir.Web.DebugIR exposing (..)

import Browser
import Dict exposing (Dict)
import Element exposing (Element, column, el, fill, height, layout, none, padding, paddingXY, paragraph, rgb, row, scrollbars, shrink, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Html exposing (Attribute, Html)
import Morphir.Compiler as Compiler
import Morphir.Elm.Frontend as Frontend exposing (Errors, SourceFile, SourceLocation)
import Morphir.IR as IR exposing (IR)
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name
import Morphir.IR.Package as Package
import Morphir.IR.Type exposing (Type)
import Morphir.Type.Infer as Infer
import Morphir.Visual.Common exposing (nameToText)
import Morphir.Visual.XRayView as XRayView
import Morphir.Web.SourceEditor as SourceEditor
import Set



-- MAIN


type alias Flags =
    {}


main =
    Browser.element { init = init, update = update, view = view, subscriptions = subscriptions }



-- MODEL


type alias Model =
    { source : String
    , maybePackageDef : Maybe (Package.Definition () (Type ()))
    , errors : List Compiler.Error
    }


init : Flags -> ( Model, Cmd Msg )
init flags =
    update (Change sampleSource) { source = "", maybePackageDef = Nothing, errors = [] }


moduleSource : String -> SourceFile
moduleSource sourceValue =
    { path = "Test.elm"
    , content = sourceValue
    }



-- UPDATE


type Msg
    = Change String


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Change sourceCode ->
            let
                opts =
                    { typesOnly = False }

                sourceFiles =
                    [ { path = "Test.elm"
                      , content = sourceCode
                      }
                    ]

                frontendResult : Result (List Compiler.Error) (Package.Definition Frontend.SourceLocation Frontend.SourceLocation)
                frontendResult =
                    Frontend.mapSource opts packageInfo Dict.empty sourceFiles

                typedResult : Result (List Compiler.Error) (Package.Definition () (Type ()))
                typedResult =
                    frontendResult
                        |> Result.andThen
                            (\packageDef ->
                                let
                                    thisPackageSpec : Package.Specification ()
                                    thisPackageSpec =
                                        packageDef
                                            |> Package.definitionToSpecificationWithPrivate
                                            |> Package.mapSpecificationAttributes (\_ -> ())

                                    ir : IR
                                    ir =
                                        Frontend.defaultDependencies
                                            |> Dict.insert packageInfo.name thisPackageSpec
                                            |> IR.fromPackageSpecifications
                                in
                                packageDef
                                    |> Package.mapDefinitionAttributes (\_ -> ()) identity
                                    |> Infer.inferPackageDefinition ir
                                    |> Result.map (Package.mapDefinitionAttributes (\_ -> ()) (\( _, tpe ) -> tpe))
                            )
            in
            ( { model
                | source = sourceCode
                , maybePackageDef =
                    case typedResult of
                        Ok newPackageDef ->
                            Just newPackageDef

                        Err _ ->
                            model.maybePackageDef
                , errors =
                    case typedResult of
                        Err errors ->
                            errors

                        Ok _ ->
                            []
              }
            , Cmd.none
            )



-- VIEW


view : Model -> Html Msg
view model =
    layout
        [ width fill
        , height fill
        , Font.family
            [ Font.external
                { name = "Source Code Pro"
                , url = "https://fonts.googleapis.com/css2?family=Source+Code+Pro&display=swap"
                }
            , Font.monospace
            ]
        , Font.size 16
        ]
        (el
            [ width fill
            , height fill
            ]
            (viewPackageResult model.source Change model.maybePackageDef model.errors)
        )


viewPackageResult : String -> (String -> msg) -> Maybe (Package.Definition () (Type ())) -> List Compiler.Error -> Element msg
viewPackageResult sourceCode onSourceChange maybePackageDef errors =
    row
        [ width fill
        , height fill
        , scrollbars
        ]
        [ column
            [ width fill
            , height fill
            , scrollbars
            ]
            [ el [ height shrink, padding 10 ] (text "Source Model")
            , el
                [ width fill
                , height fill
                , scrollbars
                ]
                (SourceEditor.view sourceCode onSourceChange)
            , el
                [ height shrink
                , width fill
                , padding 10
                , Background.color
                    (if List.isEmpty errors then
                        rgb 0.5 0.7 0.5

                     else
                        rgb 0.7 0.5 0.5
                    )
                ]
                (if List.isEmpty errors then
                    text "Parsed > Resolved > Type checked"

                 else
                    errors
                        |> List.concatMap
                            (\error ->
                                case error of
                                    Compiler.ErrorsInSourceFile _ sourceErrors ->
                                        sourceErrors
                                            |> List.map (.errorMessage >> text >> List.singleton >> paragraph [])

                                    Compiler.ErrorAcrossSourceFiles e ->
                                        [ Debug.toString e |> text ]
                            )
                        |> column []
                )
            ]
        , column
            [ width fill
            , height fill
            , scrollbars
            ]
            [ el [ height shrink, padding 10 ] (text "Morphir IR")
            , el
                [ width fill
                , height fill
                , scrollbars
                , padding 10
                ]
                (case maybePackageDef of
                    Just packageDef ->
                        viewPackageDefinition (\_ -> Html.div [] []) packageDef

                    Nothing ->
                        Element.none
                )
            ]
        ]


viewPackageDefinition : (va -> Html msg) -> Package.Definition () (Type ()) -> Element msg
viewPackageDefinition viewAttribute packageDef =
    packageDef.modules
        |> Dict.toList
        |> List.map
            (\( moduleName, moduleDef ) -> viewModuleDefinition viewAttribute moduleDef.value)
        |> column []


viewModuleDefinition : (va -> Html msg) -> Module.Definition () (Type ()) -> Element msg
viewModuleDefinition viewAttribute moduleDef =
    column []
        [ moduleDef.types
            |> viewDict
                (\typeName -> text (typeName |> Name.toHumanWords |> String.join " "))
                (\typeDef -> text (Debug.toString typeDef))
        , moduleDef.values
            |> Dict.toList
            |> List.map
                (\( valueName, valueDef ) ->
                    column
                        [ Background.color (rgb 0.9 0.9 0.9)
                        , Border.rounded 5
                        , padding 5
                        , spacing 5
                        ]
                        [ el
                            [ Border.rounded 5
                            , Background.color (rgb 0.95 0.95 0.95)
                            , width fill
                            ]
                            (row []
                                [ el [ paddingXY 10 5 ] (text (nameToText valueName))
                                , row
                                    [ paddingXY 10 5
                                    , spacing 5
                                    , Background.color (rgb 1 0.9 0.8)
                                    ]
                                    [ text ":"
                                    , XRayView.viewType valueDef.value.outputType
                                    ]
                                ]
                            )
                        , if List.isEmpty valueDef.value.inputTypes then
                            none

                          else
                            el
                                [ padding 5
                                , Border.rounded 5
                                , Background.color (rgb 0.95 0.95 0.95)
                                , width fill
                                ]
                                (valueDef.value.inputTypes
                                    |> List.map
                                        (\( argName, _, argType ) ->
                                            row []
                                                [ el [ paddingXY 10 5 ] (text (nameToText argName))
                                                , row
                                                    [ paddingXY 10 5
                                                    , spacing 5
                                                    , Background.color (rgb 1 0.9 0.8)
                                                    ]
                                                    [ text ":"
                                                    , XRayView.viewType argType
                                                    ]
                                                ]
                                        )
                                    |> column [ spacing 5 ]
                                )
                        , el
                            [ padding 5
                            , Border.rounded 5
                            , Background.color (rgb 1 1 1)
                            , width fill
                            ]
                            (XRayView.viewValueDefinition
                                (\tpe ->
                                    row
                                        [ spacing 5
                                        , Background.color (rgb 1 0.9 0.8)
                                        ]
                                        [ text ":"
                                        , XRayView.viewType tpe
                                        ]
                                )
                                valueDef
                            )
                        ]
                )
            |> column [ spacing 20 ]
        ]


viewFields : List ( Element msg, Element msg ) -> Element msg
viewFields fields =
    fields
        |> List.map
            (\( key, value ) ->
                column []
                    [ key
                    , el [ paddingXY 10 5 ] value
                    ]
            )
        |> column []


viewDict : (comparable -> Element msg) -> (v -> Element msg) -> Dict comparable v -> Element msg
viewDict viewKey viewVal dict =
    dict
        |> Dict.toList
        |> List.map
            (\( key, value ) ->
                column []
                    [ viewKey key
                    , el [ paddingXY 10 5 ]
                        (viewVal value)
                    ]
            )
        |> column []


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none


packageInfo =
    { name = [ [ "my" ] ]
    , exposedModules = Set.fromList [ [ [ "test" ] ] ]
    }


sampleSource : String
sampleSource =
    """module My.Test exposing (..)

basicLiteralBool : Bool
basicLiteralBool =
    True


basicLiteralChar : Char
basicLiteralChar =
    'Z'


basicLiteralString : String
basicLiteralString =
    "foo bar"


basicLiteralInt : Int
basicLiteralInt =
    42


basicLiteralFloat : Float
basicLiteralFloat =
    3.14


basicTuple2 : ( Int, String )
basicTuple2 =
    ( 13, "Tuple Two" )


basicTuple3 : ( Bool, Int, Bool )
basicTuple3 =
    ( True, 14, False )


basicListEmpty : List Int
basicListEmpty =
    []


basicListOne : List String
basicListOne =
    [ "single element" ]


basicListMany : List Char
basicListMany =
    [ 'a', 'b', 'c', 'd' ]


basicRecordEmpty : {}
basicRecordEmpty =
    {}


basicRecordOne : { foo : String }
basicRecordOne =
    { foo = "bar"
    }


basicRecordMany : { foo : String, bar : Bool, baz : Int }
basicRecordMany =
    { foo = "bar"
    , bar = False
    , baz = 15
    }


basicField : { foo : String } -> String
basicField rec =
    rec.foo


basicFieldFunction : { foo : String } -> String
basicFieldFunction =
    .foo


basicLetDefinition : Int
basicLetDefinition =
    let
        a : Int
        a =
            1

        b : Int
        b =
            a

        d : Int -> Int
        d i =
            i
    in
    d b


basicLetRecursion : Int
basicLetRecursion =
    let
        a : Int -> Int
        a i =
            b (i - 1)

        b : Int -> Int
        b i =
            if i < 0 then
                0

            else
                a i
    in
    a 10


basicDestructure : Int
basicDestructure =
    let
        ( a, b ) =
            ( 1, 2 )
    in
    b


basicIfThenElse : Int -> Int -> String
basicIfThenElse a b =
    if a < b then
        "Less"

    else
        "Greater or equal"


basicPatternMatchWildcard : String -> Int
basicPatternMatchWildcard s =
    case s of
        _ ->
            1


basicUnit : ()
basicUnit =
    ()
        """
