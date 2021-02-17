module Morphir.Visual.BoolOperatorTree exposing (..)

import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Value as Value exposing (TypedValue)


type BoolOperatorTree
    = BoolOperatorBranch BoolOperator (List BoolOperatorTree)
    | BoolValueLeaf TypedValue


type BoolOperator
    = And
    | Or


fromTypedValue : TypedValue -> BoolOperatorTree
fromTypedValue typedValue =
    case typedValue of
        Value.Apply _ fun arg ->
            let
                ( function, args ) =
                    Value.uncurryApply fun arg
            in
            case ( function, args ) of
                ( Value.Reference _ ( _, moduleName, localName ), [ arg1, arg2 ] ) ->
                    let
                        operatorName : String
                        operatorName =
                            functionName moduleName localName
                    in
                    case operatorName of
                        "Basics.or" ->
                            BoolOperatorBranch Or (helperFunction typedValue operatorName)

                        "Basics.and" ->
                            BoolOperatorBranch And (helperFunction typedValue operatorName)

                        _ ->
                            BoolValueLeaf typedValue

                _ ->
                    BoolValueLeaf typedValue

        _ ->
            BoolValueLeaf typedValue


helperFunction : TypedValue -> String -> List BoolOperatorTree
helperFunction value operatorName =
    case value of
        Value.Apply _ fun arg ->
            let
                ( function, args ) =
                    Value.uncurryApply fun arg
            in
            case ( function, args ) of
                ( Value.Reference _ ( _, moduleName, localName ), [ arg1, arg2 ] ) ->
                    if functionName moduleName localName == operatorName then
                        helperFunction arg1 operatorName ++ helperFunction arg2 operatorName

                    else
                        [ fromTypedValue value ]

                _ ->
                    [ BoolValueLeaf value ]

        _ ->
            [ BoolValueLeaf value ]


functionName : Path -> Name -> String
functionName moduleName localName =
    String.join "."
        [ moduleName |> Path.toString Name.toTitleCase "."
        , localName |> Name.toCamelCase
        ]
