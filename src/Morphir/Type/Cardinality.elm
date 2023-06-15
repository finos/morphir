module Morphir.Type.Cardinality exposing (Cardinality, AlephNumber, cardinality)

{-| This module contains utilities to calculate the cardinality of types.

@docs Cardinality, AlephNumber, cardinality

-}

import Dict exposing (Dict)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Type as Type exposing (Type)


{-| Type cardinality represents the number of possible values for a given type.
<https://en.wikipedia.org/wiki/Cardinality>
-}
type Cardinality
    = Finite Int
    | Infinite AlephNumber
    | Unbound


{-| Represents an Aleph number that allows you to compare various levels of infinity
<https://en.wikipedia.org/wiki/Aleph_number>
-}
type alias AlephNumber =
    Int


{-| Calculate the cardinality of a type going down recursively in the type expression tree.
-}
cardinality : Distribution -> Dict Name (Type ()) -> Type () -> Cardinality
cardinality ir vars tpe =
    case Distribution.resolveType tpe ir of
        Type.Variable _ _ ->
            Unbound

        Type.Reference _ fQName typeArgs ->
            case Distribution.lookupTypeSpecification fQName ir of
                Just typeSpec ->
                    case typeSpec of
                        Type.TypeAliasSpecification _ _ ->
                            -- if it's still an alias after resolving we don't know what it is
                            Unbound

                        Type.OpaqueTypeSpecification _ ->
                            -- we don't know anything about opaque types
                            Unbound

                        Type.CustomTypeSpecification paramNames constructors ->
                            let
                                newVars : Dict Name (Type ())
                                newVars =
                                    List.map2 Tuple.pair paramNames typeArgs
                                        |> Dict.fromList
                            in
                            constructors
                                |> Dict.toList
                                |> List.map
                                    (\( _, ctorArgs ) ->
                                        ctorArgs
                                            |> List.map (Tuple.second >> cardinality ir newVars)
                                            |> List.foldl product unit
                                    )
                                |> List.foldl sum null

                        Type.DerivedTypeSpecification _ config ->
                            cardinality ir vars config.baseType

                Nothing ->
                    Unbound

        Type.Tuple _ elemTypes ->
            elemTypes
                |> List.map (cardinality ir vars)
                |> List.foldl product unit

        Type.Record _ fields ->
            fields
                |> List.map (.tpe >> cardinality ir vars)
                |> List.foldl product unit

        Type.ExtensibleRecord _ _ _ ->
            Unbound

        Type.Function _ argType returnType ->
            function (cardinality ir vars argType) (cardinality ir vars returnType)

        Type.Unit _ ->
            unit


null : Cardinality
null =
    Finite 0


unit : Cardinality
unit =
    Finite 1


sum : Cardinality -> Cardinality -> Cardinality
sum card1 card2 =
    case card1 of
        Finite number1 ->
            case card2 of
                Finite number2 ->
                    Finite (number1 + number2)

                Infinite alephNumber2 ->
                    Infinite alephNumber2

                Unbound ->
                    Unbound

        Infinite alephNumber1 ->
            case card2 of
                Finite _ ->
                    Infinite alephNumber1

                Infinite alephNumber2 ->
                    Infinite (max alephNumber1 alephNumber2)

                Unbound ->
                    Unbound

        Unbound ->
            Unbound


product : Cardinality -> Cardinality -> Cardinality
product card1 card2 =
    case card1 of
        Finite number1 ->
            case card2 of
                Finite number2 ->
                    Finite (number1 * number2)

                Infinite alephNumber2 ->
                    Infinite alephNumber2

                Unbound ->
                    Unbound

        Infinite alephNumber1 ->
            case card2 of
                Finite _ ->
                    Infinite alephNumber1

                Infinite alephNumber2 ->
                    Infinite (alephNumber1 + alephNumber2)

                Unbound ->
                    Unbound

        Unbound ->
            Unbound


function : Cardinality -> Cardinality -> Cardinality
function card1 card2 =
    case card1 of
        Finite number1 ->
            case card2 of
                Finite number2 ->
                    Finite (number2 ^ number1)

                Infinite alephNumber2 ->
                    Infinite alephNumber2

                Unbound ->
                    Unbound

        Infinite alephNumber1 ->
            case card2 of
                Finite _ ->
                    Infinite alephNumber1

                Infinite alephNumber2 ->
                    Infinite (alephNumber1 * alephNumber2)

                Unbound ->
                    Unbound

        Unbound ->
            Unbound
