module Morphir.Snowpark.Constants exposing (..)
import Morphir.IR.Name as Name
import Morphir.Scala.AST as Scala
import Morphir.IR.Type as TypeIR
import Morphir.IR.Value as ValueIR exposing (Pattern(..), Value(..))
import Morphir.Snowpark.MappingContext exposing (ValueMappingContext)

snowflakeNamespace : List String
snowflakeNamespace = ["com", "snowflake", "snowpark"]

functionsNamespace : List String
functionsNamespace = snowflakeNamespace ++  ["functions"]

typesNamespace : List String
typesNamespace = snowflakeNamespace ++  ["types"]

applySnowparkFunc : String -> List Scala.Value -> Scala.Value
applySnowparkFunc name args =
    applyFunctionName functionsNamespace name args

transformToArgsValue : List Scala.Value -> List Scala.ArgValue
transformToArgsValue valueList =
    List.map (\x -> Scala.ArgValue Nothing x ) valueList

typeRefForSnowparkType : String -> Scala.Type
typeRefForSnowparkType typeName =
    (Scala.TypeRef snowflakeNamespace typeName)

typeRefForSnowparkTypesType : String -> Scala.Type
typeRefForSnowparkTypesType typeName =
    (Scala.TypeRef typesNamespace typeName)

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

type alias MapValueType ta = ValueIR.Value ta (TypeIR.Type ()) -> ValueMappingContext -> Scala.Value

type alias VariableInformation = (List Scala.Value, List (String, Scala.Value))

type alias MappingFunc ta = (MapValueType ta,  ValueMappingContext)

type alias MappingFuntions ta = 
    { mapValue : MapValueType ta
    , ctx : ValueMappingContext
    }

type alias AliasVariableInfo = 
    { aliasName: List Scala.Value
    , variables: VariableInformation
    }

type alias LambdaInfo ta = 
    { lambdaPattern: Pattern (TypeIR.Type())
    , lambdaBody: Value ta (TypeIR.Type ())
    , groupByName: Name.Name
    , firstParameter: Name.Name
    }