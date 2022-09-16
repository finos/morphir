module Morphir.Type.InferTests.Issue889 exposing (..)

import Dict
import Expect
import Morphir.IR as IR exposing (IR)
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.SDK.Basics exposing (boolType, floatType)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value
import Morphir.Type.Constraint exposing (Constraint(..))
import Morphir.Type.ConstraintSet as ConstraintSet exposing (ConstraintSet(..))
import Morphir.Type.Infer as Infer
import Morphir.Type.InferTests.Common exposing (checkValueDefinitionTypes)
import Morphir.Type.MetaType as MetaType exposing (MetaType(..))
import Morphir.Type.Solve exposing (SolutionMap(..))
import Set
import Test exposing (Test, test)


barRecordType : Type ()
barRecordType =
    Type.Record ()
        [ Type.Field [ "bar" ] (floatType ())
        ]


testIR : IR
testIR =
    Dict.fromList
        [ ( [ [ "test" ] ]
          , { modules =
                Dict.fromList
                    [ ( [ [ "test" ] ]
                      , { types =
                            Dict.fromList
                                [ ( [ "bar", "record" ]
                                  , Documented ""
                                        (Type.TypeAliasSpecification [] barRecordType)
                                  )
                                ]
                        , values =
                            Dict.empty
                        }
                      )
                    ]
            }
          )
        ]
        |> IR.fromPackageSpecifications


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
    let
        ( annotated, _ ) =
            Infer.annotateDefinition 1 testDefinition
    in
    test "constraints"
        (\_ ->
            Infer.constrainDefinition (MetaType.variableByIndex 0) testIR Dict.empty annotated
                |> Expect.equal
                    (ConstraintSet
                        [ Equality (Set.fromList [ ( [], 0, 1 ), ( [], 1, 0 ) ]) (MetaVar ( [], 1, 0 )) (MetaRef (Set.fromList [ ( [], 0, 1 ) ]) ( [ [ "test" ] ], [ [ "test" ] ], [ "bar", "record" ] ) [] (Just (MetaRecord (Set.fromList [ ( [], 0, 1 ) ]) ( [], 0, 1 ) False (Dict.fromList [ ( [ "bar" ], MetaRef (Set.fromList []) ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] Nothing ) ]))))
                        , Equality (Set.fromList [ ( [], 3, 0 ), ( [], 3, 1 ), ( [], 4, 0 ) ]) (MetaVar ( [], 3, 0 )) (MetaRecord (Set.fromList [ ( [], 3, 1 ), ( [], 4, 0 ) ]) ( [], 3, 1 ) False (Dict.fromList [ ( [ "bar" ], MetaVar ( [], 4, 0 ) ) ]))
                        , Equality (Set.fromList [ ( [], 4, 0 ) ]) (MetaVar ( [], 4, 0 )) (MetaRef (Set.fromList []) ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] Nothing)
                        , Equality (Set.fromList [ ( [], 2, 0 ) ]) (MetaVar ( [], 2, 0 )) (MetaRef (Set.fromList []) ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "bool" ] ) [] Nothing)
                        , Equality (Set.fromList [ ( [], 1, 1 ), ( [], 2, 0 ) ]) (MetaVar ( [], 1, 1 )) (MetaVar ( [], 2, 0 ))
                        , Equality (Set.fromList [ ( [], 1, 0 ), ( [], 3, 0 ) ]) (MetaVar ( [], 1, 0 )) (MetaVar ( [], 3, 0 ))
                        ]
                    )
        )


solveTest : Test
solveTest =
    test "solve"
        (\_ ->
            Infer.solve testIR
                (ConstraintSet
                    [ Equality (Set.fromList [ ( [], 0, 1 ), ( [], 1, 0 ) ]) (MetaVar ( [], 1, 0 )) (MetaRef (Set.fromList [ ( [], 0, 1 ) ]) ( [ [ "test" ] ], [ [ "test" ] ], [ "bar", "record" ] ) [] (Just (MetaRecord (Set.fromList [ ( [], 0, 1 ) ]) ( [], 0, 1 ) False (Dict.fromList [ ( [ "bar" ], MetaRef (Set.fromList []) ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] Nothing ) ]))))
                    , Equality (Set.fromList [ ( [], 3, 0 ), ( [], 3, 1 ), ( [], 4, 0 ) ]) (MetaVar ( [], 3, 0 )) (MetaRecord (Set.fromList [ ( [], 3, 1 ), ( [], 4, 0 ) ]) ( [], 3, 1 ) False (Dict.fromList [ ( [ "bar" ], MetaVar ( [], 4, 0 ) ) ]))
                    , Equality (Set.fromList [ ( [], 4, 0 ) ]) (MetaVar ( [], 4, 0 )) (MetaRef (Set.fromList []) ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] Nothing)
                    , Equality (Set.fromList [ ( [], 2, 0 ) ]) (MetaVar ( [], 2, 0 )) (MetaRef (Set.fromList []) ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "bool" ] ) [] Nothing)
                    , Equality (Set.fromList [ ( [], 1, 1 ), ( [], 2, 0 ) ]) (MetaVar ( [], 1, 1 )) (MetaVar ( [], 2, 0 ))
                    , Equality (Set.fromList [ ( [], 1, 0 ), ( [], 3, 0 ) ]) (MetaVar ( [], 1, 0 )) (MetaVar ( [], 3, 0 ))
                    ]
                )
                |> Expect.equal
                    (Ok
                        ( ConstraintSet []
                        , SolutionMap
                            (Dict.fromList
                                [ ( ( [], 1, 0 ), MetaRef (Set.fromList [ ( [], 0, 1 ) ]) ( [ [ "test" ] ], [ [ "test" ] ], [ "bar", "record" ] ) [] (Just (MetaRecord (Set.fromList [ ( [], 0, 1 ) ]) ( [], 0, 1 ) False (Dict.fromList [ ( [ "bar" ], MetaRef (Set.fromList []) ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] Nothing ) ]))) )
                                , ( ( [], 1, 1 ), MetaRef (Set.fromList []) ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "bool" ] ) [] Nothing )
                                , ( ( [], 2, 0 ), MetaRef (Set.fromList []) ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "bool" ] ) [] Nothing )
                                , ( ( [], 3, 0 ), MetaRef (Set.fromList [ ( [], 0, 1 ) ]) ( [ [ "test" ] ], [ [ "test" ] ], [ "bar", "record" ] ) [] (Just (MetaRecord (Set.fromList [ ( [], 0, 1 ) ]) ( [], 0, 1 ) False (Dict.fromList [ ( [ "bar" ], MetaRef (Set.fromList []) ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] Nothing ) ]))) )
                                , ( ( [], 3, 1 ), MetaRef (Set.fromList [ ( [], 0, 1 ) ]) ( [ [ "test" ] ], [ [ "test" ] ], [ "bar", "record" ] ) [] (Just (MetaRecord (Set.fromList [ ( [], 0, 1 ) ]) ( [], 0, 1 ) False (Dict.fromList [ ( [ "bar" ], MetaRef (Set.fromList []) ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] Nothing ) ]))) )
                                , ( ( [], 4, 0 ), MetaRef (Set.fromList []) ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] Nothing )
                                ]
                            )
                        )
                    )
        )


inferTest : Test
inferTest =
    test "Infer record type alias"
        (\_ -> checkValueDefinitionTypes testIR testDefinition)
