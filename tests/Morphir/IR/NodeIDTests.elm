module Morphir.IR.NodeIDTests exposing (..)

import Expect
import Dict
import Morphir.IR.NodeId as NodeID exposing (Error(..))
import Morphir.IR.Value as Value exposing (Pattern(..), Value(..))
import Morphir.IR.Literal as Literal exposing (Literal(..))
import Morphir.IR.Type as Type exposing (Type(..))
import Morphir.IR.FQName exposing (fqn)
import Test exposing (Test, describe, test, only)

getTypeAttributeByPathTest : Test
getTypeAttributeByPathTest =
    let
        expectation expectedAttr nodePath value =
            (\_ -> (Expect.equal (Ok expectedAttr) (NodeID.getTypeAttributeByPath nodePath value)))
    in
    describe "TypeNodePath"
    [test "variable" <|
        expectation 0 
            [] 
            (Type.Variable 0 ["var"])
    , test "tuple" <|
        expectation 2 
            [NodeID.ChildByIndex 1] 
            (Type.Tuple 0 [(Type.Variable 1 ["var1"]), (Type.Variable 2 ["var2"])])
    , test "record" <|
        expectation 3 
            [NodeID.ChildByName ["f1"], NodeID.ChildByIndex 1] 
            (Type.Record 0 
            [
                { name = ["f1"]
                    , tpe = (Type.Tuple 1 [(Type.Variable 2 ["var1"]), (Type.Variable 3 ["var2"])])
                }, 
                { name = ["f2"]
                    , tpe = (Type.Variable 4 ["var"])
                }
            ])
    , test "unit" <|
        expectation 99
            [] 
            (Type.Unit 99)
    , test "function" <|
        expectation 4
            [NodeID.ChildByIndex 1] 
            (Type.Function 0 (Type.Tuple 1 [(Type.Variable 2 ["var1"]), (Type.Variable 3 ["var2"])]) (Type.Tuple 4 [(Type.Variable 5 ["var1"]), (Type.Variable 6 ["var2"])]))
    , test "reference" <|
        expectation 99
            [NodeID.ChildByIndex 1] 
            (Type.Reference 0 (fqn "" "" "")
            [   (Type.Unit 9),
                (Type.Unit 99)
            ])
    , test "extensible record" <|
        expectation 9
            [NodeID.ChildByName ["f1"], NodeID.ChildByIndex 1, NodeID.ChildByIndex 0] 
            (Type.ExtensibleRecord 0 []
            [   { name = ["f1"]
                , tpe = (Type.Tuple 1 [(Type.Variable 2 ["var1"]), (Type.Reference 0 (fqn "" "" "") [(Type.Unit 9), (Type.Unit 99)])])
                }, 
                { name = ["f2"]
                    , tpe = (Type.Variable 4 ["var"])
                }
            ])
    , test "error" <|
        (\_ -> (Expect.equal (Err <| InvalidPath "Path is invalid after #f1") (NodeID.getTypeAttributeByPath [NodeID.ChildByName ["f1"], NodeID.ChildByIndex 3] (Type.Record 0 
            [
                { name = ["f1"]
                    , tpe = (Type.Tuple 1 [(Type.Variable 2 ["var1"]), (Type.Variable 3 ["var2"])])
                }, 
                { name = ["f2"]
                    , tpe = (Type.Variable 4 ["var"])
                }
            ]))))
        ]

getValueAttributeByPathTest : Test
getValueAttributeByPathTest = 
    let
        expectation expectedAttr nodePath value =
            (\_ -> (Expect.equal (Ok expectedAttr) (NodeID.getValueAttributeByPath nodePath value)))
    in
    describe "ValueNodePath"
    [test "Unit" <|
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
        (\_ -> (Expect.equal (Err <| InvalidPath "Path is invalid") (NodeID.getValueAttributeByPath [NodeID.ChildByIndex 0] (Value.Constructor 97 (fqn "" "" "")))))
    , test "Tuple" <|
        expectation 95
            [NodeID.ChildByIndex 0] 
            (Value.Tuple 96 [(Value.Literal 95 (BoolLiteral True)), (Value.Literal 94 (BoolLiteral False))])
    , test "List" <|
        expectation 90
            [NodeID.ChildByIndex 2] 
            (Value.Tuple 93 [(Value.Literal 92 (BoolLiteral True)), (Value.Literal 91 (BoolLiteral False)), (Value.Literal 90 (BoolLiteral False))])
    , test "Record (inside tuple)" <|
        expectation 85
            [NodeID.ChildByIndex 1, NodeID.ChildByName ["field2"]] 
            (Value.Tuple 89 [(Value.Literal 88 (BoolLiteral True)), (Value.Record 87 (Dict.fromList [(["field"], (Value.Unit 86) ), (["field2"], (Value.Unit 85) )]))])
    , test "Variable" <|
        expectation 84
            [] 
            (Value.Variable 84 ["varName"])
    , test "Reference" <|
        expectation 83
            [] 
            (Value.Reference 83 (fqn "f" "q" "n"))
    , test "Field" <|
        expectation 82
            [] 
            (Value.Field 82 (Value.Unit 81) ["field"])
    , test "inside of Field" <|
        expectation 79
            [NodeID.ChildByIndex 0] 
            (Value.Field 80 (Value.Unit 79) ["field"])
    , test "FieldFunction" <|
        expectation 78
            [] 
            (Value.FieldFunction 78 ["fieldfunction"])
    , test "Apply" <|
        expectation 75
            [NodeID.ChildByIndex 1] 
            (Value.Apply 77 (Value.Literal 76 (BoolLiteral True)) (Value.Literal 75 (BoolLiteral True)))
    , test "Lambda" <|
        expectation 73
            [NodeID.ChildByIndex 0] 
            (Value.Lambda 74 (Value.WildcardPattern 73) (Value.Literal 72 (BoolLiteral True)))
    , test "IfThenElse" <|
        expectation 69
            [NodeID.ChildByIndex 1] 
            (Value.IfThenElse 71 (Value.Variable 70 ["if"]) (Value.Variable 69 ["then"]) (Value.Variable 68 ["else"]))
    , test "Destructure pattern" <|
        expectation 48
            [NodeID.ChildByIndex 0] 
            (Value.Destructure 49 (Value.EmptyListPattern 48) (Value.Literal 47 (BoolLiteral True)) (Value.Unit 46))
    , test "Destructure value 2" <|
        expectation 42
            [NodeID.ChildByIndex 2] 
            (Value.Destructure 45 (Value.EmptyListPattern 44) (Value.Literal 43 (BoolLiteral True)) (Value.Unit 42))
    , test "LetDefinition outputType" <|
        expectation 40
            [NodeID.ChildByIndex 0, NodeID.ChildByIndex 1] 
            (Value.LetDefinition 41 ["letDefinition"] 
                { 
                    inputTypes = []
                    , outputType = (Type.Variable 40 ["var"])
                    , body = (Value.Unit 39)
                }
                (Value.Unit 38)
            )
    , test "LetDefinition body" <|
        expectation 34
            [NodeID.ChildByIndex 0, NodeID.ChildByName ["body"], NodeID.ChildByIndex 0 ] 
            (Value.LetDefinition 37 ["letDefinition"] 
                { 
                    inputTypes = []
                    , outputType = (Type.Variable 36 ["var"])
                    , body = (Value.Tuple 35 [(Value.Literal 34 (BoolLiteral True)), (Value.Literal 33 (BoolLiteral False))])
                }
                (Value.Unit 32)
            )
    , test "LetDefinition inputTypes" <|
        expectation 29
            [ NodeID.ChildByIndex 0, NodeID.ChildByName ["inputTypes"], NodeID.ChildByIndex 0, NodeID.ChildByIndex 1 ] 
            (Value.LetDefinition 31 ["letDefinition"] 
                { 
                    inputTypes = [(["name"], 30, (Type.Unit 29))]
                    , outputType = (Type.Variable 28 ["var"])
                    , body = (Value.Unit 27)
                }
                (Value.Unit 26)
            )
    ]