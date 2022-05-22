module Morphir.Spark.IR exposing (..)

{-| An IR for Spark
-}

import Array exposing (Array)
import Morphir.IR as IR exposing (..)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Literal exposing (Literal)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (TypedValue)
import Morphir.SDK.ResultList as ResultList


type ObjectExpression
    = From ObjectName
    | Filter FieldExpression ObjectExpression
    | Select FieldExpressions ObjectExpression


type alias FieldExpressions =
    List ( Name, FieldExpression )


type FieldExpression
    = Lit Literal
    | Col Name
    | ColumExpression FQName FieldExpression FieldExpression
    | WhenOtherwise FieldExpression FieldExpression FieldExpression
    | Transform FieldExpression FieldExpression -- colName, morphirValue
    | Lambda (List Name) TypedValue
    | Native FQName
    | GenericExpression TypedValue


type alias DataFrame =
    { schema : List FieldName
    , data : List (Array FieldExpression)
    }


type alias ObjectName =
    Name


type alias FieldName =
    Name


type Error
    = UnhandledValue TypedValue
    | UnknownValueReturnedByMapFunction TypedValue
    | FunctionNotFound FQName
    | UnknownArgumentType (Type ())
    | LambdaExpected TypedValue


objectExpressionFromValue : IR -> TypedValue -> Result Error ObjectExpression
objectExpressionFromValue ir morphirValue =
    case morphirValue of
        Value.Variable _ varName ->
            From varName |> Ok

        Value.Apply _ (Value.Apply _ (Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "filter" ] )) predicate) sourceRelation ->
            objectExpressionFromValue ir sourceRelation
                |> Result.map
                    (\source ->
                        fieldExpressionFromValue ir predicate
                            |> (\fieldExp -> Filter fieldExp source)
                    )

        Value.Apply _ (Value.Apply _ (Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "map" ] )) mappingFunction) sourceRelation ->
            objectExpressionFromValue ir sourceRelation
                |> Result.map (Select (fieldExpressionsFromValue ir mappingFunction))

        other ->
            let
                _ =
                    Debug.log "Relational.Backend.mapValue unhandled" other
            in
            Err (UnhandledValue other)


fieldExpressionsFromValue : IR -> TypedValue -> FieldExpressions
fieldExpressionsFromValue ir typedValue =
    case typedValue of
        Value.Lambda _ _ (Value.Record _ fields) ->
            fields
                |> List.map
                    (\( name, value ) ->
                        ( name, fieldExpressionFromValue ir value )
                    )

        Value.FieldFunction _ name ->
            [ ( name, Col name ) ]

        _ ->
            []


fieldExpressionFromValue : IR -> TypedValue -> FieldExpression
fieldExpressionFromValue ir typedValue =
    case typedValue of
        Value.Literal _ literal ->
            Lit literal

        Value.Lambda _ _ body ->
            fieldExpressionFromValue ir body

        Value.FieldFunction _ name ->
            Col name

        Value.Field _ _ name ->
            Col name

        Value.Apply applyType (Value.Reference refType fQName) argValue ->
            let
                argList : TypedValue -> TypedValue
                argList v =
                    case v of
                        (Value.Literal _ _) as variable ->
                            variable

                        (Value.Variable _ _) as variable ->
                            variable

                        Value.Field va _ name ->
                            Value.Variable va name

                        Value.FieldFunction va name ->
                            Value.Variable va name

                        Value.List va values ->
                            List.map argList values
                                |> Value.List va

                        Value.Tuple va values ->
                            List.map argList values
                                |> Value.List va

                        _ ->
                            Value.Unit (Type.Unit ())

                argNames : TypedValue -> List Name
                argNames v =
                    case v of
                        Value.Field _ _ name ->
                            [ name ]

                        Value.FieldFunction _ name ->
                            [ name ]

                        Value.List _ values ->
                            List.map argNames values |> List.concat

                        Value.Tuple _ values ->
                            List.map argNames values |> List.concat

                        _ ->
                            []

                lambda =
                    Lambda (argNames argValue) (Value.Apply applyType (Value.Reference refType fQName) (argList argValue))

                colName =
                    case argValue of
                        Value.Field _ _ name ->
                            Col name

                        Value.FieldFunction _ name ->
                            Col name

                        _ ->
                            -- Todo Handle this better
                            Col []
            in
            Transform colName lambda

        Value.Apply _ (Value.Apply _ (Value.Reference _ fqName) fn) argValue ->
            ColumExpression fqName (fieldExpressionFromValue ir fn) (fieldExpressionFromValue ir argValue)

        Value.IfThenElse _ condition thenBranch elseBranch ->
            WhenOtherwise
                (fieldExpressionFromValue ir condition)
                (fieldExpressionFromValue ir thenBranch)
                (fieldExpressionFromValue ir elseBranch)

        Value.Reference _ fqName ->
            case IR.lookupValueDefinition fqName ir of
                Just { body } ->
                    fieldExpressionFromValue ir body

                Nothing ->
                    mapReference typedValue

        _ ->
            GenericExpression typedValue


mapReference : TypedValue -> FieldExpression
mapReference value =
    case value of
        Value.Reference _ (( package, _, _ ) as fqn) ->
            case package |> Path.toString Name.toTitleCase "." of
                "Morphir.SDK" ->
                    Native fqn

                _ ->
                    GenericExpression value

        other ->
            GenericExpression other
