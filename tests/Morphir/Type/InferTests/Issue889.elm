module Morphir.Type.InferTests.Issue889 exposing (..)

import Dict
import Expect
import Morphir.IR.AccessControlled exposing (public)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.SDK.Basics exposing (boolType, floatType)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value
import Morphir.Type.Constraint exposing (Constraint(..))
import Morphir.Type.ConstraintSet exposing (ConstraintSet(..))
import Morphir.Type.Count as Count
import Morphir.Type.Infer as Infer
import Morphir.Type.InferTests.Common exposing (checkValueDefinitionTypes)
import Morphir.Type.MetaType exposing (MetaType(..))
import Morphir.Type.Solve exposing (SolutionMap(..))
import Set
import Test exposing (Test, test)


barRecordType : Type ()
barRecordType =
    Type.Record ()
        [ Type.Field [ "bar" ] (floatType ())
        ]


testIR : Distribution
testIR =
    Library [ [ "test" ] ]
        Dict.empty
        { modules =
            Dict.fromList
                [ ( [ [ "test" ] ]
                  , public <|
                        { types =
                            Dict.fromList
                                [ ( [ "bar", "record" ]
                                  , public <|
                                        Documented ""
                                            (Type.TypeAliasDefinition [] barRecordType)
                                  )
                                ]
                        , values =
                            Dict.empty
                        , doc = Nothing
                        }
                  )
                ]
        }


testDefinition : Value.Definition () (Type ())
testDefinition =
    let
        barRecordRef : Type ()
        barRecordRef =
            Type.Reference () ( [ [ "test" ] ], [ [ "test" ] ], [ "bar", "record" ] ) []

        dummyDef : Value.Definition () (Type ())
        dummyDef =
            { inputTypes = []
            , outputType = boolType ()
            , body = Value.Literal (boolType ()) (BoolLiteral True)
            }
    in
    { inputTypes = []
    , outputType = barRecordRef
    , body =
        Value.LetDefinition barRecordRef
            [ "dummy" ]
            dummyDef
            (Value.Record barRecordRef
                (Dict.fromList
                    [ ( [ "bar" ], Value.Literal (floatType ()) (FloatLiteral 3.14) )
                    ]
                )
            )
    }


constraintTest : Test
constraintTest =
    test "constraints"
        (\_ ->
            Infer.constrainDefinition testIR Dict.empty testDefinition
                |> Count.apply 0
                |> (\( _, ( _, _, ( cs, _ ) ) ) -> cs)
                |> Expect.equal
                    (ConstraintSet
                        [ Equality (Set.fromList [ 0, 6 ]) (MetaVar 6) (MetaRef (Set.fromList [ 0 ]) ( [ [ "test" ] ], [ [ "test" ] ], [ "bar", "record" ] ) [] (Just (MetaRecord (Set.fromList [ 0 ]) 0 False (Dict.fromList [ ( [ "bar" ], MetaRef (Set.fromList []) ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] Nothing ) ]))))
                        , Equality (Set.fromList [ 4, 6 ]) (MetaVar 6) (MetaVar 4)
                        , Equality (Set.fromList [ 1, 2 ]) (MetaVar 2) (MetaVar 1)
                        , Equality (Set.fromList [ 1 ]) (MetaVar 1) (MetaRef (Set.fromList []) ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "bool" ] ) [] Nothing)
                        , Equality (Set.fromList [ 3 ]) (MetaVar 3) (MetaRef (Set.fromList []) ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] Nothing)
                        , Equality (Set.fromList [ 3, 4, 5 ]) (MetaVar 4) (MetaRecord (Set.fromList [ 3, 5 ]) 5 False (Dict.fromList [ ( [ "bar" ], MetaVar 3 ) ]))
                        , Equality (Set.fromList [ 6, 7 ]) (MetaVar 7) (MetaVar 6)
                        ]
                    )
        )


solveTest : Test
solveTest =
    test "solve"
        (\_ ->
            Infer.solve testIR
                (ConstraintSet
                    [ Equality (Set.fromList [ 0, 6 ]) (MetaVar 6) (MetaRef (Set.fromList [ 0 ]) ( [ [ "test" ] ], [ [ "test" ] ], [ "bar", "record" ] ) [] (Just (MetaRecord (Set.fromList [ 0 ]) 0 False (Dict.fromList [ ( [ "bar" ], MetaRef (Set.fromList []) ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] Nothing ) ]))))
                    , Equality (Set.fromList [ 4, 6 ]) (MetaVar 6) (MetaVar 4)
                    , Equality (Set.fromList [ 1, 2 ]) (MetaVar 2) (MetaVar 1)
                    , Equality (Set.fromList [ 1 ]) (MetaVar 1) (MetaRef (Set.fromList []) ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "bool" ] ) [] Nothing)
                    , Equality (Set.fromList [ 3 ]) (MetaVar 3) (MetaRef (Set.fromList []) ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] Nothing)
                    , Equality (Set.fromList [ 3, 4, 5 ]) (MetaVar 4) (MetaRecord (Set.fromList [ 3, 5 ]) 5 False (Dict.fromList [ ( [ "bar" ], MetaVar 3 ) ]))
                    , Equality (Set.fromList [ 6, 7 ]) (MetaVar 7) (MetaVar 6)
                    ]
                )
                |> Expect.equal
                    (Ok
                        ( ConstraintSet []
                        , SolutionMap
                            (Dict.fromList
                                [ ( 1, MetaRef (Set.fromList []) ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "bool" ] ) [] Nothing )
                                , ( 2, MetaRef (Set.fromList []) ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "bool" ] ) [] Nothing )
                                , ( 3, MetaRef (Set.fromList []) ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] Nothing )
                                , ( 4, MetaRef (Set.fromList [ 0 ]) ( [ [ "test" ] ], [ [ "test" ] ], [ "bar", "record" ] ) [] (Just (MetaRecord (Set.fromList [ 0 ]) 0 False (Dict.fromList [ ( [ "bar" ], MetaRef (Set.fromList []) ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] Nothing ) ]))) )
                                , ( 5, MetaRef (Set.fromList [ 0 ]) ( [ [ "test" ] ], [ [ "test" ] ], [ "bar", "record" ] ) [] (Just (MetaRecord (Set.fromList [ 0 ]) 0 False (Dict.fromList [ ( [ "bar" ], MetaRef (Set.fromList []) ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] Nothing ) ]))) )
                                , ( 6, MetaRef (Set.fromList [ 0 ]) ( [ [ "test" ] ], [ [ "test" ] ], [ "bar", "record" ] ) [] (Just (MetaRecord (Set.fromList [ 0 ]) 0 False (Dict.fromList [ ( [ "bar" ], MetaRef (Set.fromList []) ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] Nothing ) ]))) )
                                , ( 7, MetaRef (Set.fromList [ 0 ]) ( [ [ "test" ] ], [ [ "test" ] ], [ "bar", "record" ] ) [] (Just (MetaRecord (Set.fromList [ 0 ]) 0 False (Dict.fromList [ ( [ "bar" ], MetaRef (Set.fromList []) ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] Nothing ) ]))) )
                                ]
                            )
                        )
                    )
        )


inferTest : Test
inferTest =
    test "Infer record type alias"
        (\_ -> checkValueDefinitionTypes testIR testDefinition)
