module Morphir.Web.DevelopApp.ModulePage exposing (..)

import Dict exposing (Dict)
import Element exposing (Element, alignRight, alignTop, column, el, explain, fill, height, link, padding, paddingXY, rgb, row, scrollbars, shrink, spacing, text, width, wrappedRow)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input exposing (labelHidden)
import Morphir.IR as IR exposing (IR)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.SDK as SDK
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue)
import Morphir.Visual.Common exposing (nameToText)
import Morphir.Visual.Components.FieldList as FieldList
import Morphir.Visual.Config exposing (Config, PopupScreenRecord)
import Morphir.Visual.Theme as Theme exposing (Theme)
import Morphir.Visual.ValueEditor as ValueEditor
import Morphir.Visual.ViewValue as ViewValue
import Morphir.Visual.XRayView as XRayView
import Morphir.Web.DevelopApp.Common exposing (viewAsCard)
import Url.Parser as UrlParser exposing (..)
import Url.Parser.Query as Query


type alias Model =
    { moduleName : List String
    , filter : Maybe String
    , viewType : ViewType
    , argState : Dict FQName (Dict Name ValueEditor.EditorState)
    , expandedValues : Dict ( FQName, Name ) (Value.Definition () (Type ()))
    , popupVariables : PopupScreenRecord
    }


type alias Handlers msg =
    { expandReference : FQName -> Bool -> msg
    , expandVariable : Int -> Maybe RawValue -> msg
    , shrinkVariable : Int -> msg
    , argValueUpdated : FQName -> Name -> ValueEditor.EditorState -> msg
    , invalidArgValue : FQName -> Name -> String -> msg
    , jumpToTestCases : FQName -> msg
    }


routeParser : UrlParser.Parser (Model -> a) a
routeParser =
    UrlParser.map
        (\moduleName filter viewType ->
            { moduleName = moduleName
            , filter =
                filter
                    |> Maybe.map
                        (\filterString ->
                            if String.endsWith "*" filterString then
                                filterString |> String.dropRight 1

                            else
                                filterString
                        )
            , viewType = viewType
            , argState = Dict.empty
            , expandedValues = Dict.empty
            , popupVariables = PopupScreenRecord 0 Nothing
            }
        )
        (UrlParser.s "module"
            </> (UrlParser.string |> UrlParser.map (String.split "."))
            <?> Query.string "filter"
            <?> (Query.string "view" |> Query.map (Maybe.map viewTypeFromString >> Maybe.withDefault InsightView))
        )


type ViewType
    = XRayView
    | InsightView


viewTypeFromString : String -> ViewType
viewTypeFromString string =
    case string of
        "insight" ->
            InsightView

        _ ->
            XRayView


viewTitle : Model -> String
viewTitle model =
    "Morphir - " ++ (model.moduleName |> String.join " / ")


viewPage : Theme -> Handlers msg -> (String -> msg) -> Distribution -> Model -> Element msg
viewPage theme handlers valueFilterChanged ((Library packageName _ packageDef) as distribution) model =
    let
        moduleName =
            model.moduleName |> List.map Name.fromString

        ir : IR
        ir =
            IR.fromDistribution distribution
    in
    case packageDef.modules |> Dict.get moduleName of
        Just accessControlledModuleDef ->
            column
                [ width fill
                , height fill
                , spacing (theme |> Theme.scaled 4)
                ]
                [ viewModuleControls theme valueFilterChanged model
                , wrappedRow
                    [ padding (theme |> Theme.scaled 4)
                    , spacing (theme |> Theme.scaled 4)
                    , width fill
                    , height fill
                    , scrollbars
                    ]
                    (accessControlledModuleDef.value.values
                        |> Dict.toList
                        |> List.filterMap
                            (\( valueName, accessControlledValueDef ) ->
                                let
                                    matchesFilter =
                                        case model.filter of
                                            Just filter ->
                                                String.contains
                                                    (filter |> String.toLower)
                                                    (valueName
                                                        |> Name.toHumanWords
                                                        |> List.map String.toLower
                                                        |> String.join " "
                                                    )

                                            Nothing ->
                                                True

                                    valueFQName =
                                        ( packageName, moduleName, valueName )
                                in
                                if matchesFilter then
                                    Just
                                        (el [ alignTop ]
                                            (viewAsCard theme
                                                (column [ width fill, spacing 5 ]
                                                    [ Theme.header theme
                                                        { left = [ nameToText valueName |> text ]
                                                        , middle = []
                                                        , right = [ theme |> Theme.button (handlers.jumpToTestCases valueFQName) "Scenarios" theme.colors.primaryHighlight ]
                                                        }
                                                    , viewArgumentEditors ir handlers model valueFQName accessControlledValueDef.value
                                                    ]
                                                )
                                                (case model.viewType of
                                                    InsightView ->
                                                        viewValue handlers model distribution valueFQName accessControlledValueDef.value

                                                    XRayView ->
                                                        XRayView.viewValueDefinition XRayView.viewType accessControlledValueDef
                                                )
                                            )
                                        )

                                else
                                    Nothing
                            )
                    )
                ]

        Nothing ->
            text (String.join " " [ "Module", model.moduleName |> String.join ".", "not found" ])


viewModuleControls : Theme -> (String -> msg) -> Model -> Element msg
viewModuleControls theme valueFilterChanged model =
    let
        viewTypeBackground expectedType =
            if model.viewType == expectedType then
                Background.color (rgb 0.8 0.8 0.8)

            else
                Background.color (rgb 1 1 1)
    in
    row
        [ width fill
        , spacing (theme |> Theme.scaled 2)
        , height shrink
        , padding 5
        ]
        [ Input.text
            [ paddingXY 10 4
            , Border.width 1
            , Border.rounded 10
            ]
            { onChange = valueFilterChanged
            , text = model.filter |> Maybe.withDefault ""
            , placeholder = Just (Input.placeholder [] (text "start typing to filter values ..."))
            , label = labelHidden "filter values"
            }
        , el []
            (row [ spacing 5 ]
                [ link [ paddingXY 6 4, Border.rounded 3, viewTypeBackground XRayView ]
                    { url = makeURL { model | viewType = XRayView }
                    , label = text "x-ray"
                    }
                , text "|"
                , link [ paddingXY 6 4, Border.rounded 3, viewTypeBackground InsightView ]
                    { url = makeURL { model | viewType = InsightView }
                    , label = text "insight"
                    }
                ]
            )
        ]


viewValue : Handlers msg -> Model -> Distribution -> FQName -> Value.Definition () (Type ()) -> Element msg
viewValue handlers model distribution valueFQName valueDef =
    let
        validArgValues : Dict Name RawValue
        validArgValues =
            model.argState
                |> Dict.get valueFQName
                |> Maybe.map (\args -> args |> Dict.map (\_ arg -> arg.lastValidValue |> Maybe.withDefault (Value.Unit ())))
                |> Maybe.withDefault Dict.empty

        config : Config msg
        config =
            { irContext =
                { distribution = distribution
                , nativeFunctions = SDK.nativeFunctions
                }
            , state =
                { expandedFunctions = model.expandedValues |> Dict.toList |> List.map (\( ( fQName, _ ), rawValue ) -> ( fQName, rawValue )) |> Dict.fromList
                , variables = validArgValues
                , popupVariables = model.popupVariables
                , theme = Theme.fromConfig Nothing
                }
            , handlers =
                { onReferenceClicked = handlers.expandReference
                , onHoverOver = handlers.expandVariable
                , onHoverLeave = handlers.shrinkVariable
                }
            }
    in
    ViewValue.viewDefinition config valueFQName valueDef


viewArgumentEditors : IR -> Handlers msg -> Model -> FQName -> Value.Definition () (Type ()) -> Element msg
viewArgumentEditors ir handlers model fQName valueDef =
    valueDef.inputTypes
        |> List.map
            (\( argName, _, argType ) ->
                ( argName
                , ValueEditor.view ir
                    argType
                    (handlers.argValueUpdated fQName argName)
                    (model.argState |> Dict.get fQName |> Maybe.andThen (Dict.get argName) |> Maybe.withDefault (ValueEditor.initEditorState ir argType Nothing))
                )
            )
        |> FieldList.view


makeURL : Model -> String
makeURL model =
    String.concat
        [ "/module/"
        , model.moduleName |> String.join "."
        , "?filter="
        , model.filter |> Maybe.withDefault ""
        , "&view="
        , case model.viewType of
            InsightView ->
                "insight"

            _ ->
                "raw"
        ]
