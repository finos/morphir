module Morphir.Snowpark.AccessElementTests exposing (mapFieldAccessTests)

import Expect
import Test exposing (Test, describe, test)
import Dict exposing (Dict(..))
import Morphir.Snowpark.MapExpressionsToDataFrameOperations exposing (mapValue)
import Morphir.Scala.AST as Scala
import Morphir.IR.Value as Value
import Morphir.IR.Type as Type
import Morphir.Snowpark.MappingContext as MappingContext
import Morphir.IR.FQName as FQName
import Morphir.IR.Name as Name
import Morphir.Snowpark.CommonTestUtils exposing ( testDistributionName
                                                 , testDistributionPackage)
import Morphir.Snowpark.MappingContext exposing (emptyValueMappingContext)


stringReference : Type.Type ()
stringReference = Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "boolean" ] ) []

recordFieldAccess : Value.Value () (Type.Type ())
recordFieldAccess =
   Value.Field
      stringReference
      (Value.Variable
               (Type.Reference () (FQName.fromString "UTest:MyMod:Emp" ":") [])
               (Name.fromString "x"))
      (Name.fromString "salary")

referenceToDefinition : Value.Value () (Type.Type ())
referenceToDefinition =
    Value.Reference stringReference (FQName.fromString "ATest:AMod:counter" ":")

constructorReference : Value.Value () (Type.Type ())
constructorReference =
    Value.Constructor 
             (Type.Reference () (FQName.fromString "UTest:MyMod:DeptKind" ":") []) 
             (FQName.fromString "UTest:MyMod:Hr" ":")

mapFieldAccessTests: Test
mapFieldAccessTests =
    let
        (calculatedContext, _) = MappingContext.processDistributionModules testDistributionName testDistributionPackage
        valueMapContext = { emptyValueMappingContext | typesContextInfo = calculatedContext }
        assertMapFieldAccess =
            test ("Convert record field reference") <|
            \_ ->
                Expect.equal (Scala.Ref ["uTest","MyMod","Emp"] "salary") (mapValue recordFieldAccess valueMapContext)
        assertMapExternalDefinitionReference =
            test ("Convert definition reference") <|
            \_ ->
                Expect.equal (Scala.Ref ["aTest","AMod"] "counter") (mapValue referenceToDefinition valueMapContext)

        assertMapConstructorReference =
            test ("Convert constructor reference") <|
            \_ ->
                Expect.equal (Scala.Ref ["uTest","MyMod","DeptKind"] "Hr") (mapValue constructorReference valueMapContext)
    in
    describe "AccessElementsTests"
        [
            assertMapFieldAccess
            , assertMapExternalDefinitionReference
            , assertMapConstructorReference
        ]