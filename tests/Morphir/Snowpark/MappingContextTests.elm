module Morphir.Snowpark.MappingContextTests exposing (typeClassificationTests)

import Dict
import Set
import Test exposing (Test, describe, test)
import Expect
import Morphir.IR.Path as Path
import Morphir.IR.Module exposing (emptyDefinition)
import Morphir.IR.AccessControlled exposing (public)
import Morphir.IR.Name as Name
import Morphir.IR.Type as Type
import Morphir.IR.Type exposing (Type(..))
import Morphir.Snowpark.MappingContext as MappingContext
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.FQName as FQName


floatTypeInstance : Type ()
floatTypeInstance = Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) []

stringTypeInstance : Type ()
stringTypeInstance = Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "string" ] ], [ "string" ] ) []


testDistributionName = (Path.fromString "UTest") 

testDistributionPackage = 
        ({ modules = Dict.fromList [
            ( Path.fromString "MyMod",
              public { emptyDefinition | types = Dict.fromList [
                -- A type alias
                (Name.fromString "Price", 
                 public { doc =  "", value = Type.TypeAliasDefinition [["t1"]] floatTypeInstance }),
                -- A record with simple types
                (Name.fromString "Emp1", 
                 public { doc =  "", value = Type.TypeAliasDefinition [] (Type.Record () [
                    { name = Name.fromString "name", tpe = stringTypeInstance },
                    { name = Name.fromString "salary", tpe = floatTypeInstance }
                 ]) }),
                 -- A Union type without constructors with parameters
                (Name.fromString "DeptKind", 
                 public { doc =  "", value = Type.CustomTypeDefinition [] (public (Dict.fromList [
                    (Name.fromString "Hr", [] ),
                    (Name.fromString "It", [] )
                 ])) }), 
                 -- A Union type with constructors with parameters
                (Name.fromString "FloatOptionType", 
                 public { doc =  "", value = Type.CustomTypeDefinition [] (public (Dict.fromList [
                    (Name.fromString "No", [] ),
                    (Name.fromString "Yes", [ ([],  floatTypeInstance ) ] )
                 ])) }), 
                 -- A record with simple types
                (Name.fromString "Emp2", 
                 public { doc =  "", value = Type.TypeAliasDefinition [] (Type.Record () [
                    { name = Name.fromString "name", tpe = stringTypeInstance },
                    { name = Name.fromString "salary", tpe = (Reference () (FQName.fromString "UTest:MyMod:Price" ":") []) },
                    { name = Name.fromString "dept", tpe = (Reference () (FQName.fromString "UTest:MyMod:DeptKind" ":") []) }
                 ]) }),
                  -- A record with nested types
                (Name.fromString "Dept1", 
                 public { doc =  "", value = Type.TypeAliasDefinition [] (Type.Record () [
                    { name = Name.fromString "name", tpe = stringTypeInstance },
                    { name = Name.fromString "head", tpe = (Reference () (FQName.fromString "UTest:MyMod:Emp1" ":") []) }
                 ]) })
              ] } )
        ]}) 

typeClassificationTests : Test
typeClassificationTests =
    let
        customizationOptions = {functionsToInline = Set.empty, functionsToCache = Set.empty}
        (calculatedContext, _, _) = MappingContext.processDistributionModules testDistributionName testDistributionPackage customizationOptions
        assertCount  =
            test ("Types in context") <|
                \_ ->
                    Expect.equal 6 (Dict.size calculatedContext)
        assertTypeAliasLookup  =
            test ("Type alias lookup") <|
                \_ ->
                    Expect.equal True (MappingContext.isTypeAlias (FQName.fromString "UTest:MyMod:Price" ":") calculatedContext)
        assertNegativeTypeAliasLookup  =
            test ("Type negative alias lookup") <|
                \_ ->
                    Expect.equal False (MappingContext.isTypeAlias (FQName.fromString "UTest:MyMod:Emp1" ":") calculatedContext)

        assertTypeRecordSimpleLookup  =
            test ("Lookup for type with simple types") <|
                \_ ->
                    Expect.equal True (MappingContext.isRecordWithSimpleTypes (FQName.fromString "UTest:MyMod:Emp1" ":") calculatedContext)
        assertTypeRecordSimpleWithAliasesLookup  =
            test ("Lookup for type with simple types with aliases") <|
                \_ ->
                    Expect.equal True (MappingContext.isRecordWithSimpleTypes (FQName.fromString "UTest:MyMod:Emp2" ":") calculatedContext)
        
        assertNegativeTestOnComplexTypePredicate  =
            test ("Lookup type that should not be classifed as record with complex fields") <|
                \_ ->
                    Expect.equal False (MappingContext.isRecordWithComplexTypes (FQName.fromString "UTest:MyMod:Emp2" ":") calculatedContext)

        assertTypeRecordWithComplexLookup  =
            test ("Lookup type that should be classified as record with complex fields") <|
                \_ ->
                    Expect.equal True (MappingContext.isRecordWithComplexTypes (FQName.fromString "UTest:MyMod:Dept1" ":") calculatedContext)

        assertLookupForUnionTypeWithNames  =
            test ("Lookup type that should be classified as union type without constructors with parameters") <|
                \_ ->
                    Expect.equal True (MappingContext.isUnionTypeWithoutParams (FQName.fromString "UTest:MyMod:DeptKind" ":") calculatedContext)
        
        assertLookupForUnionTypeWithParameters  =
            test ("Lookup type that should be classified as union type with constructors having parameters") <|
                \_ ->
                    Expect.equal True (MappingContext.isUnionTypeWithParams (FQName.fromString "UTest:MyMod:FloatOptionType" ":") calculatedContext)
    in
    describe "resolveTNam"
        [ assertCount
        , assertTypeAliasLookup
        , assertNegativeTypeAliasLookup
        , assertTypeRecordSimpleLookup
        , assertTypeRecordSimpleWithAliasesLookup
        , assertNegativeTestOnComplexTypePredicate
        , assertTypeRecordWithComplexLookup
        , assertLookupForUnionTypeWithNames
        , assertLookupForUnionTypeWithParameters
        ]
