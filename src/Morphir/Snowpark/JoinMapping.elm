module Morphir.Snowpark.JoinMapping exposing (processJoinProjection, processJoinBody)

import Dict
import Morphir.Scala.AST as Scala
import Morphir.IR.Value as ValueIR exposing (TypedValue)
import Morphir.Snowpark.Constants as Constants exposing (ValueGenerationResult)
import Morphir.IR.Name as Name
import Morphir.Snowpark.MappingContext exposing (ValueMappingContext)
import Morphir.Snowpark.GenerationReport exposing (GenerationIssue)
import Morphir.Snowpark.ReferenceUtils exposing (errorValueAndIssue)

processJoinProjection : TypedValue -> Constants.MapValueType -> ValueMappingContext -> (List Scala.Value, List GenerationIssue)
processJoinProjection projection mapValue ctx =
    case projection of
        ValueIR.Lambda _ _ (ValueIR.Record _ record) ->
            let
                listFields = Dict.toList record
                (variablesExpr, varIssues) =  
                        listFields 
                            |> List.map (\(_, x) -> mapValue x ctx) 
                            |> List.unzip
                variables =
                    variablesExpr
                        |> List.map (\x -> Scala.Select x "alias")
                alias = listFields |> List.map(\(x, _) ->  Scala.Literal (Scala.StringLit (Name.toCamelCase x)) )

                selectColumns = List.map2 (\name variable -> Scala.Apply variable [Scala.ArgValue Nothing name]) alias variables
            in
            (selectColumns, List.concat varIssues)
        _ ->
            ([Scala.Literal <| Scala.StringLit "Projection"], [])

processJoinBody :  (TypedValue) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
processJoinBody joinValue mapValue ctx =
    case joinValue of
        ValueIR.Apply _ 
            (ValueIR.Apply 
                _ 
                (ValueIR.Apply _ ( ValueIR.Reference _  ([["morphir"],["s","d","k"]],[["list"]], joinName)) (ValueIR.Variable _ arg2))
                -- _
                (ValueIR.Lambda 
                    _ 
                    (ValueIR.AsPattern _ _ lambdaArg1Name)
                    (ValueIR.Lambda
                        _
                        (ValueIR.AsPattern _ _ lambdaArg2Name)
                        lambdaBody
                    )
                )
            ) 
            (ValueIR.Variable _ arg1) ->
                let
                    (lambdaBodyScala, bodyIssues) = 
                        processJoinFunctionBody lambdaBody mapValue ctx
                    joinTypeName = getJoinType joinName
                in
                (Scala.Apply 
                    (Scala.Select (Scala.Variable (Name.toCamelCase arg1)) "join")
                    [ Scala.ArgValue Nothing (Scala.Variable (Name.toCamelCase arg2))
                    , Scala.ArgValue Nothing lambdaBodyScala
                    , Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit joinTypeName))
                    ]
                , bodyIssues)
        _ ->
            errorValueAndIssue "'Join' scenario not supported"

processJoinFunctionBody : TypedValue -> Constants.MapValueType -> ValueMappingContext  -> ValueGenerationResult
processJoinFunctionBody value mapValue ctx =
    case value of
        ValueIR.Apply _ x y ->
            mapValue value ctx
        _ ->
            errorValueAndIssue "Join Body EXCEPTION"


getJoinVariable : TypedValue -> Scala.Value
getJoinVariable value =
    case value of
        ValueIR.Field tpe val name ->
            Scala.Literal (Scala.StringLit (Name.toCamelCase name))
        _ ->
            Scala.Literal (Scala.StringLit "")


getJoinType : Name.Name -> String
getJoinType name =
    if List.member "inner" name then
        "inner"
    else if List.member "inner" name then
            "right"
    else if List.member "inner" name then
            "left"
    else
        "Unsupported join Type"
