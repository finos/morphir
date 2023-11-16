module Morphir.Snowpark.UserDefinedFunctionMapping exposing (tryToConvertUserFunctionCall)

import Morphir.Scala.AST as Scala
import Morphir.IR.Value as ValueIR exposing (Pattern(..), Value(..))
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Name as Name
import Morphir.IR.FQName as FQName
import Morphir.Snowpark.Constants as Constants exposing (applySnowparkFunc)
import Morphir.Snowpark.ReferenceUtils exposing ( scalaPathToModule, getCustomTypeParameterFieldAccess)
import Morphir.Snowpark.MappingContext exposing (
            ValueMappingContext
            , FunctionClassification(..)
            , isBasicType
            , isAliasedBasicType
            , isLocalFunctionName )
import Morphir.Snowpark.MappingContext exposing (isRecordWithSimpleTypes)
import Morphir.Snowpark.MappingContext exposing (isLocalVariableDefinition)
import Morphir.Snowpark.MappingContext exposing (isFunctionReceivingDataFrameExpressions)
import Morphir.Snowpark.ReferenceUtils exposing (getFunctionInputTypes)

tryToConvertUserFunctionCall : ((Value a (Type ())), List (Value a (Type ()))) -> Constants.MapValueType a -> ValueMappingContext -> Scala.Value
tryToConvertUserFunctionCall (func, args) mapValue ctx =
   case func of
       ValueIR.Reference functionType functionName -> 
            if isLocalFunctionName functionName ctx then
                let 
                    funcReference = 
                        Scala.Ref (scalaPathToModule functionName) 
                                  (functionName |> FQName.getLocalName |> Name.toCamelCase)
                    argsConverted =
                        args 
                            |> List.map (\arg -> mapValue arg ctx)
                    argsToUse =
                        checkIfArgumentsNeedsToBeAdapted functionName functionType argsConverted ctx
                            |> List.map (Scala.ArgValue Nothing)
                in
                case argsToUse of
                    [] -> 
                        funcReference
                    (first::rest) -> 
                        List.foldl (\a c -> Scala.Apply c [a]) (Scala.Apply funcReference [first]) rest
            else
                Scala.Literal (Scala.StringLit "Call not converted")
       ValueIR.Constructor _ constructorName ->
            if isRecordWithSimpleTypes constructorName ctx.typesContextInfo then
                let 
                    argsToUse = 
                        args |> List.map (\ arg -> mapValue arg ctx)
                in
                Constants.applySnowparkFunc "array_construct" argsToUse
            else 
                if isLocalFunctionName constructorName ctx && List.length args > 0 then
                    let
                        argsToUse =
                            args 
                                |> List.indexedMap (\i arg -> (getCustomTypeParameterFieldAccess i, mapValue arg ctx))
                                |> List.concatMap (\(field, value) -> [Constants.applySnowparkFunc "lit" [Scala.Literal (Scala.StringLit field)], value])
                        tag = [ Constants.applySnowparkFunc "lit" [Scala.Literal (Scala.StringLit "__tag")],
                                Constants.applySnowparkFunc "lit" [ Scala.Literal (Scala.StringLit <| ( constructorName |> FQName.getLocalName |> Name.toTitleCase))]]
                    in Constants.applySnowparkFunc "object_construct" (tag ++ argsToUse)
                else
                    Scala.Literal (Scala.StringLit "Constructor call not converted")
       ValueIR.Variable _ funcName ->
            if List.member funcName ctx.parameters ||
               isLocalVariableDefinition funcName ctx then
                let
                    argsToUse =
                        args 
                            |> List.map (\arg -> mapValue arg ctx)
                            |> List.map (Scala.ArgValue Nothing)
                in
                case argsToUse of
                    [] -> 
                        Scala.Variable (Name.toCamelCase funcName)
                    (first::rest) -> 
                        List.foldl (\a c -> Scala.Apply c [a]) (Scala.Apply (Scala.Variable (Name.toCamelCase funcName)) [first]) rest               
            else
                Scala.Literal (Scala.StringLit "Call to variable function not converted")
       _ -> 
            Scala.Literal (Scala.StringLit "Call not converted")

checkIfArgumentsNeedsToBeAdapted : FQName.FQName -> 
                                    Type () ->
                                    List Scala.Value ->
                                   ValueMappingContext -> 
                                   List Scala.Value
checkIfArgumentsNeedsToBeAdapted invokedFunctionName functionType args ctx =
    let
        inPlainScalaFunction = 
            ctx.currentFunctionClassification == FromComplexValuesToDataFrames || 
            ctx.currentFunctionClassification == FromComplexToValues
    in
    if inPlainScalaFunction && 
       (isFunctionReceivingDataFrameExpressions invokedFunctionName ctx) then
        getFunctionInputTypes functionType
            |> Maybe.map (\inputTypes -> List.map2 (adaptArgumentToDfExpr ctx) args inputTypes  )
            |> Maybe.withDefault args
    else 
        args

adaptArgumentToDfExpr : ValueMappingContext -> Scala.Value -> Type () ->  Scala.Value
adaptArgumentToDfExpr ctx arg targetArgType =
    if isBasicType targetArgType || (isAliasedBasicType targetArgType ctx.typesContextInfo) then
        applySnowparkFunc "lit" [ arg ]
     else
        arg
