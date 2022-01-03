module Morphir.Web.TryMorphir exposing (..)

import Browser
import Dict exposing (Dict)
import Element exposing (Element, alignRight, column, el, fill, height, layout, none, padding, paddingXY, paragraph, rgb, row, scrollbars, shrink, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Html exposing (Attribute, Html)
import Json.Encode as Encode
import Morphir.Compiler as Compiler
import Morphir.Elm.Frontend as Frontend exposing (Errors, SourceFile, SourceLocation)
import Morphir.IR as IR exposing (IR)
import Morphir.IR.AccessControlled exposing (AccessControlled)
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name
import Morphir.IR.Package as Package
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Type.Codec as TypeCodec
import Morphir.IR.Value as Value
import Morphir.IR.Value.Codec as ValueCodec
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
    , irView : IRView
    }


type IRView
    = VisualView
    | JsonView


init : Flags -> ( Model, Cmd Msg )
init flags =
    update (ChangeSource sampleSource) { source = "", maybePackageDef = Nothing, errors = [], irView = VisualView }


moduleSource : String -> SourceFile
moduleSource sourceValue =
    { path = "Test.elm"
    , content = sourceValue
    }



-- UPDATE


type Msg
    = ChangeSource String
    | ChangeIRView IRView


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ChangeSource sourceCode ->
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

        ChangeIRView viewType ->
            ( { model
                | irView = viewType
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
            (viewPackageResult model.source ChangeSource model.maybePackageDef model.errors model.irView)
        )


viewPackageResult : String -> (String -> Msg) -> Maybe (Package.Definition () (Type ())) -> List Compiler.Error -> IRView -> Element Msg
viewPackageResult sourceCode onSourceChange maybePackageDef errors irView =
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
            [ row [ width fill ]
                [ el [ height shrink, padding 10 ] (text "Morphir IR")
                , viewIRViewTabs irView
                ]
            , el
                [ width fill
                , height fill
                , scrollbars
                , padding 10
                ]
                (case maybePackageDef of
                    Just packageDef ->
                        viewPackageDefinition (\_ -> Html.div [] []) packageDef irView

                    Nothing ->
                        Element.none
                )
            ]
        ]


viewPackageDefinition : (va -> Html Msg) -> Package.Definition () (Type ()) -> IRView -> Element Msg
viewPackageDefinition viewAttribute packageDef irView =
    packageDef.modules
        |> Dict.toList
        |> List.map
            (\( moduleName, moduleDef ) -> viewModuleDefinition viewAttribute moduleDef.value irView)
        |> column []


viewModuleDefinition : (va -> Html Msg) -> Module.Definition () (Type ()) -> IRView -> Element Msg
viewModuleDefinition viewAttribute moduleDef irView =
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
                            (viewValue irView valueDef)
                        ]
                )
            |> column [ spacing 20 ]
        ]


viewValue : IRView -> AccessControlled (Value.Definition () (Type ())) -> Element Msg
viewValue irView valueDef =
    case irView of
        VisualView ->
            XRayView.viewValueDefinition
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

        JsonView ->
            ValueCodec.encodeValue (always Encode.null) (TypeCodec.encodeType (always Encode.null)) valueDef.value.body
                |> Encode.encode 2
                |> text


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


viewIRViewTabs : IRView -> Element Msg
viewIRViewTabs irView =
    let
        button viewType labelText =
            Input.button
                [ paddingXY 10 5
                , Background.color
                    (if viewType == irView then
                        rgb 0.8 0.85 0.9

                     else
                        rgb 0.9 0.9 0.9
                    )
                , Border.rounded 3
                ]
                { onPress = Just (ChangeIRView viewType)
                , label = el [] (text labelText)
                }
    in
    row
        [ alignRight
        , paddingXY 10 0
        , spacing 10
        ]
        [ button VisualView "Visual"
        , button JsonView "JSON"
        ]


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none


packageInfo =
    { name = [ [ "my" ] ]
    , exposedModules = Nothing
    }


sampleSource : String
sampleSource =
    """module My.Test exposing (..)

bar : List a
bar =
    if True then
        [ 1.5 ]
    else
        [ 1 ]

foo : Bool -> Int
foo myBool =
    if myBool then
        1 + 5
    else
        0
        """
