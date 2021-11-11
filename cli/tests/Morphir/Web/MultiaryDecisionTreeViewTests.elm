module Morphir.Web.MultiaryDecisionTreeViewTests exposing (..)

import List exposing (length)
import Morphir.IR.Name as Name
import Morphir.IR.Type as Type
import Morphir.Visual.Components.MultiaryDecisionTree exposing (Node(..))

import Element exposing (column, el, layout, none, padding, paddingEach, row, spacing, text)
import Expect
import Html exposing (label, var)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Value as Value
import Morphir.Visual.Components.MultiaryDecisionTree exposing (Node(..))
import Morphir.Visual.ViewPattern as ViewPattern
import Morphir.Web.MultiaryDecisionTreeTest as MultiaryDecisionTreeTest exposing (..)
import Test exposing (..)


checkText : Test
checkText =
     test "1 Branch" <|
     \_ ->
       ( MultiaryDecisionTreeTest.main)
       |> Expect.equal (layout
                                []
                                (el [ padding 10 ]
                                    (column [ spacing 20 ]
                                        (examples
                                            |> List.indexedMap
                                                (\index example ->
                                                    column [ spacing 10 ]
                                                        [ text ("Example " ++ String.fromInt (index + 1))
                                                        , column [ spacing 5 ] (viewNode 0 Nothing example)
                                                        ]
                                                )
                                        )
                                    )
                                ))
