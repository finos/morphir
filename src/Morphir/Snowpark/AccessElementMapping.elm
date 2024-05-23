module Morphir.Snowpark.AccessElementMapping exposing
    ( mapConstructorAccess
    , mapFieldAccess
    , mapReferenceAccess
    , mapVariableAccess
    )

{-| This module contains functions to generate code like `a.b` or `a`.
|
-}

import Dict
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name
import Morphir.IR.Type as IrType
import Morphir.IR.Value as Value exposing (TypedValue, Value(..))
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.Constants exposing (MapValueType, ValueGenerationResult, applySnowparkFunc)
import Morphir.Snowpark.MappingContext
    exposing
        ( ValueMappingContext
        , getReplacementForIdentifier
        , isAnonymousRecordWithSimpleTypes
        , isDataFrameFriendlyType
        , isListOfDataFrameFriendlyType
        , isLocalFunctionName
        , isUnionTypeWithParams
        , isUnionTypeWithoutParams
        )
import Morphir.Snowpark.ReferenceUtils
    exposing
        ( errorValueAndIssue
        , isValueReferenceToSimpleTypesRecord
        , scalaPathToModule
        , scalaReferenceToUnionTypeCase
        )


checkForDataFrameVariableReference : Value ta (IrType.Type ()) -> ValueMappingContext -> Maybe String
checkForDataFrameVariableReference value ctx =
    case Value.valueAttribute value of
        IrType.Reference _ typeName _ ->
            Dict.get typeName ctx.dataFrameColumnsObjects

        _ ->
            Nothing


mapFieldAccess : va -> TypedValue -> Name.Name -> ValueMappingContext -> MapValueType -> ValueGenerationResult
mapFieldAccess _ value name ctx mapValue =
    let
        simpleFieldName =
            name |> Name.toCamelCase

        valueIsFunctionParameter =
            case value of
                Value.Variable _ varName ->
                    if List.member varName ctx.parameters then
                        Just <| Name.toCamelCase varName

                    else
                        Nothing

                _ ->
                    Nothing

        valueIsDataFrameColumnAccess =
            case ( value, checkForDataFrameVariableReference value ctx ) of
                ( Value.Variable _ _, Just replacement ) ->
                    Just replacement

                _ ->
                    Nothing
    in
    case ( isValueReferenceToSimpleTypesRecord value ctx.typesContextInfo, valueIsFunctionParameter, valueIsDataFrameColumnAccess ) of
        ( _, Just replacement, _ ) ->
            ( Scala.Ref [ replacement ] simpleFieldName, [] )

        ( _, _, Just replacement ) ->
            ( Scala.Ref [ replacement ] simpleFieldName, [] )

        ( Just ( path, refererName ), Nothing, Nothing ) ->
            ( Scala.Ref (path ++ [ refererName |> Name.toTitleCase ]) simpleFieldName, [] )

        _ ->
            if isAnonymousRecordWithSimpleTypes (value |> Value.valueAttribute) ctx.typesContextInfo then
                ( applySnowparkFunc "col" [ Scala.Literal (Scala.StringLit (Name.toCamelCase name)) ], [] )

            else
                let
                    ( mappedValue, issues ) =
                        mapValue value ctx
                in
                ( Scala.Select mappedValue (Name.toCamelCase name), issues )


mapVariableAccess : Name.Name -> TypedValue -> ValueMappingContext -> ValueGenerationResult
mapVariableAccess name nameAccess ctx =
    case ( getReplacementForIdentifier name ctx, checkForDataFrameVariableReference nameAccess ctx ) of
        ( Just replacement, _ ) ->
            ( replacement, [] )

        ( _, Just replacementStr ) ->
            ( Scala.Variable replacementStr, [] )

        _ ->
            ( Scala.Variable (name |> Name.toCamelCase), [] )


mapConstructorAccess : IrType.Type a -> FQName.FQName -> ValueMappingContext -> ValueGenerationResult
mapConstructorAccess tpe name ctx =
    case ( tpe, name ) of
        ( IrType.Reference _ _ _, ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ) ) ->
            ( applySnowparkFunc "lit" [ Scala.Literal Scala.NullLit ], [] )

        ( IrType.Reference _ typeName _, _ ) ->
            if isUnionTypeWithoutParams typeName ctx.typesContextInfo then
                ( scalaReferenceToUnionTypeCase typeName name, [] )

            else if isUnionTypeWithParams typeName ctx.typesContextInfo then
                ( applySnowparkFunc "object_construct"
                    [ applySnowparkFunc "lit" [ Scala.Literal <| Scala.StringLit "__tag" ]
                    , applySnowparkFunc "lit" [ Scala.Literal <| Scala.StringLit (name |> FQName.getLocalName |> Name.toTitleCase) ]
                    ]
                , []
                )

            else
                errorValueAndIssue <| "Constructor access not converted" ++ FQName.toString name

        _ ->
            errorValueAndIssue <| "Constructor access not converted" ++ FQName.toString name


mapReferenceAccess : IrType.Type () -> FQName.FQName -> MapValueType -> ValueMappingContext -> ValueGenerationResult
mapReferenceAccess tpe name mapValue ctx =
    if Dict.member name ctx.globalValuesToInline then
        let
            inlinedResult =
                ctx.globalValuesToInline
                    |> Dict.get name
                    |> Maybe.map (\definition -> mapValue definition.body ctx)
                    |> Maybe.withDefault ( Scala.Wildcard, [] )
        in
        inlinedResult

    else if
        isDataFrameFriendlyType tpe ctx.typesContextInfo
            || isListOfDataFrameFriendlyType tpe ctx.typesContextInfo
    then
        let
            nsName =
                scalaPathToModule name

            containerObjectFieldName =
                FQName.getLocalName name |> Name.toCamelCase
        in
        ( Scala.Ref nsName containerObjectFieldName, [] )

    else
        case tpe of
            IrType.Function _ _ _ ->
                if isLocalFunctionName name ctx then
                    ( Scala.Ref (scalaPathToModule name) (name |> FQName.getLocalName |> Name.toCamelCase), [] )

                else
                    errorValueAndIssue ("Reference access to function not converted" ++ FQName.toString name)

            _ ->
                errorValueAndIssue ("Reference access not converted: " ++ FQName.toString name)
