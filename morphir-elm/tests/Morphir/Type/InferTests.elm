module Morphir.Type.InferTests exposing (..)

import Dict exposing (Dict)
import Expect
import Morphir.IR.AccessControlled exposing (public)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName exposing (fQName, fqn)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name
import Morphir.IR.Package exposing (PackageName)
import Morphir.IR.Path as Path
import Morphir.IR.SDK as SDK
import Morphir.IR.SDK.Basics exposing (boolType, floatType, intType)
import Morphir.IR.SDK.List exposing (listType)
import Morphir.IR.SDK.String exposing (stringType)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Type.Class as Class
import Morphir.Type.Constraint exposing (Constraint, class, equality)
import Morphir.Type.ConstraintSet as ConstraintSet
import Morphir.Type.Count as Count
import Morphir.Type.Infer as Infer exposing (TypeError(..))
import Morphir.Type.InferTests.BooksAndRecordsTests as BooksAndRecordsTests
import Morphir.Type.InferTests.ConstructorTests as ConstructorTests
import Morphir.Type.InferTests.RecordFieldAccessTests as RecordFieldAccessTests
import Morphir.Type.MetaType as MetaType exposing (MetaType(..), Variable, metaRef, metaTuple, variableByIndex)
import Morphir.Type.Solve as Solve exposing (UnificationError(..), UnificationErrorType(..))
import Test exposing (Test, describe, test)


testReferences : Distribution
testReferences =
    Library [ [ "test" ] ]
        (Dict.fromList
            [ ( [ [ "morphir" ], [ "s", "d", "k" ] ]
              , SDK.packageSpec
              )
            , ( Path.fromString "BooksAndRecords"
              , BooksAndRecordsTests.packageSpec
              )
            , ( Path.fromString "RecordAccess"
              , RecordFieldAccessTests.packageSpec
              )
            ]
        )
        { modules =
            Dict.fromList
                [ ( [ [ "test" ] ]
                  , public <|
                        { types =
                            Dict.fromList
                                [ ( [ "custom" ]
                                  , public <|
                                        Documented ""
                                            (Type.CustomTypeDefinition []
                                                (public <|
                                                    Dict.fromList
                                                        [ ( [ "custom", "zero" ], [] )
                                                        ]
                                                )
                                            )
                                  )
                                , ( [ "foo", "bar", "baz", "record" ]
                                  , public <|
                                        Documented ""
                                            (Type.TypeAliasDefinition []
                                                (Type.Record ()
                                                    [ Type.Field [ "foo" ] (stringType ())
                                                    , Type.Field [ "bar" ] (boolType ())
                                                    , Type.Field [ "baz" ] (intType ())
                                                    ]
                                                )
                                            )
                                  )
                                ]
                        , values =
                            Dict.empty
                        , doc = Nothing
                        }
                  )
                ]
        }


positiveOutcomes : List (Value () (Type ()))
positiveOutcomes =
    let
        isZeroType : Type ()
        isZeroType =
            Type.Function () (floatType ()) (boolType ())

        extRecordType : String -> List ( String, Type () ) -> Type ()
        extRecordType extends fields =
            Type.ExtensibleRecord ()
                (Name.fromString extends)
                (fields
                    |> List.map
                        (\( fieldName, fieldType ) ->
                            Type.Field (Name.fromString fieldName) fieldType
                        )
                )

        fooRecordType : String -> Type ()
        fooRecordType extends =
            extRecordType extends [ ( "foo", boolType () ) ]

        barRecordType : String -> Type ()
        barRecordType extends =
            extRecordType extends [ ( "bar", floatType () ) ]

        fooBarRecordType : String -> Type ()
        fooBarRecordType extends =
            extRecordType extends [ ( "bar", floatType () ), ( "foo", boolType () ) ]

        fooBarBazRecordType : Type ()
        fooBarBazRecordType =
            Type.Record ()
                [ Type.Field [ "bar" ] (floatType ())
                , Type.Field [ "baz" ] (stringType ())
                , Type.Field [ "foo" ] (boolType ())
                ]
    in
    -- if then else
    [ Value.IfThenElse (floatType ())
        (Value.Literal (boolType ()) (BoolLiteral False))
        (Value.Literal (floatType ()) (FloatLiteral 2))
        (Value.Literal (floatType ()) (FloatLiteral 3))
    , Value.IfThenElse (floatType ())
        (Value.Apply (boolType ())
            (Value.Variable isZeroType [ "is", "zero" ])
            (Value.Literal (floatType ()) (FloatLiteral 1))
        )
        (Value.Literal (floatType ()) (FloatLiteral 2))
        (Value.Literal (floatType ()) (FloatLiteral 3))

    -- tuple
    , Value.Tuple (Type.Tuple () [ boolType (), floatType () ])
        [ Value.Literal (boolType ()) (BoolLiteral False)
        , Value.Literal (floatType ()) (FloatLiteral 2)
        ]

    -- record
    , Value.Record (Type.Record () [ Type.Field [ "bar" ] (floatType ()), Type.Field [ "foo" ] (boolType ()) ]) <|
        Dict.fromList
            [ ( [ "foo" ], Value.Literal (boolType ()) (BoolLiteral False) )
            , ( [ "bar" ], Value.Literal (floatType ()) (FloatLiteral 2) )
            ]
    , Value.Lambda (Type.Function () (barRecordType "t4") (floatType ()))
        (Value.AsPattern (barRecordType "t4") (Value.WildcardPattern (barRecordType "t4")) [ "rec" ])
        (Value.IfThenElse (floatType ())
            (Value.Literal (boolType ()) (BoolLiteral False))
            (Value.Field (floatType ())
                (Value.Variable (barRecordType "t4") [ "rec" ])
                [ "bar" ]
            )
            (Value.Literal (floatType ()) (FloatLiteral 2))
        )
    , Value.Lambda (Type.Function () (barRecordType "t4") (floatType ()))
        (Value.AsPattern (barRecordType "t4") (Value.WildcardPattern (barRecordType "t4")) [ "rec" ])
        (Value.IfThenElse (floatType ())
            (Value.Literal (boolType ()) (BoolLiteral False))
            (Value.Apply (floatType ())
                (Value.FieldFunction (Type.Function () (barRecordType "t4") (floatType ())) [ "bar" ])
                (Value.Variable (barRecordType "t4") [ "rec" ])
            )
            (Value.Literal (floatType ()) (FloatLiteral 2))
        )
    , Value.LetDefinition (floatType ())
        [ "rec" ]
        (Value.Definition []
            fooBarBazRecordType
            (Value.Record fooBarBazRecordType <|
                Dict.fromList
                    [ ( [ "foo" ], Value.Literal (boolType ()) (BoolLiteral False) )
                    , ( [ "bar" ], Value.Literal (floatType ()) (FloatLiteral 3.14) )
                    , ( [ "baz" ], Value.Literal (stringType ()) (StringLiteral "meh") )
                    ]
            )
        )
        (Value.IfThenElse (floatType ())
            (Value.Apply (boolType ())
                (Value.FieldFunction (Type.Function () fooBarBazRecordType (boolType ())) [ "foo" ])
                (Value.Variable fooBarBazRecordType [ "rec" ])
            )
            (Value.Apply (floatType ())
                (Value.FieldFunction (Type.Function () fooBarBazRecordType (floatType ())) [ "bar" ])
                (Value.Variable fooBarBazRecordType [ "rec" ])
            )
            (Value.Literal (floatType ()) (FloatLiteral 2))
        )
    , Value.Lambda (Type.Function () (barRecordType "t3") (barRecordType "t3"))
        (Value.AsPattern (barRecordType "t3") (Value.WildcardPattern (barRecordType "t3")) [ "rec" ])
        (Value.UpdateRecord (barRecordType "t3")
            (Value.Variable (barRecordType "t3") [ "rec" ])
         <|
            Dict.fromList
                [ ( [ "bar" ], Value.Literal (floatType ()) (FloatLiteral 2) )
                ]
        )

    -- reference
    , Value.Apply (listType () (floatType ()))
        (Value.Apply (Type.Function () (listType () (floatType ())) (listType () (floatType ())))
            (Value.Reference (Type.Function () (Type.Function () (floatType ()) (floatType ())) (Type.Function () (listType () (floatType ())) (listType () (floatType ()))))
                (fqn "Morphir.SDK" "List" "map")
            )
            (Value.Lambda (Type.Function () (floatType ()) (floatType ()))
                (Value.AsPattern (floatType ()) (Value.WildcardPattern (floatType ())) [ "a" ])
                (Value.Variable (floatType ()) [ "a" ])
            )
        )
        (Value.List (listType () (floatType ()))
            [ Value.Literal (floatType ()) (FloatLiteral 2)
            ]
        )
    , Value.Apply (listType () (floatType ()))
        (Value.Apply (Type.Function () (listType () (floatType ())) (listType () (floatType ())))
            (Value.Reference (Type.Function () (Type.Function () (floatType ()) (boolType ())) (Type.Function () (listType () (floatType ())) (listType () (floatType ()))))
                (fqn "Morphir.SDK" "List" "filter")
            )
            (Value.Lambda (Type.Function () (floatType ()) (boolType ()))
                (Value.AsPattern (floatType ()) (Value.WildcardPattern (floatType ())) [ "a" ])
                (Value.Literal (boolType ()) (BoolLiteral False))
            )
        )
        (Value.List (listType () (floatType ()))
            [ Value.Literal (floatType ()) (FloatLiteral 2)
            ]
        )

    -- lambda and patterns
    , Value.Lambda (Type.Function () (Type.Unit ()) (floatType ()))
        (Value.UnitPattern (Type.Unit ()))
        (Value.Literal (floatType ()) (FloatLiteral 3))
    , Value.Lambda (Type.Function () (Type.Tuple () [ boolType (), floatType () ]) (floatType ()))
        (Value.TuplePattern (Type.Tuple () [ boolType (), floatType () ])
            [ Value.LiteralPattern (boolType ()) (BoolLiteral False)
            , Value.LiteralPattern (floatType ()) (FloatLiteral 3)
            ]
        )
        (Value.Literal (floatType ()) (FloatLiteral 3))
    , Value.Lambda (Type.Function () (Type.Reference () (fqn "Morphir.SDK" "Maybe" "Maybe") [ Type.Variable () [ "t", "2" ] ]) (floatType ()))
        (Value.ConstructorPattern (Type.Reference () (fqn "Morphir.SDK" "Maybe" "Maybe") [ Type.Variable () [ "t", "2" ] ])
            (fqn "Morphir.SDK" "Maybe" "Nothing")
            []
        )
        (Value.Literal (floatType ()) (FloatLiteral 3))
    , Value.Lambda (Type.Function () (listType () (boolType ())) (floatType ()))
        (Value.HeadTailPattern (listType () (boolType ()))
            (Value.LiteralPattern (boolType ()) (BoolLiteral False))
            (Value.EmptyListPattern (listType () (boolType ())))
        )
        (Value.Literal (floatType ()) (FloatLiteral 3))
    , Value.Lambda (Type.Function () isZeroType (floatType ()))
        (Value.AsPattern isZeroType (Value.WildcardPattern isZeroType) [ "is", "zero" ])
        (Value.IfThenElse (floatType ())
            (Value.Apply (boolType ())
                (Value.Variable isZeroType [ "is", "zero" ])
                (Value.Literal (floatType ()) (FloatLiteral 1))
            )
            (Value.Literal (floatType ()) (FloatLiteral 2))
            (Value.Literal (floatType ()) (FloatLiteral 3))
        )

    -- let
    , Value.LetDefinition (floatType ())
        [ "foo" ]
        (Value.Definition
            [ ( [ "a" ], floatType (), floatType () )
            ]
            (floatType ())
            (Value.Variable (floatType ()) [ "a" ])
        )
        (Value.Apply (floatType ())
            (Value.Variable (Type.Function () (floatType ()) (floatType ())) [ "foo" ])
            (Value.Literal (floatType ()) (FloatLiteral 3))
        )
    , Value.LetRecursion (floatType ())
        (Dict.fromList
            [ ( [ "foo" ]
              , Value.Definition
                    [ ( [ "a" ], floatType (), floatType () )
                    ]
                    (floatType ())
                    (Value.Variable (floatType ()) [ "a" ])
              )
            ]
        )
        (Value.Apply (floatType ())
            (Value.Variable (Type.Function () (floatType ()) (floatType ())) [ "foo" ])
            (Value.Literal (floatType ()) (FloatLiteral 3))
        )
    , Value.LetRecursion (floatType ())
        (Dict.fromList
            [ ( [ "foo" ]
              , Value.Definition
                    [ ( [ "a" ], floatType (), floatType () )
                    ]
                    (floatType ())
                    (Value.Apply (floatType ())
                        (Value.Variable (Type.Function () (floatType ()) (floatType ())) [ "foo" ])
                        (Value.Variable (floatType ()) [ "a" ])
                    )
              )
            ]
        )
        (Value.Apply (floatType ())
            (Value.Variable (Type.Function () (floatType ()) (floatType ())) [ "foo" ])
            (Value.Literal (floatType ()) (FloatLiteral 3))
        )
    , Value.LetRecursion (floatType ())
        (Dict.fromList
            [ ( [ "foo" ]
              , Value.Definition
                    [ ( [ "a" ], floatType (), floatType () )
                    ]
                    (floatType ())
                    (Value.Apply (floatType ())
                        (Value.Variable (Type.Function () (floatType ()) (floatType ())) [ "bar" ])
                        (Value.Variable (floatType ()) [ "a" ])
                    )
              )
            , ( [ "bar" ]
              , Value.Definition
                    [ ( [ "a" ], floatType (), floatType () )
                    ]
                    (floatType ())
                    (Value.Apply (floatType ())
                        (Value.Variable (Type.Function () (floatType ()) (floatType ())) [ "foo" ])
                        (Value.Variable (floatType ()) [ "a" ])
                    )
              )
            ]
        )
        (Value.Apply (floatType ())
            (Value.Variable (Type.Function () (floatType ()) (floatType ())) [ "foo" ])
            (Value.Literal (floatType ()) (FloatLiteral 3))
        )

    -- destructure
    , Value.Destructure (listType () (boolType ()))
        (Value.HeadTailPattern (listType () (boolType ()))
            (Value.LiteralPattern (boolType ()) (BoolLiteral False))
            (Value.AsPattern (listType () (boolType ())) (Value.WildcardPattern (listType () (boolType ()))) [ "my", "list" ])
        )
        (Value.List (listType () (boolType ())) [])
        (Value.Variable (listType () (boolType ())) [ "my", "list" ])

    -- pattern-match
    , Value.PatternMatch (listType () (boolType ()))
        (Value.List (listType () (boolType ())) [])
        [ ( Value.HeadTailPattern (listType () (boolType ()))
                (Value.LiteralPattern (boolType ()) (BoolLiteral False))
                (Value.AsPattern (listType () (boolType ())) (Value.WildcardPattern (listType () (boolType ()))) [ "my", "list" ])
          , Value.Variable (listType () (boolType ())) [ "my", "list" ]
          )
        , ( Value.EmptyListPattern (listType () (boolType ()))
          , Value.List (listType () (boolType ())) []
          )
        ]

    -- number type class
    , Value.IfThenElse (floatType ())
        (Value.Literal (boolType ()) (BoolLiteral False))
        (Value.Literal (floatType ()) (FloatLiteral 2))
        (Value.Literal (floatType ()) (FloatLiteral 3))
    , Value.List (listType () (floatType ()))
        [ Value.Literal (floatType ()) (FloatLiteral 2)
        , Value.Literal (floatType ()) (FloatLiteral 3)
        ]
    ]


negativeOutcomes : List ( Value () Int, TypeError )
negativeOutcomes =
    [ ( Value.IfThenElse 1
            (Value.Literal 2 (FloatLiteral 1))
            (Value.Literal 3 (WholeNumberLiteral 2))
            (Value.Literal 4 (WholeNumberLiteral 3))
      , UnifyError (CouldNotUnify RefMismatch MetaType.boolType MetaType.floatType)
      )
    , ( Value.List 1
            [ Value.Literal 2 (WholeNumberLiteral 2)
            , Value.Literal 3 (FloatLiteral 3)
            , Value.Literal 4 (BoolLiteral False)
            ]
      , UnifyError (CouldNotUnify RefMismatch MetaType.floatType MetaType.boolType)
      )
    ]


positiveDefOutcomes : List (Value.Definition () ( Int, Type () ))
positiveDefOutcomes =
    let
        fooBarBazRecordType : Type ()
        fooBarBazRecordType =
            Type.Reference () (fqn "Test" "Test" "FooBarBazRecord") []
    in
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
    , Value.Definition
        [ ( [ "a" ], ( 0, fooBarBazRecordType ), fooBarBazRecordType )
        ]
        (stringType ())
        (Value.Field ( 1, stringType () )
            (Value.Variable ( 2, fooBarBazRecordType ) [ "a" ])
            [ "foo" ]
        )
    ]


inferPositiveTests : Test
inferPositiveTests =
    describe "Inference should succeed"
        (positiveOutcomes
            ++ ConstructorTests.positiveOutcomes
            ++ BooksAndRecordsTests.positiveOutcomes
            |> List.indexedMap
                (\index expected ->
                    let
                        untyped : Value () ()
                        untyped =
                            expected
                                |> Value.mapValueAttributes identity (always ())
                    in
                    test ("Scenario " ++ String.fromInt index)
                        (\_ ->
                            case
                                Infer.inferValue testReferences untyped
                                    |> Result.map (Value.mapValueAttributes identity Tuple.second)
                            of
                                Ok actual ->
                                    if expected == actual then
                                        Expect.pass

                                    else
                                        let
                                            ( count, ( annotatedValue, constraints ) ) =
                                                Infer.constrainValue testReferences Dict.empty Nothing untyped
                                                    |> Count.apply 0

                                            message =
                                                String.join "\n"
                                                    [ String.join " = " [ "annotatedValue", Debug.toString annotatedValue ]
                                                    , String.join " = " [ "constraints", Debug.toString constraints ]
                                                    , String.join " = " [ "expected", Debug.toString expected ]
                                                    , String.join " = " [ "actual", Debug.toString actual ]
                                                    ]
                                        in
                                        Expect.fail message

                                Err error ->
                                    Expect.fail (Debug.toString error)
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
            ++ RecordFieldAccessTests.positiveDefOutcomes
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
              , ( variableByIndex 1, MetaVar (variableByIndex 1) )
              , [ ( variableByIndex 1, MetaVar (variableByIndex 1) )
                ]
              )
            , ( [ ( variableByIndex 1, MetaVar (variableByIndex 2) )
                ]
              , ( variableByIndex 1, MetaVar (variableByIndex 2) )
              , [ ( variableByIndex 1, MetaVar (variableByIndex 2) )
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
                                |> Solve.fromList
                                |> Solve.addSolution testReferences newVar newSolution
                                |> Expect.equal (Ok (Solve.fromList expectedSolutionMap))
                        )
                )
        )


solvePositiveTests : Test
solvePositiveTests =
    let
        t i =
            variableByIndex i

        tvar i =
            MetaVar (t i)

        ref n =
            metaRef (fQName [] [] [ n ]) []

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
              , [ ( t 2, tvar 1 )
                ]
              )
            , ( [ equality (tvar 1) (tvar 2)
                , equality (tvar 2) (tvar 1)
                ]
              , []
              , [ ( t 2, tvar 1 )
                ]
              )
            , ( [ equality (tvar 1) (metaTuple [ tvar 5, tvar 4 ])
                , equality (tvar 5) (ref "int")
                , equality (tvar 4) (ref "bool")
                , equality (tvar 6) (ref "int")
                , equality (tvar 7) (ref "int")
                , equality (tvar 6) (tvar 3)
                , equality (tvar 7) (tvar 3)
                , equality (tvar 2) (metaTuple [ tvar 1, tvar 3 ])
                ]
              , []
              , [ ( t 1, metaTuple [ ref "int", ref "bool" ] )
                , ( t 5, ref "int" )
                , ( t 4, ref "bool" )
                , ( t 6, ref "int" )
                , ( t 7, ref "int" )
                , ( t 3, ref "int" )
                , ( t 2, metaTuple [ metaTuple [ ref "int", ref "bool" ], ref "int" ] )
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
              , [ class MetaType.intType Class.Number
                ]
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
                                |> Expect.equal (Ok ( ConstraintSet.fromList residualConstraints, Solve.fromList expectedSolutionMap ))
                        )
                )
        )


solveNegativeTests : Test
solveNegativeTests =
    let
        t i =
            variableByIndex i

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
