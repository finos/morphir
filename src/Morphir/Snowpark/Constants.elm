module Morphir.Snowpark.Constants exposing
    ( AliasVariableInfo
    , LambdaInfo
    , MapValueType
    , MappingFunc
    , ValueGenerationResult
    , VariableInformation
    , applyForSnowparkTypesType
    , applyForSnowparkTypesTypeExpr
    , applySnowparkFunc
    , transformToArgsValue
    , typeRefForSnowparkType
    , typeRefForSnowparkTypesType
    )

import Morphir.IR.Name as Name
import Morphir.IR.Type as TypeIR
import Morphir.IR.Value exposing (Pattern(..), TypedValue, Value(..))
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.GenerationReport exposing (GenerationIssue)
import Morphir.Snowpark.MappingContext exposing (ValueMappingContext)


snowflakeNamespace : List String
snowflakeNamespace =
    [ "com", "snowflake", "snowpark" ]


functionsNamespace : List String
functionsNamespace =
    snowflakeNamespace ++ [ "functions" ]


typesNamespace : List String
typesNamespace =
    snowflakeNamespace ++ [ "types" ]


applySnowparkFunc : String -> List Scala.Value -> Scala.Value
applySnowparkFunc name args =
    applyFunctionName functionsNamespace name args


transformToArgsValue : List Scala.Value -> List Scala.ArgValue
transformToArgsValue valueList =
    List.map (\x -> Scala.ArgValue Nothing x) valueList


typeRefForSnowparkType : String -> Scala.Type
typeRefForSnowparkType typeName =
    Scala.TypeRef snowflakeNamespace typeName


typeRefForSnowparkTypesType : String -> Scala.Type
typeRefForSnowparkTypesType typeName =
    Scala.TypeRef typesNamespace typeName


applyForSnowparkTypesType : String -> List Scala.Value -> Scala.Value
applyForSnowparkTypesType name args =
    applyFunctionName typesNamespace name args


applyForSnowparkTypesTypeExpr : String -> Scala.Value
applyForSnowparkTypesTypeExpr name =
    Scala.Ref typesNamespace name


applyFunctionName : List String -> String -> List Scala.Value -> Scala.Value
applyFunctionName namespace name args =
    Scala.Apply
        (Scala.Ref namespace name)
        (args |> List.map (\v -> Scala.ArgValue Nothing v))


type alias ValueGenerationResult =
    ( Scala.Value, List GenerationIssue )


type alias MapValueType =
    TypedValue -> ValueMappingContext -> ( Scala.Value, List GenerationIssue )


type alias VariableInformation =
    ( List Scala.Value, List ( String, Scala.Value ) )


type alias MappingFunc =
    ( MapValueType, ValueMappingContext )


type alias AliasVariableInfo =
    { aliasName : List Scala.Value
    , variables : VariableInformation
    }


type alias LambdaInfo ta =
    { lambdaPattern : Pattern (TypeIR.Type ())
    , lambdaBody : Value ta (TypeIR.Type ())
    , groupByName : Name.Name
    , firstParameter : Name.Name
    }
