module Morphir.Snowpark.TypeRefMapping exposing
    ( generateCastIfPossible
    , generateRecordTypeWrapperExpression
    , generateSnowparkTypeExprFromElmType
    , mapFunctionReturnType
    , mapTypeReference
    )

import Morphir.IR.FQName as FQName
import Morphir.IR.Name as Name
import Morphir.IR.Type as Type exposing (Type(..))
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.Constants
    exposing
        ( applyForSnowparkTypesType
        , applyForSnowparkTypesTypeExpr
        , applySnowparkFunc
        , typeRefForSnowparkType
        )
import Morphir.Snowpark.MappingContext as MappingContextMod
    exposing
        ( FunctionClassification
        , MappingContextInfo
        , ValueMappingContext
        , getLocalVariableIfDataFrameReference
        , isAliasedBasicType
        , isBasicType
        , isCandidateForDataFrame
        , isDataFrameFriendlyType
        , isTypeAlias
        , isTypeRefToRecordWithComplexTypes
        , isUnionTypeWithParams
        , isUnionTypeWithoutParams
        , resolveTypeAlias
        )
import Morphir.Snowpark.ReferenceUtils exposing (isTypeReferenceToSimpleTypesRecord, scalaPathToModule)
import Morphir.Snowpark.Utils exposing (tryAlternatives)


checkDataFrameCase : Type () -> MappingContextInfo () -> Maybe Scala.Type
checkDataFrameCase typeReference ctx =
    if isCandidateForDataFrame typeReference ctx then
        Just <| typeRefForSnowparkType "DataFrame"

    else
        Nothing


checkComplexRecordCase : Type () -> MappingContextInfo () -> Maybe Scala.Type
checkComplexRecordCase typeReference ctx =
    if isTypeRefToRecordWithComplexTypes typeReference ctx then
        case typeReference of
            Type.Reference _ fullName [] ->
                Just <| Scala.TypeRef (scalaPathToModule fullName) (fullName |> FQName.getLocalName |> Name.toTitleCase)

            _ ->
                Nothing

    else
        Nothing


checkDataFrameCaseToArray : Type () -> MappingContextInfo () -> Maybe Scala.Type
checkDataFrameCaseToArray typeReference ctx =
    if isCandidateForDataFrame typeReference ctx then
        Just <| typeRefForSnowparkType "Column"

    else
        Nothing


checkForFunctionTypeCase : Type () -> MappingContextInfo () -> Maybe Scala.Type
checkForFunctionTypeCase typeReference ctx =
    case typeReference of
        Type.Function _ fromType toType ->
            let
                convertedFrom =
                    mapTypeReferenceForDataFrameOperations fromType ctx

                convertedTo =
                    mapTypeReferenceForDataFrameOperations toType ctx
            in
            Just <| Scala.FunctionType convertedFrom convertedTo

        _ ->
            Nothing


checkForColumnCase : Type () -> MappingContextInfo () -> Maybe Scala.Type
checkForColumnCase typeReference ctx =
    if
        isBasicType typeReference
            || isAliasedBasicType typeReference ctx
            || isDataFrameFriendlyType typeReference ctx
            || isTypeVariable typeReference
            || isMaybeWithGenericType typeReference
    then
        Just <| typeRefForSnowparkType "Column"

    else
        Nothing


checkForRecordToColumnCase : Type () -> MappingContextInfo () -> Maybe Scala.Type
checkForRecordToColumnCase typeReference ctx =
    isTypeReferenceToSimpleTypesRecord typeReference ctx
        |> Maybe.map (\_ -> typeRefForSnowparkType "Column")


checkForBasicTypeToScala : Type () -> MappingContextInfo () -> Maybe Scala.Type
checkForBasicTypeToScala tpe ctx =
    case tpe of
        Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "int" ] ) _ ->
            Just <| Scala.TypeVar "Int"

        Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) _ ->
            Just <| Scala.TypeVar "Float"

        Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "double" ] ) _ ->
            Just <| Scala.TypeVar "Double"

        Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "bool" ] ) _ ->
            Just <| Scala.TypeVar "Boolean"

        Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "string" ] ], [ "string" ] ) _ ->
            Just <| Scala.TypeVar "String"

        Reference _ fullName [] ->
            resolveTypeAlias fullName ctx
                |> Maybe.map (\resolved -> checkForBasicTypeToScala resolved ctx)
                |> Maybe.withDefault Nothing

        _ ->
            Nothing


checkDefaultCase : Type () -> MappingContextInfo () -> Maybe Scala.Type
checkDefaultCase typeReference ctx =
    let
        nameInfo =
            isTypeReferenceToSimpleTypesRecord typeReference ctx

        typeNameInfo =
            Maybe.map
                (\( typePath, simpleTypeName ) -> Just (Scala.TypeRef typePath (simpleTypeName |> Name.toTitleCase)))
                nameInfo
    in
    typeNameInfo |> Maybe.withDefault Nothing


mapFunctionReturnType : Type () -> FunctionClassification -> MappingContextInfo () -> Scala.Type
mapFunctionReturnType typeReference currentFunctionClassification ctx =
    case currentFunctionClassification of
        MappingContextMod.FromDataFramesToValues ->
            mapTypeReferenceToBuiltinTypes typeReference ctx

        MappingContextMod.FromComplexToValues ->
            mapTypeReferenceToBuiltinTypes typeReference ctx

        _ ->
            checkForRecordToColumnCase typeReference ctx
                |> Maybe.withDefault (mapTypeReference typeReference currentFunctionClassification ctx)


mapTypeReference : Type () -> FunctionClassification -> MappingContextInfo () -> Scala.Type
mapTypeReference typeReference currentFunctionClassification ctx =
    case currentFunctionClassification of
        MappingContextMod.FromDfValuesToDfValues ->
            mapTypeReferenceForColumnOperations typeReference ctx

        MappingContextMod.FromComplexToValues ->
            mapToScalaTypes typeReference ctx

        MappingContextMod.FromComplexValuesToDataFrames ->
            mapToScalaTypes typeReference ctx

        _ ->
            mapTypeReferenceForDataFrameOperations typeReference ctx


mapToScalaTypes : Type () -> MappingContextInfo () -> Scala.Type
mapToScalaTypes typeReference ctx =
    tryAlternatives
        [ \_ -> checkDataFrameCase typeReference ctx
        , \_ -> checkForBasicTypeToScala typeReference ctx
        , \_ -> checkComplexRecordCase typeReference ctx
        , \_ -> checkUnionTypeForPlainScala typeReference ctx
        ]
        |> Maybe.withDefault (Scala.TypeVar "TypeNotConverted")


checkUnionTypeForPlainScala : Type () -> MappingContextInfo () -> Maybe Scala.Type
checkUnionTypeForPlainScala tpe ctx =
    case tpe of
        Type.Reference _ fullTypeName _ ->
            if isUnionTypeWithoutParams fullTypeName ctx then
                Just <| Scala.TypeVar "String"

            else
                Nothing

        _ ->
            Nothing


mapTypeReferenceForColumnOperations : Type () -> MappingContextInfo () -> Scala.Type
mapTypeReferenceForColumnOperations typeReference ctx =
    tryAlternatives
        [ \_ -> checkDataFrameCaseToArray typeReference ctx
        , \_ -> checkForColumnCase typeReference ctx
        , \_ -> checkDefaultCase typeReference ctx
        , \_ -> checkForListOfSimpleTypes typeReference ctx
        , \_ -> checkComplexRecordCase typeReference ctx
        ]
        |> Maybe.withDefault (Scala.TypeVar "TypeNotConverted")


mapTypeReferenceForDataFrameOperations : Type () -> MappingContextInfo () -> Scala.Type
mapTypeReferenceForDataFrameOperations typeReference ctx =
    tryAlternatives
        [ \_ -> checkDataFrameCase typeReference ctx
        , \_ -> checkForColumnCase typeReference ctx
        , \_ -> checkDefaultCase typeReference ctx
        , \_ -> checkForListOfSimpleTypes typeReference ctx
        , \_ -> checkComplexRecordCase typeReference ctx
        , \_ -> checkForFunctionTypeCase typeReference ctx
        ]
        |> Maybe.withDefault (Scala.TypeVar "TypeNotConverted")


generateRecordTypeWrapperExpression : Type () -> ValueMappingContext -> Maybe Scala.Value
generateRecordTypeWrapperExpression typeReference ctx =
    getLocalVariableIfDataFrameReference typeReference ctx
        |> Maybe.map Scala.Variable


isMaybeWithGenericType : Type () -> Bool
isMaybeWithGenericType tpe =
    case tpe of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "maybe" ] ) [ _ ] ->
            True

        _ ->
            False


isTypeVariable : Type () -> Bool
isTypeVariable tpe =
    case tpe of
        Type.Variable _ _ ->
            True

        _ ->
            False


checkForListOfSimpleTypes : Type () -> MappingContextInfo () -> Maybe Scala.Type
checkForListOfSimpleTypes typeReference ctx =
    if isListOfSimpleType typeReference ctx then
        Just <| Scala.TypeApply (Scala.TypeRef [] "Seq") [ typeRefForSnowparkType "Column" ]

    else
        Nothing


isListOfSimpleType : Type () -> MappingContextInfo () -> Bool
isListOfSimpleType tpe ctx =
    case tpe of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "list" ] ) [ elementType ] ->
            isDataFrameFriendlyType elementType ctx

        _ ->
            False


mapTypeReferenceToBuiltinTypes : Type () -> MappingContextInfo () -> Scala.Type
mapTypeReferenceToBuiltinTypes tpe ctx =
    case tpe of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] ->
            Scala.TypeVar "Double"

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "int" ] ) [] ->
            Scala.TypeVar "Int"

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "string" ] ], [ "string" ] ) [] ->
            Scala.TypeVar "String"

        Type.Reference _ fullTypeName [] ->
            if isTypeAlias fullTypeName ctx then
                resolveTypeAlias fullTypeName ctx
                    |> Maybe.map (\t -> mapTypeReferenceToBuiltinTypes t ctx)
                    |> Maybe.withDefault (Scala.TypeVar "TypeNotConverted")

            else
                Scala.TypeVar "TypeNotConverted"

        _ ->
            Scala.TypeVar "TypeNotConverted"


generateCastIfPossible : ValueMappingContext -> Type () -> Scala.Value -> Scala.Value
generateCastIfPossible ctx tpe value =
    case tpe of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] ->
            applySnowparkFunc "as_double" [ value ]

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "int" ] ) [] ->
            applySnowparkFunc "as_integer" [ value ]

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "string" ] ], [ "string" ] ) [] ->
            applySnowparkFunc "as_char" [ value ]

        Type.Reference _ fullName [] ->
            if isTypeAlias fullName ctx.typesContextInfo then
                resolveTypeAlias fullName ctx.typesContextInfo
                    |> Maybe.map (\t -> generateCastIfPossible ctx t value)
                    |> Maybe.withDefault value

            else
                value

        _ ->
            value


generateSnowparkTypeExprFromElmType : Type () -> MappingContextInfo () -> ( Scala.Value, Bool )
generateSnowparkTypeExprFromElmType tpe ctx =
    case tpe of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] ->
            ( applyForSnowparkTypesTypeExpr "FloatType", False )

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "double" ] ) [] ->
            ( applyForSnowparkTypesTypeExpr "DoubleType", False )

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "int" ] ) [] ->
            ( applyForSnowparkTypesTypeExpr "IntegerType", False )

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "bool" ] ) [] ->
            ( applyForSnowparkTypesTypeExpr "BooleanType", False )

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "string" ] ], [ "string" ] ) [] ->
            ( applyForSnowparkTypesTypeExpr "StringType", False )

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "maybe" ] ) [ innerType ] ->
            let
                ( generatedType, _ ) =
                    generateSnowparkTypeExprFromElmType innerType ctx
            in
            ( generatedType, True )

        Type.Reference _ fullTypeName [] ->
            if isUnionTypeWithoutParams fullTypeName ctx then
                ( applyForSnowparkTypesTypeExpr "StringType", False )

            else if isUnionTypeWithParams fullTypeName ctx then
                ( applyForSnowparkTypesType "MapType"
                    [ applyForSnowparkTypesTypeExpr "StringType"
                    , applyForSnowparkTypesTypeExpr "StringType"
                    ]
                , True
                )

            else
                resolveTypeAlias fullTypeName ctx
                    |> Maybe.map (\t -> generateSnowparkTypeExprFromElmType t ctx)
                    |> Maybe.withDefault ( applyForSnowparkTypesTypeExpr "VariantType", True )

        _ ->
            ( applyForSnowparkTypesTypeExpr "VariantType", True )
