module Morphir.Snowpark.AccessElementTests exposing (mapFieldAccessTests)

import Expect
import Test exposing (Test, describe, test)
import Dict exposing (Dict(..))
import Morphir.Snowpark.Backend exposing (mapValue)
import Morphir.Scala.AST as Scala
import Morphir.IR.Value as Value
import Morphir.IR.Type as Type
import Morphir.Snowpark.MappingContext as MappingContext
import Morphir.IR.FQName as FQName
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.AccessControlled exposing (public)
import Morphir.IR.Module exposing (emptyDefinition)


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

stringTypeInstance : Type.Type ()
stringTypeInstance = Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "string" ] ], [ "string" ] ) []

testDistributionName = (Path.fromString "UTest") 

typesDict = 
    Dict.fromList [
        -- A record with simple types
        (Name.fromString "Emp", 
        public { doc =  "", value = Type.TypeAliasDefinition [] (Type.Record () [
            { name = Name.fromString "firstname", tpe = stringTypeInstance },
            { name = Name.fromString "lastname", tpe = stringTypeInstance }
        ]) })
        , (Name.fromString "DeptKind", 
                 public { doc =  "", value = Type.CustomTypeDefinition [] (public (Dict.fromList [
                    (Name.fromString "Hr", [] ),
                    (Name.fromString "It", [] )
                 ])) }) 
    ]

testDistributionPackage = 
        ({ modules = Dict.fromList [
            ( Path.fromString "MyMod",
              public { emptyDefinition | types = typesDict } )
        ]}) 

mapFieldAccessTests: Test
mapFieldAccessTests =
    let
        calculatedContext = MappingContext.processDistributionModules testDistributionName testDistributionPackage
        assertMapFieldAccess =
            test ("Convert record field reference") <|
            \_ ->
                Expect.equal (Scala.Ref ["uTest","MyMod","Emp"] "salary") (mapValue recordFieldAccess calculatedContext)
        assertMapExternalDefinitionReference =
            test ("Convert definition reference") <|
            \_ ->
                Expect.equal (Scala.Ref ["aTest","AMod"] "counter") (mapValue referenceToDefinition calculatedContext)

        assertMapConstructorReference =
            test ("Convert constructor reference") <|
            \_ ->
                Expect.equal (Scala.Ref ["uTest","MyMod","DeptKind"] "Hr") (mapValue constructorReference calculatedContext)        
    in
    describe "AccessElementsTests"
        [
            assertMapFieldAccess
            , assertMapExternalDefinitionReference
            , assertMapConstructorReference
        ]