module Morphir.Snowpark.FunctionGenerationTests exposing (functionGenTests)


import Expect
import Test exposing (Test, describe, test)
import Dict exposing (Dict(..))
import Morphir.Scala.AST as Scala
import Morphir.IR.Value as Value
import Morphir.IR.Type as Type
import Morphir.Snowpark.MappingContext as MappingContext
import Morphir.IR.FQName as FQName
import Morphir.IR.Name as Name
import Morphir.IR.AccessControlled exposing (public)
import Morphir.Snowpark.Backend exposing (mapFunctionDefinition)
import Morphir.IR.Value as Value
import Morphir.IR.Name as Name
import Morphir.Snowpark.CommonTestUtils exposing (stringTypeInstance
                                                 , testDistributionName
                                                 , testDistributionPackage)
import Morphir.Snowpark.Constants exposing (typeRefForSnowparkType)
import Morphir.IR.Path as Path

functionGenTests: Test
functionGenTests =
    let
        calculatedContext = MappingContext.processDistributionModules testDistributionName testDistributionPackage
        typeOfRecord = Type.Reference () (FQName.fromString "UTest:MyMod:Emp" ":") []
        functionDefinition = 
                public { doc = ""
                         , value = { inputTypes = [(Name.fromString "a", typeOfRecord, typeOfRecord)
                                                  , (Name.fromString "b", stringTypeInstance, stringTypeInstance)]
                                    , outputType = stringTypeInstance
                                    , body = Value.Variable stringTypeInstance (Name.fromString "x")
                                    }}
        mappedFunctionDefinition =
                mapFunctionDefinition (Name.fromString "foo") functionDefinition (Path.fromString "UTest") calculatedContext

        expectedRef = Scala.Ref ["uTest", "MyMod"] "Emp" 
        expectedTypeRef = Scala.TypeRef ["uTest", "MyMod"] "Emp" 
        expectedFunctionBody = 
                Scala.Variable "x"
        expectedFunctionDeclaration = 
                Scala.FunctionDecl { modifiers = []
                                    , name = "foo"
                                    , typeArgs = []
                                    , args = [[Scala.ArgDecl [] (Scala.TypeRef ["uTest", "MyMod"] "Emp") "a" Nothing]
                                             , [Scala.ArgDecl [] (typeRefForSnowparkType "Column") "b" Nothing]
                                             ]
                                    , returnType = Just <| typeRefForSnowparkType "Column"
                                    , body = Just expectedFunctionBody
                                   }
        assertGenerationOfBasicFunction =
            test ("Convert function definition") <|
            \_ ->
                Expect.equal expectedFunctionDeclaration mappedFunctionDefinition

    in
    describe "FunctionGenerationTests"
        [
            assertGenerationOfBasicFunction
        ]