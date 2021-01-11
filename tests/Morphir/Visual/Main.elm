module Morphir.Visual.Main exposing (main, sampleValues)

import Dict
import Element
import Html
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Type.Infer as Infer
import Morphir.Visual.ViewValue as ViewValue


sampleValues : List (Value () ())
sampleValues =
    [ Value.Literal () (BoolLiteral True)
    , Value.Literal () (CharLiteral 'x')
    , Value.Literal () (StringLiteral "foo")
    , Value.Literal () (IntLiteral 123)
    , Value.Literal () (FloatLiteral 3.14)
    , Value.List ()
        [ Value.Literal () (IntLiteral 1)
        , Value.Literal () (IntLiteral 12)
        , Value.Literal () (IntLiteral 123)
        ]
    , Value.List ()
        [ Value.Record ()
            [ ( [ "foo" ], Value.Literal () (IntLiteral 1) )
            , ( [ "bar" ], Value.Literal () (StringLiteral "one") )
            ]
        , Value.Record ()
            [ ( [ "foo" ], Value.Literal () (IntLiteral 12) )
            , ( [ "bar" ], Value.Literal () (StringLiteral "twelve") )
            ]
        , Value.Record ()
            [ ( [ "foo" ], Value.Literal () (IntLiteral 123) )
            , ( [ "bar" ], Value.Literal () (StringLiteral "hundred and twenty-three") )
            ]
        ]
    ]


main =
    Html.table
        []
        [ Html.tbody []
            (sampleValues
                |> List.map
                    (\value ->
                        Html.tr []
                            [ {- Html.td []
                                     [ Html.text (Debug.toString value)
                                     ]
                                 ,
                              -}
                              Html.td []
                                [ case Infer.inferValue Dict.empty value of
                                    Ok typedValue ->
                                        typedValue
                                            |> Value.mapValueAttributes identity Tuple.second
                                            |> ViewValue.viewValue
                                            |> Element.layoutWith
                                                { options = [ Element.noStaticStyleSheet ]
                                                }
                                                []

                                    Err error ->
                                        Html.text (Debug.toString error)
                                ]
                            ]
                    )
            )
        ]
