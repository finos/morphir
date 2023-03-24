module Morphir.IR.NodeIDTests exposing (..)

import Dict
import Expect
import Morphir.IR.FQName exposing (fqn)
import Morphir.IR.Literal as Literal exposing (Literal(..))
import Morphir.IR.NodeId as NodeID exposing (Error(..))
import Morphir.IR.Type as Type exposing (Type(..))
import Morphir.IR.Value as Value exposing (Pattern(..), Value(..))
import Test exposing (Test, describe, only, test)


getTypeAttributeByPathTest : Test
getTypeAttributeByPathTest =
    let
        expectation : attr -> NodeID.NodePath -> Type attr -> a -> Expect.Expectation
        expectation expectedAttr nodePath value =
            \_ -> Expect.equal (Ok expectedAttr) (NodeID.getTypeAttributeByPath nodePath value)
    in
    describe "TypeNodePath"
        [ test "variable" <|
            expectation 0
                []
                (Type.Variable 0 [ "var" ])
        , test "tuple" <|
            expectation 2
                [ NodeID.ChildByIndex 1 ]
                (Type.Tuple 0 [ Type.Variable 1 [ "var1" ], Type.Variable 2 [ "var2" ] ])
        , test "record" <|
            expectation 3
                [ NodeID.ChildByName [ "f1" ], NodeID.ChildByIndex 1 ]
                (Type.Record 0
                    [ { name = [ "f1" ]
                      , tpe = Type.Tuple 1 [ Type.Variable 2 [ "var1" ], Type.Variable 3 [ "var2" ] ]
                      }
                    , { name = [ "f2" ]
                      , tpe = Type.Variable 4 [ "var" ]
                      }
                    ]
                )
        , test "unit" <|
            expectation 99
                []
                (Type.Unit 99)
        , test "function" <|
            expectation 4
                [ NodeID.ChildByIndex 1 ]
                (Type.Function 0 (Type.Tuple 1 [ Type.Variable 2 [ "var1" ], Type.Variable 3 [ "var2" ] ]) (Type.Tuple 4 [ Type.Variable 5 [ "var1" ], Type.Variable 6 [ "var2" ] ]))
        , test "reference" <|
            expectation 99
                [ NodeID.ChildByIndex 1 ]
                (Type.Reference 0
                    (fqn "" "" "")
                    [ Type.Unit 9
                    , Type.Unit 99
                    ]
                )
        , test "extensible record" <|
            expectation 9
                [ NodeID.ChildByName [ "f1" ], NodeID.ChildByIndex 1, NodeID.ChildByIndex 0 ]
                (Type.ExtensibleRecord 0
                    []
                    [ { name = [ "f1" ]
                      , tpe = Type.Tuple 1 [ Type.Variable 2 [ "var1" ], Type.Reference 0 (fqn "" "" "") [ Type.Unit 9, Type.Unit 99 ] ]
                      }
                    , { name = [ "f2" ]
                      , tpe = Type.Variable 4 [ "var" ]
                      }
                    ]
                )
        , test "error" <|
            \_ ->
                Expect.equal (Err <| InvalidPath "Path is invalid after #f1")
                    (NodeID.getTypeAttributeByPath [ NodeID.ChildByName [ "f1" ], NodeID.ChildByIndex 3 ]
                        (Type.Record 0
                            [ { name = [ "f1" ]
                              , tpe = Type.Tuple 1 [ Type.Variable 2 [ "var1" ], Type.Variable 3 [ "var2" ] ]
                              }
                            , { name = [ "f2" ]
                              , tpe = Type.Variable 4 [ "var" ]
                              }
                            ]
                        )
                    )
        ]


getValueAttributeByPathTest : Test
getValueAttributeByPathTest =
    let
        expectation expectedAttr nodePath value =
            \_ -> Expect.equal (Ok expectedAttr) (NodeID.getValueAttributeByPath nodePath value)
    in
    describe "ValueNodePath"
        [ test "Unit" <|
            expectation 99
                []
                (Value.Unit 99)
        , test "Literal" <|
            expectation 98
                []
                (Value.Literal 98 (BoolLiteral True))
        , test "Constructor" <|
            expectation 97
                []
                (Value.Constructor 97 (fqn "" "" ""))
        , test "Constructor err" <|
            \_ -> Expect.equal (Err <| InvalidPath "Path is invalid") (NodeID.getValueAttributeByPath [ NodeID.ChildByIndex 0 ] (Value.Constructor 97 (fqn "" "" "")))
        , test "Tuple" <|
            expectation 95
                [ NodeID.ChildByIndex 0 ]
                (Value.Tuple 96 [ Value.Literal 95 (BoolLiteral True), Value.Literal 94 (BoolLiteral False) ])
        , test "List" <|
            expectation 90
                [ NodeID.ChildByIndex 2 ]
                (Value.Tuple 93 [ Value.Literal 92 (BoolLiteral True), Value.Literal 91 (BoolLiteral False), Value.Literal 90 (BoolLiteral False) ])
        , test "Record (inside tuple)" <|
            expectation 85
                [ NodeID.ChildByIndex 1, NodeID.ChildByName [ "field2" ] ]
                (Value.Tuple 89 [ Value.Literal 88 (BoolLiteral True), Value.Record 87 (Dict.fromList [ ( [ "field" ], Value.Unit 86 ), ( [ "field2" ], Value.Unit 85 ) ]) ])
        , test "Variable" <|
            expectation 84
                []
                (Value.Variable 84 [ "varName" ])
        , test "Reference" <|
            expectation 83
                []
                (Value.Reference 83 (fqn "f" "q" "n"))
        , test "Field" <|
            expectation 82
                []
                (Value.Field 82 (Value.Unit 81) [ "field" ])
        , test "inside of Field" <|
            expectation 79
                [ NodeID.ChildByIndex 0 ]
                (Value.Field 80 (Value.Unit 79) [ "field" ])
        , test "FieldFunction" <|
            expectation 78
                []
                (Value.FieldFunction 78 [ "fieldfunction" ])
        , test "Apply" <|
            expectation 75
                [ NodeID.ChildByIndex 1 ]
                (Value.Apply 77 (Value.Literal 76 (BoolLiteral True)) (Value.Literal 75 (BoolLiteral True)))
        , test "Lambda" <|
            expectation 73
                [ NodeID.ChildByIndex 0 ]
                (Value.Lambda 74 (Value.WildcardPattern 73) (Value.Literal 72 (BoolLiteral True)))
        , test "IfThenElse" <|
            expectation 69
                [ NodeID.ChildByIndex 1 ]
                (Value.IfThenElse 71 (Value.Variable 70 [ "if" ]) (Value.Variable 69 [ "then" ]) (Value.Variable 68 [ "else" ]))
        , test "Destructure pattern" <|
            expectation 48
                [ NodeID.ChildByIndex 0 ]
                (Value.Destructure 49 (Value.EmptyListPattern 48) (Value.Literal 47 (BoolLiteral True)) (Value.Unit 46))
        , test "Destructure value 2" <|
            expectation 42
                [ NodeID.ChildByIndex 2 ]
                (Value.Destructure 45 (Value.EmptyListPattern 44) (Value.Literal 43 (BoolLiteral True)) (Value.Unit 42))
        , test "LetDefinition outputType" <|
            expectation 40
                [ NodeID.ChildByIndex 0, NodeID.ChildByIndex 1 ]
                (Value.LetDefinition 41
                    [ "letDefinition" ]
                    { inputTypes = []
                    , outputType = Type.Variable 40 [ "var" ]
                    , body = Value.Unit 39
                    }
                    (Value.Unit 38)
                )
        , test "LetDefinition body" <|
            expectation 34
                [ NodeID.ChildByIndex 0, NodeID.ChildByName [ "body" ], NodeID.ChildByIndex 0 ]
                (Value.LetDefinition 37
                    [ "letDefinition" ]
                    { inputTypes = []
                    , outputType = Type.Variable 36 [ "var" ]
                    , body = Value.Tuple 35 [ Value.Literal 34 (BoolLiteral True), Value.Literal 33 (BoolLiteral False) ]
                    }
                    (Value.Unit 32)
                )
        , test "LetDefinition inputTypes" <|
            expectation 29
                [ NodeID.ChildByIndex 0, NodeID.ChildByName [ "inputTypes" ], NodeID.ChildByIndex 0, NodeID.ChildByIndex 1 ]
                (Value.LetDefinition 31
                    [ "letDefinition" ]
                    { inputTypes = [ ( [ "name" ], 30, Type.Unit 29 ) ]
                    , outputType = Type.Variable 28 [ "var" ]
                    , body = Value.Unit 27
                    }
                    (Value.Unit 26)
                )
        ]


mapPatternAttributeTest : Test
mapPatternAttributeTest =
    let
        expectation : Pattern attr -> Pattern NodeID.NodePath -> b -> Expect.Expectation
        expectation original mapped =
            \_ -> Expect.equal mapped (NodeID.mapPatternAttributesWithNodePath always original)
    in
        describe "mapPatternAttributesWithNodePath"
            [ test "UnitPattern" <|
                expectation (Value.UnitPattern ())
                    (Value.UnitPattern [])
            , test "WildcardPattern" <|
                expectation (Value.WildcardPattern ())
                    (Value.WildcardPattern [])
            , test "AsPattern" <|
                expectation (Value.AsPattern () (Value.WildcardPattern ()) [ "name" ])
                    (Value.AsPattern [] (Value.WildcardPattern [ NodeID.ChildByIndex 0 ]) [ "name" ])
            , test "TuplePattern" <|
                expectation (Value.TuplePattern () [ Value.WildcardPattern (), Value.WildcardPattern () ])
                    (Value.TuplePattern [] [ Value.WildcardPattern [ NodeID.ChildByIndex 0 ], Value.WildcardPattern [ NodeID.ChildByIndex 1 ] ])
            , test "ConstructorPattern" <|
                expectation (Value.ConstructorPattern () ( [ [ "f" ] ], [ [ "q" ] ], [ "n" ] ) [ Value.WildcardPattern (), Value.WildcardPattern () ])
                    (Value.ConstructorPattern [] ( [ [ "f" ] ], [ [ "q" ] ], [ "n" ] ) [ Value.WildcardPattern [ NodeID.ChildByIndex 0 ], Value.WildcardPattern [ NodeID.ChildByIndex 1 ] ])
            , test "EmptyListPattern" <|
                expectation (Value.EmptyListPattern ())
                    (Value.EmptyListPattern [])
            , test "HeadTailPattern" <|
                expectation (Value.HeadTailPattern () (Value.EmptyListPattern ()) (Value.EmptyListPattern ()))
                    (Value.HeadTailPattern [] (Value.EmptyListPattern [ NodeID.ChildByIndex 0 ]) (Value.EmptyListPattern [ NodeID.ChildByIndex 1 ]))
            , test "LiteralPattern" <|
                expectation (Value.LiteralPattern () (BoolLiteral True))
                    (Value.LiteralPattern [] (BoolLiteral True))
            , test "deeper" <|
                expectation (Value.TuplePattern () [ Value.AsPattern () (Value.WildcardPattern ()) [ "name" ], Value.AsPattern () (Value.WildcardPattern ()) [ "name2" ] ])
                    (Value.TuplePattern [] [ Value.AsPattern [ NodeID.ChildByIndex 0 ] (Value.WildcardPattern [ NodeID.ChildByIndex 0, NodeID.ChildByIndex 0 ]) [ "name" ], Value.AsPattern [ NodeID.ChildByIndex 1 ] (Value.WildcardPattern [ NodeID.ChildByIndex 1, NodeID.ChildByIndex 0 ]) [ "name2" ] ])
            ]


mapTypeAttributeTest : Test
mapTypeAttributeTest =
    let
        expectation : Type attr -> Type NodeID.NodePath -> b -> Expect.Expectation
        expectation original mapped =
            \_ -> Expect.equal mapped (NodeID.mapTypeAttributeWithNodePath always original)
    in
        describe "mapTypeAttributeWithNodePath"
            [ test "Variable" <|
                expectation (Type.Variable () [ "name" ])
                    (Type.Variable [] [ "name" ])
            , test "Reference" <|
                expectation (Type.Reference () ( [ [ "f" ] ], [ [ "q" ] ], [ "n" ] ) [ Type.Variable () [ "a" ], Type.Variable () [ "b" ] ])
                    (Type.Reference [] ( [ [ "f" ] ], [ [ "q" ] ], [ "n" ] ) [ Type.Variable [ NodeID.ChildByIndex 0 ] [ "a" ], Type.Variable [ NodeID.ChildByIndex 1 ] [ "b" ] ])
            , test "Tuple" <|
                expectation (Type.Tuple () [ Type.Variable () [ "a" ], Type.Variable () [ "b" ] ])
                    (Type.Tuple [] [ Type.Variable [ NodeID.ChildByIndex 0 ] [ "a" ], Type.Variable [ NodeID.ChildByIndex 1 ] [ "b" ] ])
            , test "Record" <|
                expectation (Type.Record () [ { name = [ "a" ], tpe = Type.Variable () [ "varName" ] }, { name = [ "b" ], tpe = Type.Variable () [ "varName2" ] } ])
                    (Type.Record [] [ { name = [ "a" ], tpe = Type.Variable [ NodeID.ChildByName [ "a" ] ] [ "varName" ] }, { name = [ "b" ], tpe = Type.Variable [ NodeID.ChildByName [ "b" ] ] [ "varName2" ] } ])
            , test "ExtensibleRecord" <|
                expectation (Type.ExtensibleRecord () [ "name" ] [ { name = [ "a" ], tpe = Type.Variable () [ "varName" ] }, { name = [ "b" ], tpe = Type.Variable () [ "varName2" ] } ])
                    (Type.ExtensibleRecord [] [ "name" ] [ { name = [ "a" ], tpe = Type.Variable [ NodeID.ChildByName [ "a" ] ] [ "varName" ] }, { name = [ "b" ], tpe = Type.Variable [ NodeID.ChildByName [ "b" ] ] [ "varName2" ] } ])
            , test "Function" <|
                expectation (Type.Function () (Type.Reference () ( [ [ "f" ] ], [ [ "q" ] ], [ "n" ] ) [ Type.Variable () [ "a" ], Type.Variable () [ "b" ] ]) (Type.Reference () ( [ [ "f" ] ], [ [ "q" ] ], [ "n" ] ) [ Type.Variable () [ "a" ], Type.Variable () [ "b" ] ]))
                    (Type.Function []
                        (Type.Reference [ NodeID.ChildByIndex 0 ] ( [ [ "f" ] ], [ [ "q" ] ], [ "n" ] ) [ Type.Variable [ NodeID.ChildByIndex 0, NodeID.ChildByIndex 0 ] [ "a" ], Type.Variable [ NodeID.ChildByIndex 0, NodeID.ChildByIndex 1 ] [ "b" ] ])
                        (Type.Reference [ NodeID.ChildByIndex 1 ] ( [ [ "f" ] ], [ [ "q" ] ], [ "n" ] ) [ Type.Variable [ NodeID.ChildByIndex 1, NodeID.ChildByIndex 0 ] [ "a" ], Type.Variable [ NodeID.ChildByIndex 1, NodeID.ChildByIndex 1 ] [ "b" ] ])
                    )
            , test "Unit" <|
                expectation (Type.Unit ())
                    (Type.Unit [])
            ]


mapValueAttributeTest : Test
mapValueAttributeTest =
    let
        expectation : Value attr attr -> Value NodeID.NodePath NodeID.NodePath -> b -> Expect.Expectation
        expectation original mapped =
            \_ -> Expect.equal mapped (NodeID.mapValueAttributesWithNodePath always original)
    in
        describe "mapValueAttributesWithNodePath"
            [ test "Unit" <|
                expectation (Value.Unit ())
                    (Value.Unit [])
            , test "Literal" <|
                expectation (Value.Literal () (BoolLiteral True))
                    (Value.Literal [] (BoolLiteral True))
            , test "Constructor" <|
                expectation (Value.Constructor () ( [ [ "f" ] ], [ [ "q" ] ], [ "n" ] ))
                    (Value.Constructor [] ( [ [ "f" ] ], [ [ "q" ] ], [ "n" ] ))
            , test "Variable" <|
                expectation (Value.Variable () [ "name" ])
                    (Value.Variable [] [ "name" ])
            , test "Reference" <|
                expectation (Value.Reference () ( [ [ "f" ] ], [ [ "q" ] ], [ "n" ] ))
                    (Value.Reference [] ( [ [ "f" ] ], [ [ "q" ] ], [ "n" ] ))
            , test "FieldFunction" <|
                expectation (Value.FieldFunction () [ "name" ])
                    (Value.FieldFunction [] [ "name" ])
            , test "Tuple" <|
                expectation (Value.Tuple () [ Value.Unit (), Value.Unit () ])
                    (Value.Tuple [] [ Value.Unit [ NodeID.ChildByIndex 0 ], Value.Unit [ NodeID.ChildByIndex 1 ] ])
            , test "List" <|
                expectation (Value.List () [ Value.Unit (), Value.Unit () ])
                    (Value.List [] [ Value.Unit [ NodeID.ChildByIndex 0 ], Value.Unit [ NodeID.ChildByIndex 1 ] ])
            , test "Field" <|
                expectation (Value.Field () (Value.Unit ()) [ "name" ])
                    (Value.Field [] (Value.Unit [ NodeID.ChildByIndex 0 ]) [ "name" ])
            , test "Apply" <|
                expectation (Value.Apply () (Value.Literal () (BoolLiteral True)) (Value.Literal () (BoolLiteral True)))
                    (Value.Apply [] (Value.Literal [ NodeID.ChildByIndex 0 ] (BoolLiteral True)) (Value.Literal [ NodeID.ChildByIndex 1 ] (BoolLiteral True)))
            , test "IfThenElse" <|
                expectation (Value.IfThenElse () (Value.Literal () (BoolLiteral True)) (Value.Literal () (BoolLiteral True)) (Value.Unit ()))
                    (Value.IfThenElse [] (Value.Literal [ NodeID.ChildByIndex 0 ] (BoolLiteral True)) (Value.Literal [ NodeID.ChildByIndex 1 ] (BoolLiteral True)) (Value.Unit [ NodeID.ChildByIndex 2 ]))
            , test "Lambda" <|
                expectation (Value.Lambda () (Value.EmptyListPattern ()) (Value.Literal () (BoolLiteral True)))
                    (Value.Lambda [] (Value.EmptyListPattern [ NodeID.ChildByIndex 0 ]) (Value.Literal [ NodeID.ChildByIndex 1 ] (BoolLiteral True)))
            , test "PatternMatch" <|
                expectation (Value.PatternMatch () (Value.Variable () [ "name" ]) [ ( Value.EmptyListPattern (), Value.Literal () (BoolLiteral True) ) ])
                    (Value.PatternMatch []
                        (Value.Variable [ NodeID.ChildByIndex 0 ] [ "name" ])
                        [ ( Value.EmptyListPattern [ NodeID.ChildByIndex 1, NodeID.ChildByIndex 0, NodeID.ChildByIndex 0 ]
                          , Value.Literal [ NodeID.ChildByIndex 1, NodeID.ChildByIndex 0, NodeID.ChildByIndex 1 ] (BoolLiteral True)
                          )
                        ]
                    )
            , test "Record" <|
                expectation (Value.Record () (Dict.fromList [ ( [ "a" ], Value.List () [] ), ( [ "b" ], Value.List () [ Value.Unit () ] ) ]))
                    (Value.Record []
                        (Dict.fromList
                            [ ( [ "a" ], Value.List [ NodeID.ChildByName [ "a" ] ] [] )
                            , ( [ "b" ], Value.List [ NodeID.ChildByName [ "b" ] ] [ Value.Unit [ NodeID.ChildByName [ "b" ], NodeID.ChildByIndex 0 ] ] )
                            ]
                        )
                    )
            , test "UpdateRecord" <|
                expectation (Value.UpdateRecord () (Value.Record () (Dict.fromList [ ( [ "a" ], Value.List () [] ), ( [ "b" ], Value.List () [ Value.Unit () ] ) ])) (Dict.fromList [ ( [ "a" ], Value.List () [] ), ( [ "b" ], Value.List () [ Value.Unit () ] ) ]))
                    (Value.UpdateRecord []
                        (Value.Record [ NodeID.ChildByIndex 0 ]
                            (Dict.fromList
                                [ ( [ "a" ], Value.List [ NodeID.ChildByIndex 0, NodeID.ChildByName [ "a" ] ] [] )
                                , ( [ "b" ], Value.List [ NodeID.ChildByIndex 0, NodeID.ChildByName [ "b" ] ] [ Value.Unit [ NodeID.ChildByIndex 0, NodeID.ChildByName [ "b" ], NodeID.ChildByIndex 0 ] ] )
                                ]
                            )
                        )
                        (Dict.fromList
                            [ ( [ "a" ], Value.List [ NodeID.ChildByIndex 1, NodeID.ChildByName [ "a" ] ] [] )
                            , ( [ "b" ], Value.List [ NodeID.ChildByIndex 1, NodeID.ChildByName [ "b" ] ] [ Value.Unit [ NodeID.ChildByIndex 1, NodeID.ChildByName [ "b" ], NodeID.ChildByIndex 0 ] ] )
                            ]
                        )
                    )
            , test "Destructure" <|
                expectation (Value.Destructure () (Value.EmptyListPattern ()) (Value.Literal () (BoolLiteral True) ) (Value.Unit ()))
                    (Value.Destructure [] (Value.EmptyListPattern [ NodeID.ChildByIndex 0 ]) (Value.Literal [ NodeID.ChildByIndex 1 ] (BoolLiteral True)) (Value.Unit [ NodeID.ChildByIndex 2 ]))
            , test "LetDefinition" <|
                expectation (Value.LetDefinition () ["letDef"] 
                    { inputTypes = [ ( [ "name" ], (), Type.Unit () ) ]
                    , outputType = Type.Variable () [ "var" ]
                    , body = Value.Unit ()
                    }
                    (Value.Variable () [ "ondef" ]))
                    (Value.LetDefinition [] ["letDef"] 
                    { inputTypes = [ ( [ "name" ], [NodeID.ChildByIndex 0, NodeID.ChildByName [ "inputTypes" ], NodeID.ChildByIndex 0, NodeID.ChildByIndex 0], Type.Unit [NodeID.ChildByIndex 0, NodeID.ChildByName [ "inputTypes" ], NodeID.ChildByIndex 0, NodeID.ChildByIndex 1] ) ]
                    , outputType = Type.Variable [NodeID.ChildByIndex 0, NodeID.ChildByName [ "outputType" ]] [ "var" ]
                    , body = Value.Unit [NodeID.ChildByIndex 0, NodeID.ChildByName ["body"]]
                    }
                    (Value.Variable [NodeID.ChildByIndex 1] [ "ondef" ]))
            ]
