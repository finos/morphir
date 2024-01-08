module Morphir.Snowpark.MappingContextTests exposing
    ( functionClassificationTests
    , typeClassificationTests
    )

import Dict
import Expect
import Morphir.IR.AccessControlled exposing (public)
import Morphir.IR.FQName as FQName
import Morphir.IR.Module exposing (emptyDefinition)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type exposing (Type(..))
import Morphir.IR.Value as Value
import Morphir.Snowpark.CommonTestUtils exposing (mListTypeOf)
import Morphir.Snowpark.MappingContext as MappingContext exposing (FunctionClassification(..))
import Set
import Test exposing (Test, describe, test)


floatTypeInstance : Type ()
floatTypeInstance =
    Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) []


stringTypeInstance : Type ()
stringTypeInstance =
    Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "string" ] ], [ "string" ] ) []


refToLocalType : String -> Type ()
refToLocalType name =
    Reference () (FQName.fromString ("UTest:MyMod:" ++ name) ":") []


testDistributionName =
    Path.fromString "UTest"


testDistributionPackage =
    { modules =
        Dict.fromList
            [ ( Path.fromString "MyMod"
              , public
                    { emptyDefinition
                        | types =
                            Dict.fromList
                                [ -- A type alias
                                  ( Name.fromString "Price"
                                  , public { doc = "", value = Type.TypeAliasDefinition [ [ "t1" ] ] floatTypeInstance }
                                  )
                                , -- A record with simple types
                                  ( Name.fromString "Emp1"
                                  , public
                                        { doc = ""
                                        , value =
                                            Type.TypeAliasDefinition []
                                                (Type.Record ()
                                                    [ { name = Name.fromString "name", tpe = stringTypeInstance }
                                                    , { name = Name.fromString "salary", tpe = floatTypeInstance }
                                                    ]
                                                )
                                        }
                                  )
                                , -- A Union type without constructors with parameters
                                  ( Name.fromString "DeptKind"
                                  , public
                                        { doc = ""
                                        , value =
                                            Type.CustomTypeDefinition []
                                                (public
                                                    (Dict.fromList
                                                        [ ( Name.fromString "Hr", [] )
                                                        , ( Name.fromString "It", [] )
                                                        ]
                                                    )
                                                )
                                        }
                                  )
                                , -- A Union type with constructors with parameters
                                  ( Name.fromString "FloatOptionType"
                                  , public
                                        { doc = ""
                                        , value =
                                            Type.CustomTypeDefinition []
                                                (public
                                                    (Dict.fromList
                                                        [ ( Name.fromString "No", [] )
                                                        , ( Name.fromString "Yes", [ ( [], floatTypeInstance ) ] )
                                                        ]
                                                    )
                                                )
                                        }
                                  )
                                , -- A record with simple types
                                  ( Name.fromString "Emp2"
                                  , public
                                        { doc = ""
                                        , value =
                                            Type.TypeAliasDefinition []
                                                (Type.Record ()
                                                    [ { name = Name.fromString "name", tpe = stringTypeInstance }
                                                    , { name = Name.fromString "salary", tpe = Reference () (FQName.fromString "UTest:MyMod:Price" ":") [] }
                                                    , { name = Name.fromString "dept", tpe = Reference () (FQName.fromString "UTest:MyMod:DeptKind" ":") [] }
                                                    ]
                                                )
                                        }
                                  )
                                , -- A record with nested types
                                  ( Name.fromString "Dept1"
                                  , public
                                        { doc = ""
                                        , value =
                                            Type.TypeAliasDefinition []
                                                (Type.Record ()
                                                    [ { name = Name.fromString "name", tpe = stringTypeInstance }
                                                    , { name = Name.fromString "head", tpe = Reference () (FQName.fromString "UTest:MyMod:Emp1" ":") [] }
                                                    ]
                                                )
                                        }
                                  )
                                , -- A type alias of an alias
                                  ( Name.fromString "LocalPrice"
                                  , public { doc = "", value = Type.TypeAliasDefinition [ [ "t1" ] ] (refToLocalType "Price") }
                                  )
                                ]
                        , values =
                            Dict.fromList
                                [ ( Name.fromString "fromBasicTypesToSimpleRecords"
                                  , public
                                        { doc = ""
                                        , value =
                                            { inputTypes = [ ( Name.fromString "a", floatTypeInstance, floatTypeInstance ) ]
                                            , outputType = Reference () (FQName.fromString "UTest:MyMod:Emp2" ":") []
                                            , body = Value.Variable (Type.Unit ()) [ "_" ] -- dummy body
                                            }
                                        }
                                  )
                                , ( Name.fromString "fromComplexTypesToValues"
                                  , public
                                        { doc = ""
                                        , value =
                                            { inputTypes = [ ( Name.fromString "a", refToLocalType "Dept1", refToLocalType "Dept1" ) ]
                                            , outputType = stringTypeInstance
                                            , body = Value.Variable (Type.Unit ()) [ "_" ] -- dummy body
                                            }
                                        }
                                  )
                                , ( Name.fromString "fromComplexTypesToDataFrames"
                                  , public
                                        { doc = ""
                                        , value =
                                            { inputTypes = [ ( Name.fromString "a", refToLocalType "Dept1", refToLocalType "Dept1" ) ]
                                            , outputType = mListTypeOf (refToLocalType "Emp2")
                                            , body = Value.Variable (Type.Unit ()) [ "_" ] -- dummy body
                                            }
                                        }
                                  )
                                , ( Name.fromString "fromCustomTypesToValues"
                                  , public
                                        { doc = ""
                                        , value =
                                            { inputTypes = [ ( Name.fromString "a", refToLocalType "DeptKind", refToLocalType "DeptKind" ) ]
                                            , outputType = stringTypeInstance
                                            , body = Value.Variable (Type.Unit ()) [ "_" ] -- dummy body
                                            }
                                        }
                                  )
                                , ( Name.fromString "fromAliasedSimpleValuesToSimpleValues"
                                  , public
                                        { doc = ""
                                        , value =
                                            { inputTypes = [ ( Name.fromString "a", refToLocalType "LocalPrice", refToLocalType "LocalPrice" ) ]
                                            , outputType = refToLocalType "Price"
                                            , body = Value.Variable (Type.Unit ()) [ "_" ] -- dummy body
                                            }
                                        }
                                  )
                                , ( Name.fromString "fromDataFramesToSimpleValues"
                                  , public
                                        { doc = ""
                                        , value =
                                            { inputTypes = [ ( Name.fromString "a", mListTypeOf (refToLocalType "Emp2"), mListTypeOf (refToLocalType "Emp2") ) ]
                                            , outputType = floatTypeInstance
                                            , body = Value.Variable (Type.Unit ()) [ "_" ] -- dummy body
                                            }
                                        }
                                  )
                                , ( Name.fromString "fromDataFramesToDataFrames"
                                  , public
                                        { doc = ""
                                        , value =
                                            { inputTypes = [ ( Name.fromString "a", mListTypeOf (refToLocalType "Emp2"), mListTypeOf (refToLocalType "Emp2") ) ]
                                            , outputType = mListTypeOf (refToLocalType "Emp2")
                                            , body = Value.Variable (Type.Unit ()) [ "_" ] -- dummy body
                                            }
                                        }
                                  )
                                ]
                    }
              )
            ]
    }


typeClassificationTests : Test
typeClassificationTests =
    let
        customizationOptions =
            { functionsToInline = Set.empty, functionsToCache = Set.empty }

        ( calculatedContext, _, _ ) =
            MappingContext.processDistributionModules testDistributionName testDistributionPackage customizationOptions

        assertCount =
            test "Types in context" <|
                \_ ->
                    Expect.equal 7 (Dict.size calculatedContext)

        assertTypeAliasLookup =
            test "Type alias lookup" <|
                \_ ->
                    Expect.equal True (MappingContext.isTypeAlias (FQName.fromString "UTest:MyMod:Price" ":") calculatedContext)

        assertNegativeTypeAliasLookup =
            test "Type negative alias lookup" <|
                \_ ->
                    Expect.equal False (MappingContext.isTypeAlias (FQName.fromString "UTest:MyMod:Emp1" ":") calculatedContext)

        assertTypeRecordSimpleLookup =
            test "Lookup for type with simple types" <|
                \_ ->
                    Expect.equal True (MappingContext.isRecordWithSimpleTypes (FQName.fromString "UTest:MyMod:Emp1" ":") calculatedContext)

        assertTypeRecordSimpleWithAliasesLookup =
            test "Lookup for type with simple types with aliases" <|
                \_ ->
                    Expect.equal True (MappingContext.isRecordWithSimpleTypes (FQName.fromString "UTest:MyMod:Emp2" ":") calculatedContext)

        assertNegativeTestOnComplexTypePredicate =
            test "Lookup type that should not be classifed as record with complex fields" <|
                \_ ->
                    Expect.equal False (MappingContext.isRecordWithComplexTypes (FQName.fromString "UTest:MyMod:Emp2" ":") calculatedContext)

        assertTypeRecordWithComplexLookup =
            test "Lookup type that should be classified as record with complex fields" <|
                \_ ->
                    Expect.equal True (MappingContext.isRecordWithComplexTypes (FQName.fromString "UTest:MyMod:Dept1" ":") calculatedContext)

        assertLookupForUnionTypeWithNames =
            test "Lookup type that should be classified as union type without constructors with parameters" <|
                \_ ->
                    Expect.equal True (MappingContext.isUnionTypeWithoutParams (FQName.fromString "UTest:MyMod:DeptKind" ":") calculatedContext)

        assertLookupForUnionTypeWithParameters =
            test "Lookup type that should be classified as union type with constructors having parameters" <|
                \_ ->
                    Expect.equal True (MappingContext.isUnionTypeWithParams (FQName.fromString "UTest:MyMod:FloatOptionType" ":") calculatedContext)
    in
    describe "type classification"
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


functionClassificationTests : Test
functionClassificationTests =
    let
        customizationOptions =
            { functionsToInline = Set.empty, functionsToCache = Set.empty }

        ( _, functionClassificationInfo, _ ) =
            MappingContext.processDistributionModules testDistributionName testDistributionPackage customizationOptions

        assertFunctionClassificationForReturningRecords =
            test "Lookup function classficiation for simple to record types" <|
                \_ ->
                    let
                        funcName =
                            FQName.fromString "UTest:MyMod:fromBasicTypesToSimpleRecords" ":"
                    in
                    Expect.equal FromDfValuesToDfValues (MappingContext.getFunctionClassification funcName functionClassificationInfo)

        assertFunctionClassificationForReceivingComplexTypes =
            test "Lookup function classification function receiving complex types and returning simple values" <|
                \_ ->
                    let
                        funcName =
                            FQName.fromString "UTest:MyMod:fromComplexTypesToValues" ":"
                    in
                    Expect.equal FromComplexToValues (MappingContext.getFunctionClassification funcName functionClassificationInfo)

        assertFunctionWithReceivingCustomTypes =
            test "Lookup function classficiation function receiving custom types and returning simple values" <|
                \_ ->
                    let
                        funcName =
                            FQName.fromString "UTest:MyMod:fromCustomTypesToValues" ":"
                    in
                    Expect.equal FromDfValuesToDfValues (MappingContext.getFunctionClassification funcName functionClassificationInfo)

        assertFunctionClassificationOfAliasedSimpleValuesToSimpleValues =
            test "Lookup function classification aliased simple values to simple values" <|
                \_ ->
                    let
                        funcName =
                            FQName.fromString "UTest:MyMod:fromAliasedSimpleValuesToSimpleValues" ":"
                    in
                    Expect.equal FromDfValuesToDfValues (MappingContext.getFunctionClassification funcName functionClassificationInfo)

        assertFunctionClassificationOfComplexTypesToDataFrames =
            test "Lookup function classification complex types to dataframes" <|
                \_ ->
                    let
                        funcName =
                            FQName.fromString "UTest:MyMod:fromComplexTypesToDataFrames" ":"
                    in
                    Expect.equal FromComplexValuesToDataFrames (MappingContext.getFunctionClassification funcName functionClassificationInfo)

        assertFunctionClassificationOfDataFramesToSimpleValues =
            test "Lookup function classification dataframes to simple values" <|
                \_ ->
                    let
                        funcName =
                            FQName.fromString "UTest:MyMod:fromDataFramesToSimpleValues" ":"
                    in
                    Expect.equal FromDataFramesToValues (MappingContext.getFunctionClassification funcName functionClassificationInfo)

        assertFunctionClassificationOfDataFramesToDataFrames =
            test "Lookup function classification dataframes to dataframes" <|
                \_ ->
                    let
                        funcName =
                            FQName.fromString "UTest:MyMod:fromDataFramesToDataFrames" ":"
                    in
                    Expect.equal FromDataFramesToDataFrames (MappingContext.getFunctionClassification funcName functionClassificationInfo)
    in
    describe "function classification"
        [ assertFunctionClassificationForReturningRecords
        , assertFunctionClassificationForReceivingComplexTypes
        , assertFunctionWithReceivingCustomTypes
        , assertFunctionClassificationOfAliasedSimpleValuesToSimpleValues
        , assertFunctionClassificationOfComplexTypesToDataFrames
        , assertFunctionClassificationOfDataFramesToSimpleValues
        , assertFunctionClassificationOfDataFramesToDataFrames
        ]
