module Morphir.Visual.ViewApply exposing (view)

import Dict exposing (Dict)
import Element exposing (Element, column, fill, moveRight, row, spacing, text, width, wrappedRow)
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Visual.Common exposing (nameToText)


view : (Value ta (Type ta) -> Element msg) -> Value ta (Type ta) -> List (Value ta (Type ta)) -> Element msg
view viewValue functionValue argValues =
    case ( functionValue, argValues ) of
        ( Value.Reference _ (FQName _ _ (("is" :: _) as localName)), [ argValue ] ) ->
            row
                [ width fill
                , spacing 10
                ]
                [ viewValue argValue
                , text (nameToText localName)
                ]

        -- possibly binary operator
        ( Value.Reference _ (FQName [ [ "morphir" ], [ "s", "d", "k" ] ] moduleName localName), [ argValue1, argValue2 ] ) ->
            let
                functionName : String
                functionName =
                    String.join "."
                        [ moduleName |> Path.toString Name.toTitleCase "."
                        , localName |> Name.toCamelCase
                        ]
            in
            inlineBinaryOperators
                |> Dict.get functionName
                |> Maybe.map
                    (\functionText ->
                        row
                            [ width fill
                            , spacing 10
                            ]
                            [ viewValue argValue1
                            , text (" " ++ functionText ++ " ")
                            , viewValue argValue2
                            ]
                    )
                |> Maybe.withDefault
                    (column
                        [ spacing 10 ]
                        [ viewValue functionValue
                        , column
                            [ moveRight 10
                            , spacing 10
                            ]
                            (argValues
                                |> List.map viewValue
                            )
                        ]
                    )

        _ ->
            column
                [ spacing 10 ]
                [ viewValue functionValue
                , column
                    [ moveRight 10
                    , spacing 10
                    ]
                    (argValues
                        |> List.map viewValue
                    )
                ]


inlineBinaryOperators : Dict String String
inlineBinaryOperators =
    Dict.fromList
        [ ( "Basics.equal", "=" )
        , ( "Basics.lessThan", "<" )
        , ( "Basics.lessThanOrEqual", "<=" )
        , ( "Basics.greaterThan", ">" )
        , ( "Basics.greaterThanOrEqual", ">=" )
        , ( "Basics.add", "+" )
        , ( "Basics.subtract", "-" )
        , ( "Basics.multiply", "*" )
        , ( "Basics.divide", "/" )
        ]
