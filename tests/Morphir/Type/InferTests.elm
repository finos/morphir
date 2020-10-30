module Morphir.Type.InferTests exposing (..)

import Dict exposing (Dict)
import Expect
import Morphir.IR.FQName exposing (fQName, fqn)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.SDK as SDK
import Morphir.IR.SDK.Basics exposing (boolType, floatType, intType)
import Morphir.IR.SDK.List exposing (listType)
import Morphir.IR.SDK.String exposing (stringType)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Type.Class as Class
import Morphir.Type.Constraint exposing (Constraint, class, equality)
import Morphir.Type.ConstraintSet as ConstraintSet
import Morphir.Type.Infer as Infer exposing (TypeError(..))
import Morphir.Type.MetaType as MetaType exposing (MetaType(..))
import Morphir.Type.MetaVar exposing (Variable, variable)
import Morphir.Type.SolutionMap as SolutionMap
import Test exposing (Test, describe, test)


testReferences : Dict PackageName (Package.Specification ())
testReferences =
    Dict.fromList
        [ ( [ [ "morphir" ], [ "s", "d", "k" ] ], SDK.packageSpec )
        ]


positiveOutcomes : List (Value () ( Int, Type () ))
positiveOutcomes =
    let
        isZeroType : Type ()
        isZeroType =
            Type.Function () (floatType ()) (boolType ())

        barRecordType : String -> Type ()
        barRecordType extends =
            Type.ExtensibleRecord ()
                (Name.fromString extends)
                [ Type.Field [ "bar" ] (floatType ())
                ]
    in
    -- if then else
    [ Value.IfThenElse ( 1, floatType () )
        (Value.Literal ( 2, boolType () ) (BoolLiteral False))
        (Value.Literal ( 3, floatType () ) (FloatLiteral 2))
        (Value.Literal ( 4, floatType () ) (FloatLiteral 3))
    , Value.IfThenElse ( 1, floatType () )
        (Value.Apply ( 2, boolType () )
            (Value.Variable ( 3, isZeroType ) [ "is", "zero" ])
            (Value.Literal ( 4, floatType () ) (FloatLiteral 1))
        )
        (Value.Literal ( 5, floatType () ) (FloatLiteral 2))
        (Value.Literal ( 6, floatType () ) (FloatLiteral 3))

    -- tuple
    , Value.Tuple ( 1, Type.Tuple () [ boolType (), floatType () ] )
        [ Value.Literal ( 2, boolType () ) (BoolLiteral False)
        , Value.Literal ( 3, floatType () ) (FloatLiteral 2)
        ]

    -- record
    , Value.Record ( 1, Type.Record () [ Type.Field [ "bar" ] (floatType ()), Type.Field [ "foo" ] (boolType ()) ] )
        [ ( [ "foo" ], Value.Literal ( 2, boolType () ) (BoolLiteral False) )
        , ( [ "bar" ], Value.Literal ( 3, floatType () ) (FloatLiteral 2) )
        ]
    , Value.Lambda ( 0, Type.Function () (barRecordType "t5_1") (floatType ()) )
        (Value.AsPattern ( 1, barRecordType "t5_1" ) (Value.WildcardPattern ( 2, barRecordType "t5_1" )) [ "rec" ])
        (Value.IfThenElse ( 3, floatType () )
            (Value.Literal ( 4, boolType () ) (BoolLiteral False))
            (Value.Field ( 5, floatType () )
                (Value.Variable ( 6, barRecordType "t5_1" ) [ "rec" ])
                [ "bar" ]
            )
            (Value.Literal ( 7, floatType () ) (FloatLiteral 2))
        )
    , Value.Lambda ( 0, Type.Function () (barRecordType "t6_1") (floatType ()) )
        (Value.AsPattern ( 1, barRecordType "t6_1" ) (Value.WildcardPattern ( 2, barRecordType "t6_1" )) [ "rec" ])
        (Value.IfThenElse ( 3, floatType () )
            (Value.Literal ( 4, boolType () ) (BoolLiteral False))
            (Value.Apply ( 5, floatType () )
                (Value.FieldFunction ( 6, Type.Function () (barRecordType "t6_1") (floatType ()) ) [ "bar" ])
                (Value.Variable ( 7, barRecordType "t6_1" ) [ "rec" ])
            )
            (Value.Literal ( 8, floatType () ) (FloatLiteral 2))
        )
    , Value.Lambda ( 0, Type.Function () (barRecordType "t3_1") (barRecordType "t3_1") )
        (Value.AsPattern ( 1, barRecordType "t3_1" ) (Value.WildcardPattern ( 2, barRecordType "t3_1" )) [ "rec" ])
        (Value.UpdateRecord ( 3, barRecordType "t3_1" )
            (Value.Variable ( 4, barRecordType "t3_1" ) [ "rec" ])
            [ ( [ "bar" ], Value.Literal ( 5, floatType () ) (FloatLiteral 2) )
            ]
        )

    -- constructor
    , Value.Constructor ( 0, Type.Reference () (fqn "Morphir.SDK" "Maybe" "Maybe") [ Type.Variable () [ "t", "0", "1" ] ] )
        (fqn "Morphir.SDK" "Maybe" "Nothing")
    , Value.Apply ( 0, Type.Reference () (fqn "Morphir.SDK" "Maybe" "Maybe") [ floatType () ] )
        (Value.Constructor ( 1, Type.Function () (floatType ()) (Type.Reference () (fqn "Morphir.SDK" "Maybe" "Maybe") [ floatType () ]) )
            (fqn "Morphir.SDK" "Maybe" "Just")
        )
        (Value.Literal ( 2, floatType () ) (FloatLiteral 2))
    , Value.Apply ( 0, Type.Reference () (fqn "Morphir.SDK" "Result" "Result") [ Type.Variable () [ "t", "1", "2" ], floatType () ] )
        (Value.Constructor ( 1, Type.Function () (floatType ()) (Type.Reference () (fqn "Morphir.SDK" "Result" "Result") [ Type.Variable () [ "t", "1", "2" ], floatType () ]) )
            (fqn "Morphir.SDK" "Result" "Ok")
        )
        (Value.Literal ( 2, floatType () ) (FloatLiteral 2))
    , Value.Apply ( 0, Type.Reference () (fqn "Morphir.SDK" "Result" "Result") [ stringType (), Type.Variable () [ "t", "1", "1" ] ] )
        (Value.Constructor ( 1, Type.Function () (stringType ()) (Type.Reference () (fqn "Morphir.SDK" "Result" "Result") [ stringType (), Type.Variable () [ "t", "1", "1" ] ]) )
            (fqn "Morphir.SDK" "Result" "Err")
        )
        (Value.Literal ( 2, stringType () ) (StringLiteral "err"))

    -- reference
    , Value.Apply ( 0, listType () (floatType ()) )
        (Value.Apply ( 1, Type.Function () (listType () (floatType ())) (listType () (floatType ())) )
            (Value.Reference ( 2, Type.Function () (Type.Function () (floatType ()) (floatType ())) (Type.Function () (listType () (floatType ())) (listType () (floatType ()))) )
                (fqn "Morphir.SDK" "List" "map")
            )
            (Value.Lambda ( 3, Type.Function () (floatType ()) (floatType ()) )
                (Value.AsPattern ( 4, floatType () ) (Value.WildcardPattern ( 2, floatType () )) [ "a" ])
                (Value.Variable ( 5, floatType () ) [ "a" ])
            )
        )
        (Value.List ( 6, listType () (floatType ()) )
            [ Value.Literal ( 7, floatType () ) (FloatLiteral 2)
            ]
        )
    , Value.Apply ( 0, listType () (floatType ()) )
        (Value.Apply ( 1, Type.Function () (listType () (floatType ())) (listType () (floatType ())) )
            (Value.Reference ( 2, Type.Function () (Type.Function () (floatType ()) (boolType ())) (Type.Function () (listType () (floatType ())) (listType () (floatType ()))) )
                (fqn "Morphir.SDK" "List" "filter")
            )
            (Value.Lambda ( 3, Type.Function () (floatType ()) (boolType ()) )
                (Value.AsPattern ( 4, floatType () ) (Value.WildcardPattern ( 2, floatType () )) [ "a" ])
                (Value.Literal ( 7, boolType () ) (BoolLiteral False))
            )
        )
        (Value.List ( 6, listType () (floatType ()) )
            [ Value.Literal ( 7, floatType () ) (FloatLiteral 2)
            ]
        )

    -- lambda and patterns
    , Value.Lambda ( 0, Type.Function () (Type.Unit ()) (floatType ()) )
        (Value.UnitPattern ( 1, Type.Unit () ))
        (Value.Literal ( 8, floatType () ) (FloatLiteral 3))
    , Value.Lambda ( 0, Type.Function () (Type.Tuple () [ boolType (), floatType () ]) (floatType ()) )
        (Value.TuplePattern ( 1, Type.Tuple () [ boolType (), floatType () ] )
            [ Value.LiteralPattern ( 2, boolType () ) (BoolLiteral False)
            , Value.LiteralPattern ( 3, floatType () ) (FloatLiteral 3)
            ]
        )
        (Value.Literal ( 8, floatType () ) (FloatLiteral 3))
    , Value.Lambda ( 0, Type.Function () (Type.Reference () (fqn "Morphir.SDK" "Maybe" "Maybe") [ Type.Variable () [ "t", "1", "1" ] ]) (floatType ()) )
        (Value.ConstructorPattern ( 0, Type.Reference () (fqn "Morphir.SDK" "Maybe" "Maybe") [ Type.Variable () [ "t", "1", "1" ] ] )
            (fqn "Morphir.SDK" "Maybe" "Nothing")
            []
        )
        (Value.Literal ( 8, floatType () ) (FloatLiteral 3))
    , Value.Lambda ( 0, Type.Function () (listType () (boolType ())) (floatType ()) )
        (Value.HeadTailPattern ( 1, listType () (boolType ()) )
            (Value.LiteralPattern ( 2, boolType () ) (BoolLiteral False))
            (Value.EmptyListPattern ( 3, listType () (boolType ()) ))
        )
        (Value.Literal ( 8, floatType () ) (FloatLiteral 3))
    , Value.Lambda ( 0, Type.Function () isZeroType (floatType ()) )
        (Value.AsPattern ( 1, isZeroType ) (Value.WildcardPattern ( 2, isZeroType )) [ "is", "zero" ])
        (Value.IfThenElse ( 3, floatType () )
            (Value.Apply ( 4, boolType () )
                (Value.Variable ( 5, isZeroType ) [ "is", "zero" ])
                (Value.Literal ( 6, floatType () ) (FloatLiteral 1))
            )
            (Value.Literal ( 7, floatType () ) (FloatLiteral 2))
            (Value.Literal ( 8, floatType () ) (FloatLiteral 3))
        )

    -- let
    , Value.LetDefinition ( 0, floatType () )
        [ "foo" ]
        (Value.Definition
            [ ( [ "a" ], ( 1, floatType () ), floatType () )
            ]
            (floatType ())
            (Value.Variable ( 2, floatType () ) [ "a" ])
        )
        (Value.Apply ( 3, floatType () )
            (Value.Variable ( 4, Type.Function () (floatType ()) (floatType ()) ) [ "foo" ])
            (Value.Literal ( 5, floatType () ) (FloatLiteral 3))
        )
    , Value.LetRecursion ( 0, floatType () )
        (Dict.fromList
            [ ( [ "foo" ]
              , Value.Definition
                    [ ( [ "a" ], ( 1, floatType () ), floatType () )
                    ]
                    (floatType ())
                    (Value.Variable ( 2, floatType () ) [ "a" ])
              )
            ]
        )
        (Value.Apply ( 3, floatType () )
            (Value.Variable ( 4, Type.Function () (floatType ()) (floatType ()) ) [ "foo" ])
            (Value.Literal ( 5, floatType () ) (FloatLiteral 3))
        )
    , Value.LetRecursion ( 0, floatType () )
        (Dict.fromList
            [ ( [ "foo" ]
              , Value.Definition
                    [ ( [ "a" ], ( 1, floatType () ), floatType () )
                    ]
                    (floatType ())
                    (Value.Apply ( 2, floatType () )
                        (Value.Variable ( 3, Type.Function () (floatType ()) (floatType ()) ) [ "foo" ])
                        (Value.Variable ( 4, floatType () ) [ "a" ])
                    )
              )
            ]
        )
        (Value.Apply ( 5, floatType () )
            (Value.Variable ( 6, Type.Function () (floatType ()) (floatType ()) ) [ "foo" ])
            (Value.Literal ( 7, floatType () ) (FloatLiteral 3))
        )
    , Value.LetRecursion ( 0, floatType () )
        (Dict.fromList
            [ ( [ "foo" ]
              , Value.Definition
                    [ ( [ "a" ], ( 1, floatType () ), floatType () )
                    ]
                    (floatType ())
                    (Value.Apply ( 2, floatType () )
                        (Value.Variable ( 3, Type.Function () (floatType ()) (floatType ()) ) [ "bar" ])
                        (Value.Variable ( 4, floatType () ) [ "a" ])
                    )
              )
            , ( [ "bar" ]
              , Value.Definition
                    [ ( [ "a" ], ( 5, floatType () ), floatType () )
                    ]
                    (floatType ())
                    (Value.Apply ( 6, floatType () )
                        (Value.Variable ( 7, Type.Function () (floatType ()) (floatType ()) ) [ "foo" ])
                        (Value.Variable ( 8, floatType () ) [ "a" ])
                    )
              )
            ]
        )
        (Value.Apply ( 9, floatType () )
            (Value.Variable ( 10, Type.Function () (floatType ()) (floatType ()) ) [ "foo" ])
            (Value.Literal ( 11, floatType () ) (FloatLiteral 3))
        )

    -- destructure
    , Value.Destructure ( 0, listType () (boolType ()) )
        (Value.HeadTailPattern ( 1, listType () (boolType ()) )
            (Value.LiteralPattern ( 2, boolType () ) (BoolLiteral False))
            (Value.AsPattern ( 3, listType () (boolType ()) ) (Value.WildcardPattern ( 4, listType () (boolType ()) )) [ "my", "list" ])
        )
        (Value.List ( 5, listType () (boolType ()) ) [])
        (Value.Variable ( 6, listType () (boolType ()) ) [ "my", "list" ])

    -- pattern-match
    , Value.PatternMatch ( 0, listType () (boolType ()) )
        (Value.List ( 5, listType () (boolType ()) ) [])
        [ ( Value.HeadTailPattern ( 1, listType () (boolType ()) )
                (Value.LiteralPattern ( 2, boolType () ) (BoolLiteral False))
                (Value.AsPattern ( 3, listType () (boolType ()) ) (Value.WildcardPattern ( 4, listType () (boolType ()) )) [ "my", "list" ])
          , Value.Variable ( 6, listType () (boolType ()) ) [ "my", "list" ]
          )
        , ( Value.EmptyListPattern ( 1, listType () (boolType ()) )
          , Value.List ( 6, listType () (boolType ()) ) []
          )
        ]

    -- number type class
    , Value.IfThenElse ( 1, floatType () )
        (Value.Literal ( 2, boolType () ) (BoolLiteral False))
        (Value.Literal ( 3, floatType () ) (IntLiteral 2))
        (Value.Literal ( 4, floatType () ) (FloatLiteral 3))
    , Value.List ( 1, listType () (floatType ()) )
        [ Value.Literal ( 2, floatType () ) (IntLiteral 2)
        , Value.Literal ( 3, floatType () ) (FloatLiteral 3)
        ]
    ]


negativeOutcomes : List ( Value () Int, TypeError )
negativeOutcomes =
    [ ( Value.IfThenElse 1
            (Value.Literal 2 (FloatLiteral 1))
            (Value.Literal 3 (IntLiteral 2))
            (Value.Literal 4 (IntLiteral 3))
      , TypeMismatch MetaType.boolType MetaType.floatType
      )
    , ( Value.List 1
            [ Value.Literal 2 (IntLiteral 2)
            , Value.Literal 3 (FloatLiteral 3)
            , Value.Literal 4 (BoolLiteral False)
            ]
      , TypeMismatch MetaType.floatType MetaType.boolType
      )
    ]


positiveDefOutcomes : List (Value.Definition () ( Int, Type () ))
positiveDefOutcomes =
    [ Value.Definition
        [ ( [ "a" ], ( 0, floatType () ), floatType () )
        ]
        (floatType ())
        (Value.Variable ( 1, floatType () ) [ "a" ])
    , Value.Definition
        [ ( [ "a" ], ( 0, floatType () ), floatType () )
        ]
        (floatType ())
        (Value.IfThenElse ( 1, floatType () )
            (Value.Literal ( 2, boolType () ) (BoolLiteral False))
            (Value.Variable ( 3, floatType () ) [ "a" ])
            (Value.Variable ( 4, floatType () ) [ "a" ])
        )
    ]


inferPositiveTests : Test
inferPositiveTests =
    describe "Inference should succeed"
        (positiveOutcomes
            |> List.indexedMap
                (\index expectedOutcome ->
                    let
                        untyped : Value () Int
                        untyped =
                            expectedOutcome
                                |> Value.mapValueAttributes identity Tuple.first
                    in
                    test ("Scenario " ++ String.fromInt index)
                        (\_ ->
                            Infer.inferValue testReferences untyped
                                |> Expect.equal (Ok expectedOutcome)
                        )
                )
        )


inferNegativeTests : Test
inferNegativeTests =
    describe "Inference should fail"
        (negativeOutcomes
            |> List.indexedMap
                (\index ( untyped, expectedError ) ->
                    test ("Scenario " ++ String.fromInt index)
                        (\_ ->
                            Infer.inferValue testReferences untyped
                                |> Expect.equal (Err expectedError)
                        )
                )
        )


inferDefPositiveTests : Test
inferDefPositiveTests =
    describe "Inference of definition should succeed"
        (positiveDefOutcomes
            |> List.indexedMap
                (\index expectedOutcome ->
                    let
                        untyped : Value.Definition () Int
                        untyped =
                            expectedOutcome
                                |> Value.mapDefinitionAttributes identity Tuple.first
                    in
                    test ("Scenario " ++ String.fromInt index)
                        (\_ ->
                            Infer.inferValueDefinition testReferences untyped
                                |> Expect.equal (Ok expectedOutcome)
                        )
                )
        )


addSolutionTests : Test
addSolutionTests =
    let
        scenarios : List ( List ( Variable, MetaType ), ( Variable, MetaType ), List ( Variable, MetaType ) )
        scenarios =
            [ ( []
              , ( variable 1, MetaVar (variable 1) )
              , [ ( variable 1, MetaVar (variable 1) )
                ]
              )
            , ( [ ( variable 1, MetaVar (variable 2) )
                ]
              , ( variable 1, MetaVar (variable 2) )
              , [ ( variable 1, MetaVar (variable 2) )
                ]
              )
            ]
    in
    describe "addSolution"
        (scenarios
            |> List.indexedMap
                (\index ( solutionMap, ( newVar, newSolution ), expectedSolutionMap ) ->
                    test ("Scenario " ++ String.fromInt index)
                        (\_ ->
                            solutionMap
                                |> SolutionMap.fromList
                                |> Infer.addSolution newVar newSolution
                                |> Expect.equal (Ok (SolutionMap.fromList expectedSolutionMap))
                        )
                )
        )


solvePositiveTests : Test
solvePositiveTests =
    let
        t i =
            variable i

        tvar i =
            MetaVar (t i)

        ref n =
            MetaRef (fQName [] [] [ n ])

        scenarios : List ( List Constraint, List Constraint, List ( Variable, MetaType ) )
        scenarios =
            [ ( []
              , []
              , []
              )
            , ( [ equality (tvar 1) (tvar 1)
                ]
              , []
              , []
              )
            , ( [ equality (tvar 1) (tvar 2)
                ]
              , []
              , [ ( t 1, tvar 2 )
                ]
              )
            , ( [ equality (tvar 1) (tvar 2)
                , equality (tvar 2) (tvar 1)
                ]
              , []
              , [ ( t 1, tvar 2 )
                ]
              )
            , ( [ equality (tvar 1) (MetaTuple [ tvar 5, tvar 4 ])
                , equality (tvar 5) (ref "int")
                , equality (tvar 4) (ref "bool")
                , equality (tvar 6) (ref "int")
                , equality (tvar 7) (ref "int")
                , equality (tvar 6) (tvar 3)
                , equality (tvar 7) (tvar 3)
                , equality (tvar 2) (MetaTuple [ tvar 1, tvar 3 ])
                ]
              , []
              , [ ( t 1, MetaTuple [ ref "int", ref "bool" ] )
                , ( t 5, ref "int" )
                , ( t 4, ref "bool" )
                , ( t 6, ref "int" )
                , ( t 7, ref "int" )
                , ( t 3, ref "int" )
                , ( t 2, MetaTuple [ MetaTuple [ ref "int", ref "bool" ], ref "int" ] )
                ]
              )
            , ( [ class (tvar 1) Class.Number
                ]
              , [ class (tvar 1) Class.Number
                ]
              , []
              )
            , ( [ class (tvar 1) Class.Number
                , equality (tvar 1) MetaType.intType
                ]
              , []
              , [ ( t 1, MetaType.intType )
                ]
              )
            ]
    in
    describe "Solving should succeed"
        (scenarios
            |> List.indexedMap
                (\index ( constraints, residualConstraints, expectedSolutionMap ) ->
                    test ("Scenario " ++ String.fromInt index)
                        (\_ ->
                            Infer.solve testReferences (ConstraintSet.fromList constraints)
                                |> Expect.equal (Ok ( ConstraintSet.fromList residualConstraints, SolutionMap.fromList expectedSolutionMap ))
                        )
                )
        )


solveNegativeTests : Test
solveNegativeTests =
    let
        t i =
            variable i

        tvar i =
            MetaVar (t i)

        scenarios : List ( List Constraint, TypeError )
        scenarios =
            [ ( [ class (tvar 1) Class.Number
                , equality (tvar 1) MetaType.boolType
                ]
              , ClassConstraintViolation MetaType.boolType Class.Number
              )
            ]
    in
    describe "Solving should fail"
        (scenarios
            |> List.indexedMap
                (\index ( constraints, expectedError ) ->
                    test ("Scenario " ++ String.fromInt index)
                        (\_ ->
                            Infer.solve testReferences (ConstraintSet.fromList constraints)
                                |> Expect.equal (Err expectedError)
                        )
                )
        )
