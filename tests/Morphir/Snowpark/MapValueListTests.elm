module Morphir.Snowpark.MapValueListTests exposing (mapValueListTest)

import Expect
import Test exposing (Test, describe, test)
import Morphir.Snowpark.Backend exposing (mapValue)
import Morphir.IR.Value as ValueIR
import Morphir.IR.Literal as Literal
import Morphir.IR.Type as TypeIR
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.MappingContext exposing (emptyValueMappingContext)
import Morphir.Snowpark.CommonTestUtils exposing (morphirNamespace)


createLiteral : String -> ValueIR.Value va (TypeIR.Type ())
createLiteral name = 
    ValueIR.Literal (
            TypeIR.Reference 
                        ()
                        ( morphirNamespace,[["string"]],["string"] )
                        []
        )
        (Literal.StringLiteral name)


listTest : ValueIR.Value ta (TypeIR.Type ())
listTest =  ValueIR.List (
                    TypeIR.Reference 
                            ()
                            (morphirNamespace,[["list"]],["list"]) 
                            [
                                TypeIR.Reference 
                                    () 
                                    (morphirNamespace,[["string"]],["string"])
                                    []
                            ]
                )
                [
                    createLiteral "a"
                    ,createLiteral "b"
                    ,createLiteral "c"
                ]

itemList : String -> Scala.Value
itemList name = 
    Scala.Apply (Scala.Ref ["com","snowflake","snowpark","functions"] "lit")
    [Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit name))]

listExpectedTest : Scala.Value
listExpectedTest = 
            Scala.Apply 
                (Scala.Variable "Seq")
                [ Scala.ArgValue Nothing (itemList "a")
                , Scala.ArgValue Nothing (itemList "b")
                , Scala.ArgValue Nothing (itemList "c")]

memberTest: ValueIR.Value ta (TypeIR.Type ())
memberTest =
    ValueIR.Apply
    (TypeIR.Reference () (morphirNamespace,[["basics"]],["bool"]) []) 
    (ValueIR.Apply 
        (TypeIR.Function 
            () 
            (TypeIR.Reference () (morphirNamespace,[["list"]],["list"]) [TypeIR.Reference () (morphirNamespace,[["string"]],["string"]) []])
            (TypeIR.Reference () (morphirNamespace,[["basics"]],["bool"]) [])
        )
        (ValueIR.Reference
            (TypeIR.Function () (TypeIR.Reference () (morphirNamespace,[["string"]],["string"]) []) (TypeIR.Function () (TypeIR.Reference () (morphirNamespace,[["list"]],["list"]) [TypeIR.Reference () (morphirNamespace,[["string"]],["string"]) []]) (TypeIR.Reference () (morphirNamespace,[["basics"]],["bool"]) [])))
            (morphirNamespace,[["list"]],["member"])
        )
        (ValueIR.Variable (TypeIR.Reference () (morphirNamespace,[["string"]],["string"]) []) ["v"])
    )
    (
       listTest
    )

memberExpectedTest: Scala.Value
memberExpectedTest =
    Scala.Apply (Scala.Select (Scala.Variable "v") "in") [ Scala.ArgValue Nothing listExpectedTest ]
  
mapValueListTest : Test
mapValueListTest =
    let
        emptyContext = emptyValueMappingContext
        assertListTest =
            test ("list") <|
                \_ ->
                    Expect.equal (mapValue listTest emptyContext) listExpectedTest
        assertMemberTest =
            test ("member list") <|
                \_ ->
                    Expect.equal (mapValue memberTest emptyContext) memberExpectedTest 
    in
    describe "List functions"
        [
        assertListTest
        , assertMemberTest
        ]
    