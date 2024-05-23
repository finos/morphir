module Morphir.Snowpark.AggregateMapping exposing (processAggregateLambdaBody)

import Dict
import Morphir.IR.Name as Name
import Morphir.IR.Type as TypeIR
import Morphir.IR.Value as ValueIR exposing (TypedValue)
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.Constants as Constants
import Morphir.Snowpark.MappingContext exposing (ValueMappingContext, getFieldInfoIfRecordType)
import Morphir.Snowpark.Operatorsmaps as Operatorsmaps


processAggregateLambdaBody : Constants.LambdaInfo () -> Constants.MappingFunc -> { columnNameList : List Scala.Value, variable : List Scala.ArgValue }
processAggregateLambdaBody lambdaInfo ( mapValue, ctx ) =
    case lambdaInfo.lambdaBody of
        ValueIR.Record fieldListType _ ->
            case lambdaInfo.lambdaPattern of
                ValueIR.AsPattern functionToApply _ functionName ->
                    let
                        recordFieldsName =
                            getFieldInfoIfRecordType fieldListType ctx.typesContextInfo |> Maybe.map (List.map Tuple.first) |> aliasMap
                    in
                    { columnNameList = recordFieldsName
                    , variable = processRecords lambdaInfo functionToApply functionName ( mapValue, ctx ) recordFieldsName
                    }

                _ ->
                    { columnNameList = []
                    , variable = [ Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit "To Do - Processing Record")) ]
                    }

        ValueIR.Apply _ x ((ValueIR.Apply _ _ (ValueIR.Apply _ (ValueIR.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "aggregate" ] ], _ )) (ValueIR.FieldFunction _ _))) as y) ->
            variablesFromAggregate (ValueIR.uncurryApply x y) ( mapValue, ctx )
                |> (\variableInfo -> { columnNameList = variableInfo.aliasName, variable = concatFunctions variableInfo.variables })

        _ ->
            { columnNameList = []
            , variable = [ Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit "To Do - Processing Other")) ]
            }


processRecords : Constants.LambdaInfo () -> TypeIR.Type () -> Name.Name -> Constants.MappingFunc -> List Scala.Value -> List Scala.ArgValue
processRecords lambdaInfo functionToApply functionName mappingFunc columnNameList =
    case lambdaInfo.lambdaBody of
        ValueIR.Record _ dictVariables ->
            let
                variablesInfo =
                    Dict.toList dictVariables
                        |> List.map (processRecordsVariables lambdaInfo mappingFunc functionToApply functionName)

                variables =
                    List.map2 processColumnList variablesInfo columnNameList
            in
            variables |> List.filterMap (\x -> x) |> List.map generateFunctionFromColumnRecords

        _ ->
            [ Scala.ArgValue Nothing (defaultValueForUnsupportedElement "Unsupported Record") ]


generateFunctionFromColumnRecords : ( String, Scala.Value, Scala.Value ) -> Scala.ArgValue
generateFunctionFromColumnRecords ( funcName, columnName, aliasValue ) =
    if String.contains "Unsupported" funcName then
        Scala.ArgValue Nothing <| defaultValueForUnsupportedElement "Unsupported column"

    else
        Constants.applySnowparkFunc funcName [ columnName ] |> joinWithAlias aliasValue


processColumnList : Maybe ( String, Scala.Value, Name.Name ) -> Scala.Value -> Maybe ( String, Scala.Value, Scala.Value )
processColumnList variable aliasName =
    case variable of
        Just ( funcName, value, _ ) ->
            Just ( funcName, value, aliasName )

        _ ->
            Nothing


processRecordsVariables : Constants.LambdaInfo ta -> Constants.MappingFunc -> TypeIR.Type () -> Name.Name -> ( Name.Name, TypedValue ) -> Maybe ( String, Scala.Value, Name.Name )
processRecordsVariables lambdaInfo ( mapValue, ctx ) functionFromLambda functionFromLamnbdaName ( key, value ) =
    case value of
        ValueIR.Apply _ (ValueIR.Variable functionType functionName) variableToProcess ->
            if functionType == functionFromLambda && functionFromLamnbdaName == functionName then
                getFunctionVariable variableToProcess ( mapValue, ctx ) lambdaInfo

            else
                Just ( "Unsupported case", Scala.Literal (Scala.StringLit (Name.toCamelCase key)), [] )

        ValueIR.Variable _ name ->
            if name == lambdaInfo.firstParameter then
                if key /= lambdaInfo.groupByName then
                    Just ( "col", Scala.Literal (Scala.StringLit (Name.toCamelCase lambdaInfo.groupByName)), key )

                else
                    Nothing

            else
                Just <| ( "Unsupported variable", Scala.Literal (Scala.StringLit ("UnSupported variable for " ++ Name.toCamelCase name)), [ "Unsupported" ] )

        _ ->
            Just <| ( "Unsupported field", defaultValueForUnsupportedElement "Unsupported field from Record", [ "Unsupported field" ] )


getFunctionVariable : TypedValue -> Constants.MappingFunc -> Constants.LambdaInfo ta -> Maybe ( String, Scala.Value, Name.Name )
getFunctionVariable variableInfo mappingFunc lambdaInfo =
    case variableInfo of
        ValueIR.Apply _ _ _ ->
            getVariable variableInfo mappingFunc

        ValueIR.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "aggregate" ] ], [ "count" ] ) ->
            Just ( "count", Constants.applySnowparkFunc "col" [ Scala.Literal (Scala.StringLit (Name.toCamelCase lambdaInfo.groupByName)) ], [ "count" ] )

        _ ->
            Just ( "Unsupported", defaultValueForUnsupportedElement "Unsupported Reference", [] )


concatFunctions : Constants.VariableInformation -> List Scala.ArgValue
concatFunctions ( aliasList, functions ) =
    functions
        |> List.map processList
        |> List.map2 joinWithAlias (List.tail aliasList |> Maybe.withDefault [])


processList : ( String, Scala.Value ) -> Scala.Value
processList ( funcName, columnName ) =
    Constants.applySnowparkFunc funcName [ columnName ]


variablesFromAggregate : ( TypedValue, List TypedValue ) -> Constants.MappingFunc -> Constants.AliasVariableInfo
variablesFromAggregate body ( mapValue, ctx ) =
    case body of
        ( ValueIR.Constructor tpe _, array ) ->
            let
                aliasApplies =
                    aliasMap <| getFieldsFromType tpe ctx

                variablesFromApply =
                    array
                        |> List.map (getVariablesFromApply ( mapValue, ctx ))
                        |> List.filterMap (\x -> x)
            in
            joinAliasInfo aliasApplies variablesFromApply |> (\x -> { aliasName = aliasApplies, variables = x })

        _ ->
            { aliasName = []
            , variables = ( [], [ ( "Error", Scala.Literal (Scala.StringLit "To Do - Not Support in variablesFromApply") ) ] )
            }


joinAliasInfo : a -> b -> ( a, b )
joinAliasInfo aliasList variableList =
    ( aliasList, variableList )


getFieldsFromType : TypeIR.Type () -> ValueMappingContext -> Maybe (List Name.Name)
getFieldsFromType tpe ctx =
    case tpe of
        TypeIR.Function _ _ ftpe ->
            getFieldsFromType ftpe ctx

        _ ->
            getFieldInfoIfRecordType tpe ctx.typesContextInfo
                |> Maybe.map (List.map Tuple.first)


aliasMap : Maybe (List Name.Name) -> List Scala.Value
aliasMap fields =
    case fields of
        Just list ->
            list
                |> List.map convertNameToApply

        Nothing ->
            []


convertNameToApply : Name.Name -> Scala.Value
convertNameToApply name =
    Scala.Literal (Scala.StringLit (Name.toCamelCase name))


joinWithAlias : Scala.Value -> Scala.Value -> Scala.ArgValue
joinWithAlias aliasApply columnsApply =
    let
        columnAlias =
            Scala.Select columnsApply "alias"
    in
    Scala.ArgValue Nothing (Scala.Apply columnAlias [ Scala.ArgValue Nothing aliasApply ])


getVariablesFromApply : Constants.MappingFunc -> TypedValue -> Maybe ( String, Scala.Value )
getVariablesFromApply mappingFunc value =
    case value of
        ValueIR.Apply _ _ property ->
            let
                info =
                    getVariable property mappingFunc
            in
            case info of
                Just ( funcName, scalaValue, _ ) ->
                    Just ( funcName, scalaValue )

                _ ->
                    Nothing

        _ ->
            Nothing


getVariable : TypedValue -> Constants.MappingFunc -> Maybe ( String, Scala.Value, Name.Name )
getVariable value ( mapValue, ctx ) =
    case value of
        ValueIR.Apply _ (ValueIR.Reference _ ( _, _, name )) property ->
            let
                func =
                    Operatorsmaps.mapOperator name

                ( column, _ ) =
                    mapValue property ctx

                columnName =
                    getColumnName property
            in
            Just ( func, column, columnName )

        _ ->
            Just ( "Unsupported", defaultValueForUnsupportedElement "Unsupported Reference", [] )


defaultValueForUnsupportedElement : String -> Scala.Value
defaultValueForUnsupportedElement description =
    Scala.Throw (Scala.New [] "Exception" [ Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit description)) ])


getColumnName : TypedValue -> Name.Name
getColumnName property =
    case property of
        ValueIR.FieldFunction _ name ->
            name

        _ ->
            []
