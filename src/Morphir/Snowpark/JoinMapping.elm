module Morphir.Snowpark.JoinMapping exposing (processJoinBody, processJoinProjection)

import Dict
import Morphir.IR.Name as Name
import Morphir.IR.Type as TypeIR
import Morphir.IR.Value as ValueIR exposing (TypedValue)
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.Constants as Constants exposing (ValueGenerationResult)
import Morphir.Snowpark.GenerationReport exposing (GenerationIssue)
import Morphir.Snowpark.MappingContext exposing (ValueMappingContext)
import Morphir.Snowpark.ReferenceUtils exposing (errorValueAndIssue)


processJoinProjection : TypedValue -> Constants.MapValueType -> ValueMappingContext -> ( List Scala.Value, List GenerationIssue )
processJoinProjection projection mapValue ctx =
    case projection of
        ValueIR.Lambda _ _ (ValueIR.Record _ record) ->
            let
                listFields =
                    Dict.toList record

                ( variablesExpr, varIssues ) =
                    listFields
                        |> List.map transformMaybeValueToField
                        |> List.map (\( _, x ) -> mapValue x ctx)
                        |> List.unzip

                variables =
                    variablesExpr
                        |> List.map (\x -> Scala.Select x "alias")

                alias =
                    listFields |> List.map (\( x, _ ) -> Scala.Literal (Scala.StringLit (Name.toCamelCase x)))

                selectColumns =
                    List.map2 (\name variable -> Scala.Apply variable [ Scala.ArgValue Nothing name ]) alias variables
            in
            ( selectColumns, List.concat varIssues )

        _ ->
            ( [ Scala.Literal <| Scala.StringLit "Projection" ], [] )


transformMaybeValueToField : ( Name.Name, ValueIR.Value () (TypeIR.Type ()) ) -> ( Name.Name, ValueIR.Value () (TypeIR.Type ()) )
transformMaybeValueToField ( name, value ) =
    case value of
        ValueIR.Apply (TypeIR.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "maybe" ] ) [ returnType ]) (ValueIR.Apply _ _ (ValueIR.Lambda _ _ (ValueIR.Field _ _ accessField))) (ValueIR.Variable (TypeIR.Reference _ _ [ variableRef ]) variableField) ->
            let
                variable =
                    ValueIR.Variable variableRef variableField

                field =
                    ValueIR.Field returnType variable accessField
            in
            ( name, field )

        _ ->
            ( name, value )


processJoinsLambda : TypedValue -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
processJoinsLambda lambdaValue mapValue ctx =
    case lambdaValue of
        ValueIR.Lambda _ (ValueIR.AsPattern _ _ _) (ValueIR.Lambda _ (ValueIR.AsPattern _ _ _) lambdaBody) ->
            processJoinFunctionBody lambdaBody mapValue ctx

        ValueIR.Lambda _ _ (ValueIR.Lambda _ _ lambdaBody) ->
            processJoinFunctionBody lambdaBody mapValue ctx

        _ ->
            errorValueAndIssue "`Join` scenario not supported"


processInternalJoin : TypedValue -> Constants.MapValueType -> ValueMappingContext -> ( List Scala.ArgValue, List GenerationIssue )
processInternalJoin value mapValue ctx =
    case value of
        ValueIR.Apply _ (ValueIR.Apply _ (ValueIR.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], joinName )) (ValueIR.Variable _ arg2)) ((ValueIR.Lambda _ _ _) as lambdaSection) ->
            let
                ( lambdaBodyScala, bodyIssues ) =
                    processJoinsLambda lambdaSection mapValue ctx

                joinTypeName =
                    getJoinType joinName
            in
            ( [ Scala.ArgValue Nothing (Scala.Variable (Name.toCamelCase arg2))
              , Scala.ArgValue Nothing lambdaBodyScala
              , Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit joinTypeName))
              ]
            , bodyIssues
            )

        _ ->
            ( [ Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit "Unsupported Join")) ], [] )


processJoinBody : TypedValue -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
processJoinBody joinValue mapValue ctx =
    case joinValue of
        ValueIR.Apply _ (ValueIR.Apply _ (ValueIR.Apply _ (ValueIR.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], joinName )) (ValueIR.Variable _ arg2)) ((ValueIR.Lambda _ _ _) as lambdaSection)) (ValueIR.Variable _ arg1) ->
            let
                ( lambdaBodyScala, bodyIssues ) =
                    processJoinsLambda lambdaSection mapValue ctx

                joinTypeName =
                    getJoinType joinName
            in
            ( Scala.Apply
                (Scala.Select (Scala.Variable (Name.toCamelCase arg1)) "join")
                [ Scala.ArgValue Nothing (Scala.Variable (Name.toCamelCase arg2))
                , Scala.ArgValue Nothing lambdaBodyScala
                , Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit joinTypeName))
                ]
            , bodyIssues
            )

        ValueIR.Apply _ ((ValueIR.Apply _ _ _) as internalJoin) ((ValueIR.Apply _ (ValueIR.Apply _ (ValueIR.Apply _ (ValueIR.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], joinName )) (ValueIR.Variable _ arg2)) _) _) as firstJoin) ->
            if List.member "join" joinName then
                let
                    ( firstJoinResult, firstErrors ) =
                        processJoinBody firstJoin mapValue ctx

                    ( secondJoinResult, secondErrors ) =
                        processInternalJoin internalJoin mapValue ctx

                    preresult =
                        Scala.Select firstJoinResult "join"

                    result =
                        Scala.Apply preresult secondJoinResult
                in
                ( result
                , List.append firstErrors secondErrors
                )

            else
                errorValueAndIssue "'Join' scenario not supported"

        _ ->
            errorValueAndIssue "'Join' scenario not supported"


processJoinFunctionBody : TypedValue -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
processJoinFunctionBody value mapValue ctx =
    case value of
        ValueIR.Apply _ x y ->
            mapValue value ctx

        _ ->
            errorValueAndIssue "Join Body EXCEPTION"


getJoinType : Name.Name -> String
getJoinType name =
    if List.member "inner" name then
        "inner"

    else if List.member "right" name then
        "right"

    else if List.member "left" name then
        "left"

    else
        "Unsupported join Type"
