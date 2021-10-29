module Morphir.Web.MultiaryDecisionTreeTest exposing (..)

import Dict
import Element exposing (Element, column, el, fill, layout, none, padding, paddingEach, px, row, spacing, table, text)
import Html exposing (Html)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name
import Morphir.IR.Package as Package
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value
import Morphir.Visual.Components.MultiaryDecisionTree exposing (Node(..))
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.Theme as Theme
import Morphir.Visual.ViewPattern as ViewPattern
import Morphir.Visual.ViewValue as ViewValue


main : Html Msg
main =
    -- minimalistic example
    -- need an update function
    --let
    --    cara : Element Msg
    --    cara =
    --        text "Cara"
    --in arrowHelper labels (Element.text "cara")
    layout
        []
        <|
        (el [ padding 10 ]

            (column [ spacing 20 ]
             -- column layout and spacing between layout
                (examples
                -- pipe to make it the last function
                -- collection is always last argument
                    |> List.indexedMap
                    -- takes a list and returns another lsit --> in real world we would probably be okay with .map
                        (\index example ->
                            column [ spacing 10 ]
                                [ text ("Example " ++ String.fromInt (index + 1))
                                , column [ spacing 5 ] (viewNode 0 Nothing example)
                                ]
                        )
                )
            )
        )




type Msg
    = NoMsg

-- depth should always be passed zero
-- next steps
    -- extending visualization to take extra state --> expand state --- > bool next to tree
    -- 1) incorporating this in multiarydecisiontree --> creating the data structure from the ir
    -- 2) creating buttons
    -- 3) update function
    -- 4) general ui
    -- 5) expanding and collasping
    -- 6) highlighting

-- helping ui :
    -- help spacing through ??
        -- html 5: outlining tool, css
        -- adding classes, style classes anywhere
        -- design html outline properly --> tests should confirm
        -- how elm separates everything
    -- add buttons into branches
    -- add arrows into leafs

-- work on figuring out spacing for arrows

-- good ui representation
-- keeping an eye on elm features



-- one more thing when you get into standing and collasping --> will get called in as a model

-- creates a list with the right implementation
-- indent right determines what to implement
-- change had coded name
-- show tuple as grid when it is input
    -- show multiple columns
viewNode : Int -> Maybe (Element Msg) -> Node -> List (Element Msg)
viewNode depth maybeLabel node =
    let
        indentRight by =
            paddingEach
                { left = by * 20
                , right = 0
                , top = 0
                , bottom = 0
                }

        label =
            case maybeLabel of
                Just l ->
                    --row [] [ l, text " -> " ]
                    arrowHelper labels l

                Nothing ->
                    none
    in
    case node of
        -- viewvalue is what can display anything

        Branch branch ->
            -- shows condition of the branch
            List.concat
                [ [ row [ indentRight depth ] [ text " - ", label, ViewValue.viewValue dummyConfig branch.subject ] ]
                --- for all the bracnhes it recursively calls
                -- sets the label based on the pattern pased through in the tuple
                , branch.branches
                    |> List.concatMap
                        (\( casePattern, caseBody ) ->
                            viewNode (depth + 1) (Just (text (ViewPattern.patternAsText casePattern))) caseBody
                        )
                ]
        -- if its a leaf, just creates signal row, shows label and actual body
        -- label comes from the level above
        Leaf visualTypedValue ->
            [ row [ indentRight depth ] [ text " - ", label, ViewValue.viewValue dummyConfig visualTypedValue ] ]
-- update : take a state, pass in message this is the expected state
-- the read in  part will need to be updates
examples =
    let
        dummyAnnotation =
            ( 0, Type.Unit () )

        var name =
            Value.Variable dummyAnnotation (Name.fromString name)
    in
    [ Branch
        { subject = var "isFoo"
        , subjectEvaluationResult = Nothing
        , branches =
            [ ( Value.LiteralPattern () (BoolLiteral True), Leaf (var "yes") )
            , ( Value.LiteralPattern () (BoolLiteral False), Leaf (var "no") )
            ]
        }
    , Branch
        { subject = var "isFoo"
        , subjectEvaluationResult = Nothing
        , branches =
            [ ( Value.LiteralPattern () (BoolLiteral True)
              , Branch
                    { subject = var "isBar"
                    , subjectEvaluationResult = Nothing
                    , branches =
                        [ ( Value.LiteralPattern () (BoolLiteral True), Leaf (var "yesAndYes") )
                        , ( Value.LiteralPattern () (BoolLiteral False), Leaf (var "yar") )
                        ]
                    }
              )
            , ( Value.LiteralPattern () (BoolLiteral False), Leaf (var "no") )
            ]
        }
    , Branch
        { subject = var "cara"
        , subjectEvaluationResult = Nothing
        , branches =
            [ ( Value.ConstructorPattern () (FQName.fromString "My:Sample:EnumValue1" ":") [], Leaf (var "foo") )
            , ( Value.ConstructorPattern () (FQName.fromString "My:Sample:EnumValue2" ":") [], Leaf (var "bar") )
            , ( Value.WildcardPattern (), Leaf (var "baz") )
            ]
        }


    ]


dummyConfig : Config Msg
dummyConfig =
    { irContext =
        { distribution = Library [] Dict.empty Package.emptyDefinition
        , nativeFunctions = Dict.empty
        }
    , state =
        { expandedFunctions = Dict.empty
        , variables = Dict.empty
        , popupVariables =
            { variableIndex = -1
            , variableValue = Nothing
            }
        , theme = Theme.fromConfig Nothing
        , highlightState = Nothing
        }
    , handlers =
        { onReferenceClicked = \_ _ -> NoMsg
        , onHoverOver = \_ _ -> NoMsg
        , onHoverLeave = \_ -> NoMsg
        }
    }

type alias LabelUI =
        { label :  Element Msg
        , arrow : String
        }

labels : Element Msg -> List LabelUI
labels maybelLabel =
    [ { label = maybelLabel , arrow = "->"}
    ]

arrowHelper: (Element Msg -> List LabelUI) -> Element Msg -> Element Msg

arrowHelper newLabel message =
    Element.table []
            { data = newLabel message
            , columns =
                [ { header = none
                  , width = px 150
                  , view =
                        \myLabel ->
                            myLabel.label
                  }
                , { header = none
                  , width = px 150
                  , view =
                        \myLabel ->
                            Element.text myLabel.arrow
                  }
                ]
            }