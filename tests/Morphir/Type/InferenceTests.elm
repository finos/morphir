module Morphir.Type.InferenceTests exposing (..)

import Dict
import Expect
import Morphir.IR.FQName exposing (FQName, fQName, fqn)
import Morphir.IR.Literal as Literal
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Type.Inference as Inference exposing (Constraint(..), Substitutions, TypeError(..))
import Morphir.Type.MetaType as MetaType exposing (MetaType(..))
import Test exposing (Test, describe, test)


inferPositiveTests : Test
inferPositiveTests =
    let
        boolType =
            Type.Reference () (fqn "Morphir.SDK" "Basics" "Bool") []

        boolLit =
            Value.Literal boolType
                (Literal.BoolLiteral False)

        stringType =
            Type.Reference () (fqn "Morphir.SDK" "String" "String") []

        stringLit =
            Value.Literal stringType
                (Literal.StringLiteral "foo")

        listType itemType =
            Type.Reference () (fqn "Morphir.SDK" "List" "List") [ itemType ]

        scenarios : List (Value () (Type ()))
        scenarios =
            [ boolLit
            , stringLit
            , Value.Tuple (Type.Tuple () [ stringType, boolType, stringType ])
                [ stringLit, boolLit, stringLit ]
            , Value.List (listType stringType)
                [ stringLit, stringLit ]
            ]
    in
    describe "inferValueTypes positive tests"
        (scenarios
            |> List.indexedMap
                (\index scenario ->
                    test ("Scenario " ++ String.fromInt index)
                        (\_ ->
                            let
                                typedValue : Value () ( Type (), () )
                                typedValue =
                                    scenario
                                        |> Value.mapValueAttributes identity (\tpe -> ( tpe, () ))

                                untypedValue : Value () ()
                                untypedValue =
                                    scenario
                                        |> Value.mapValueAttributes identity (always ())
                            in
                            Inference.inferValueTypes untypedValue
                                |> Expect.equal (Ok typedValue)
                        )
                )
        )



--inferNegativeTests : Test
--inferNegativeTests =
--    let
--        boolLit =
--            Value.Literal () (Literal.BoolLiteral False)
--
--        stringLit =
--            Value.Literal () (Literal.StringLiteral "foo")
--
--        scenarios : List ( Value () (), TypeError )
--        scenarios =
--            [ ( Value.List () [ stringLit, boolLit ]
--              , TypeErrors []
--              )
--            ]
--    in
--    describe "inferValueTypes negative tests"
--        (scenarios
--            |> List.indexedMap
--                (\index ( untypedValue, expectedError ) ->
--                    test ("Scenario " ++ String.fromInt index)
--                        (\_ ->
--                            Inference.inferValueTypes untypedValue
--                                |> Expect.equal (Err expectedError)
--                        )
--                )
--        )


generateValueConstraintsTests : Test
generateValueConstraintsTests =
    let
        mtv i =
            ( i, 0 )

        boolLit var =
            Value.Literal ( var, () ) (Literal.BoolLiteral False)

        stringLit var =
            Value.Literal ( var, () ) (Literal.StringLiteral "foo")

        scenarios : List ( Value () ( MetaType.Variable, () ), Constraint )
        scenarios =
            [ ( Value.List ( mtv 0, () ) [ stringLit (mtv 1), boolLit (mtv 2) ]
              , CAnd
                    [ CEqual (MetaVar ( 0, 0 )) (MetaApply (MetaRef (fqn "Morphir.SDK" "List" "List")) (MetaVar ( 0, 1 )))
                    , CEqual (MetaVar ( 0, 1 )) (MetaVar ( 1, 0 ))
                    , CEqual (MetaVar ( 1, 0 )) (MetaRef (fqn "Morphir.SDK" "String" "String"))
                    , CEqual (MetaVar ( 0, 1 )) (MetaVar ( 2, 0 ))
                    , CEqual (MetaVar ( 2, 0 )) (MetaRef (fqn "Morphir.SDK" "Basics" "Bool"))
                    ]
              )
            ]
    in
    describe "generateValueConstraints"
        (scenarios
            |> List.indexedMap
                (\index ( value, expectedConstraint ) ->
                    test ("Scenario " ++ String.fromInt index)
                        (\_ ->
                            Inference.generateValueConstraints value
                                |> Expect.equal expectedConstraint
                        )
                )
        )


solveConstraintTests : Test
solveConstraintTests =
    let
        boolType =
            MetaRef (fqn "Morphir.SDK" "Basics" "Bool")

        stringType =
            MetaRef (fqn "Morphir.SDK" "String" "String")

        mtv i =
            ( i, 0 )

        boolLit var =
            Value.Literal ( var, () ) (Literal.BoolLiteral False)

        stringLit var =
            Value.Literal ( var, () ) (Literal.StringLiteral "foo")

        scenarios : List ( Constraint, Result TypeError Substitutions )
        scenarios =
            [ ( CAnd
                    [ CEqual (MetaVar ( 1, 0 )) (MetaTuple [ MetaVar ( 5, 0 ), MetaVar ( 4, 0 ) ])
                    , CEqual (MetaVar ( 5, 0 )) stringType
                    , CEqual (MetaVar ( 4, 0 )) boolType
                    , CEqual (MetaVar ( 6, 0 )) stringType
                    , CEqual (MetaVar ( 7, 0 )) stringType
                    , CEqual (MetaVar ( 6, 0 )) (MetaVar ( 3, 0 ))
                    , CEqual (MetaVar ( 7, 0 )) (MetaVar ( 3, 0 ))
                    , CEqual (MetaVar ( 2, 0 )) (MetaTuple [ MetaVar ( 1, 0 ), MetaVar ( 3, 0 ) ])
                    ]
              , Ok
                    (Dict.fromList
                        [ ( ( 0, 0 ), MetaApply (MetaRef (fqn "Morphir.SDK" "List" "List")) (MetaVar ( 1, 0 )) )
                        , ( ( 0, 1 ), MetaVar ( 1, 0 ) )
                        ]
                    )
              )
            , ( CEqual (MetaVar ( 0, 0 )) (MetaApply (MetaRef (fqn "Morphir.SDK" "List" "List")) (MetaVar ( 0, 1 )))
              , Ok
                    (Dict.fromList
                        [ ( ( 0, 0 ), MetaApply (MetaRef (fqn "Morphir.SDK" "List" "List")) (MetaVar ( 0, 1 )) )
                        ]
                    )
              )
            , ( CAnd
                    [ CEqual (MetaVar ( 0, 0 )) (MetaApply (MetaRef (fqn "Morphir.SDK" "List" "List")) (MetaVar ( 0, 1 )))
                    , CEqual (MetaVar ( 0, 1 )) (MetaVar ( 1, 0 ))
                    ]
              , Ok
                    (Dict.fromList
                        [ ( ( 0, 0 ), MetaApply (MetaRef (fqn "Morphir.SDK" "List" "List")) (MetaVar ( 1, 0 )) )
                        , ( ( 0, 1 ), MetaVar ( 1, 0 ) )
                        ]
                    )
              )
            , ( CAnd
                    [ CEqual (MetaVar ( 0, 0 )) (MetaApply (MetaRef (fqn "Morphir.SDK" "List" "List")) (MetaVar ( 0, 1 )))
                    , CEqual (MetaVar ( 0, 1 )) (MetaVar ( 1, 0 ))
                    , CEqual (MetaVar ( 1, 0 )) (MetaRef (fqn "Morphir.SDK" "String" "String"))
                    ]
              , Ok
                    (Dict.fromList
                        [ ( ( 0, 0 ), MetaApply (MetaRef (fqn "Morphir.SDK" "List" "List")) (MetaRef (fqn "Morphir.SDK" "String" "String")) )
                        , ( ( 0, 1 ), MetaRef (fqn "Morphir.SDK" "String" "String") )
                        , ( ( 1, 0 ), MetaRef (fqn "Morphir.SDK" "String" "String") )
                        ]
                    )
              )
            , ( CAnd
                    [ CEqual (MetaVar ( 0, 0 )) (MetaApply (MetaRef (fqn "Morphir.SDK" "List" "List")) (MetaVar ( 0, 1 )))
                    , CEqual (MetaVar ( 0, 1 )) (MetaVar ( 1, 0 ))
                    , CEqual (MetaVar ( 1, 0 )) (MetaRef (fqn "Morphir.SDK" "String" "String"))
                    , CEqual (MetaVar ( 0, 1 )) (MetaVar ( 2, 0 ))
                    ]
              , Ok
                    (Dict.fromList
                        [ ( ( 0, 0 ), MetaApply (MetaRef (fqn "Morphir.SDK" "List" "List")) (MetaRef (fqn "Morphir.SDK" "String" "String")) )
                        , ( ( 0, 1 ), MetaRef (fqn "Morphir.SDK" "String" "String") )
                        , ( ( 1, 0 ), MetaRef (fqn "Morphir.SDK" "String" "String") )
                        ]
                    )
              )

            --, ( CAnd
            --        [ CEqual (MetaVar ( 0, 0 )) (MetaApply (MetaRef (fqn "Morphir.SDK" "List" "List")) (MetaVar ( 0, 1 )))
            --        , CEqual (MetaVar ( 0, 1 )) (MetaVar ( 1, 0 ))
            --        , CEqual (MetaVar ( 1, 0 )) (MetaRef (fqn "Morphir.SDK" "String" "String"))
            --        , CEqual (MetaVar ( 0, 1 )) (MetaVar ( 2, 0 ))
            --        , CEqual (MetaVar ( 2, 0 )) (MetaRef (fqn "Morphir.SDK" "Basics" "Bool"))
            --        ]
            --  , Dict.empty
            --  , Ok
            --        (Dict.fromList
            --            [ ( ( 0, 0 ), MetaApply (MetaRef (FQName [ [ "morphir" ], [ "s", "d", "k" ] ] [ [ "list" ] ] [ "list" ])) (MetaRef (FQName [ [ "morphir" ], [ "s", "d", "k" ] ] [ [ "string" ] ] [ "string" ])) )
            --            , ( ( 0, 1 ), MetaRef (FQName [ [ "morphir" ], [ "s", "d", "k" ] ] [ [ "string" ] ] [ "string" ]) )
            --            , ( ( 1, 0 ), MetaRef (FQName [ [ "morphir" ], [ "s", "d", "k" ] ] [ [ "string" ] ] [ "string" ]) )
            --            , ( ( 2, 0 ), MetaRef (FQName [ [ "morphir" ], [ "s", "d", "k" ] ] [ [ "basics" ] ] [ "bool" ]) )
            --            ]
            --        )
            --  )
            ]
    in
    describe "solveConstraint"
        (scenarios
            |> List.indexedMap
                (\index ( constraint, expectedResult ) ->
                    test ("Scenario " ++ String.fromInt index)
                        (\_ ->
                            Inference.solveConstraint constraint
                                |> Expect.equal expectedResult
                        )
                )
        )
