module Morphir.Snowpark.AggregateMapping exposing (processAggregateLambdaBody)

import Morphir.IR.Name as Name
import Morphir.IR.Type as TypeIR
import Morphir.IR.Value as ValueIR
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.Constants as Constants
import Morphir.Snowpark.MappingContext exposing (ValueMappingContext, getFieldsNamesIfRecordType)
import Morphir.Snowpark.Operatorsmaps as Operatorsmaps


processAggregateLambdaBody : ValueIR.Value ta (TypeIR.Type ()) -> Constants.MapValueType ta -> ValueMappingContext ->  List Scala.ArgValue
processAggregateLambdaBody body mapValue ctx =
    case body of
        ValueIR.Record _ _ ->
            [Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit "To Do - Processing Record"))]
        ValueIR.Apply _ x
            ((ValueIR.Apply _ _
                (ValueIR.Apply _
                    ( ValueIR.Reference _ ([["morphir"],["s","d","k"]],[["aggregate"]], _ ) )
                    ( ValueIR.FieldFunction _ _ )
                )
            ) as y) ->
            variablesFromAggregate (ValueIR.uncurryApply x y) mapValue ctx 
                |>  concatFunctions
        _ ->
            [Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit "To Do - Processing Other"))]

concatFunctions : Constants.VariableInformation -> List Scala.ArgValue
concatFunctions (aliasList, functions) =
    functions 
        |> List.map processList
            |> List.map2 joinWithAlias (List.tail aliasList |> Maybe.withDefault [])

processList : (String, Scala.Value) -> Scala.Value
processList (funcName, columnName) =
    Constants.applySnowparkFunc funcName [columnName]

variablesFromAggregate : (ValueIR.Value ta (TypeIR.Type ()),List (ValueIR.Value ta (TypeIR.Type ()))) -> Constants.MapValueType ta -> ValueMappingContext -> Constants.VariableInformation
variablesFromAggregate body mapValue ctx =
    case body of
        (ValueIR.Constructor tpe _, array) ->
            let
                aliasApplies = aliasMap <| getFieldsFromType tpe ctx
            in
            joinAliasInfo aliasApplies <| (array 
            |> List.map (getVariablesFromApply mapValue ctx)
                |> List.filterMap (\x -> x ))
        _ ->
            ( [], [("Error", Scala.Literal (Scala.StringLit "To Do - Not Support in variablesFromApply"))])

joinAliasInfo : a -> b -> ( a, b )
joinAliasInfo aliasList variableList =
    (aliasList, variableList)

getFieldsFromType : TypeIR.Type () -> ValueMappingContext -> Maybe (List Name.Name)
getFieldsFromType tpe ctx =
    case tpe of
        TypeIR.Function _ _ ftpe ->
            getFieldsFromType ftpe ctx
        _ ->
            getFieldsNamesIfRecordType tpe ctx.typesContextInfo

aliasMap : Maybe (List (Name.Name)) -> List Scala.Value
aliasMap fields =
    case fields of
        Just list ->
            list |>
                List.map convertNameToApply
        Nothing ->
            []

convertNameToApply : Name.Name -> Scala.Value
convertNameToApply name =
    Scala.Literal (Scala.StringLit (Name.toCamelCase name))


joinWithAlias : Scala.Value -> Scala.Value -> Scala.ArgValue
joinWithAlias aliasApply columnsApply =
    let
        columnAlias = Scala.Select columnsApply "alias"
    in
    Scala.ArgValue Nothing (Scala.Apply columnAlias [Scala.ArgValue Nothing aliasApply])

getVariablesFromApply : Constants.MapValueType ta -> ValueMappingContext -> ValueIR.Value ta (TypeIR.Type ()) -> Maybe (String, Scala.Value)
getVariablesFromApply mapValue ctx value =
    case value of
        ValueIR.Apply _ _ 
            (ValueIR.Apply _ (ValueIR.Reference _ ( _, _, name )) property) ->
            let
                func = Operatorsmaps.mapOperator name
                column = mapValue property ctx
            in
            Just (func, column)
        _ ->
            Nothing