module Morphir.Snowpark.AccessElementTests exposing (mapFieldAccessTests)

import Dict exposing (Dict(..))
import Expect
import Morphir.IR.FQName as FQName
import Morphir.IR.Name as Name
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.CommonTestUtils
    exposing
        ( testDistributionName
        , testDistributionPackage
        )
import Morphir.Snowpark.MapExpressionsToDataFrameOperations exposing (mapValue)
import Morphir.Snowpark.MappingContext as MappingContext exposing (emptyValueMappingContext)
import Set
import Test exposing (Test, describe, test)


stringReference : Type.Type ()
stringReference =
    Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "boolean" ] ) []


recordFieldAccess : Value.Value () (Type.Type ())
recordFieldAccess =
    Value.Field
        stringReference
        (Value.Variable
            (Type.Reference () (FQName.fromString "UTest:MyMod:Emp" ":") [])
            (Name.fromString "x")
        )
        (Name.fromString "salary")


referenceToDefinition : Value.Value () (Type.Type ())
referenceToDefinition =
    Value.Reference stringReference (FQName.fromString "ATest:AMod:counter" ":")


constructorReference : Value.Value () (Type.Type ())
constructorReference =
    Value.Constructor
        (Type.Reference () (FQName.fromString "UTest:MyMod:DeptKind" ":") [])
        (FQName.fromString "UTest:MyMod:Hr" ":")


mapFieldAccessTests : Test
mapFieldAccessTests =
    let
        customizationOptions =
            { functionsToInline = Set.empty, functionsToCache = Set.empty }

        ( calculatedContext, _, _ ) =
            MappingContext.processDistributionModules testDistributionName testDistributionPackage customizationOptions

        valueMapContext =
            { emptyValueMappingContext | typesContextInfo = calculatedContext }

        assertMapFieldAccess =
            test "Convert record field reference" <|
                \_ ->
                    let
                        ( mapped, _ ) =
                            mapValue recordFieldAccess valueMapContext
                    in
                    Expect.equal (Scala.Ref [ "utest", "MyMod", "Emp" ] "salary") mapped

        assertMapExternalDefinitionReference =
            test "Convert definition reference" <|
                \_ ->
                    let
                        ( mapped, _ ) =
                            mapValue referenceToDefinition valueMapContext
                    in
                    Expect.equal (Scala.Ref [ "atest", "AMod" ] "counter") mapped

        assertMapConstructorReference =
            test "Convert constructor reference" <|
                \_ ->
                    let
                        ( mapped, _ ) =
                            mapValue constructorReference valueMapContext
                    in
                    Expect.equal (Scala.Ref [ "utest", "MyMod", "DeptKind" ] "Hr") mapped
    in
    describe "AccessElementsTests"
        [ assertMapFieldAccess
        , assertMapExternalDefinitionReference
        , assertMapConstructorReference
        ]
