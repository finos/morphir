module Morphir.Spark.IR exposing (..)

{-| An IR for Spark
-}

import Array exposing (Array)
import Morphir.IR as IR exposing (..)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Literal exposing (Literal)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (TypedValue)
import Morphir.SDK.ResultList as ResultList


type ObjectExpression
    = From ObjectName
    | Filter Expression ObjectExpression
    | Select NamedExpressions ObjectExpression


type alias NamedExpressions =
    List ( Name, Expression )


type Expression
    = Simple SimpleExpression
    | Operator FQName Expression Expression
    | Function FunctionExpression
    | Unresolved TypedValue


type FunctionExpression
    = WhenOtherwise FunctionExpression FunctionExpression FunctionExpression
    | Transform SimpleExpression FunctionExpression
    | Lambda (List String) FunctionExpression
    | Apply FunctionExpression (List FunctionExpression)
      --| Compound FunctionExpression FunctionExpression -- chained expression
    | Value SimpleExpression


type SimpleExpression
    = Column String
    | Literal Literal
    | Reference FQName
    | Variable String
    | Unknown TypedValue


type alias DataFrame =
    { schema : List FieldName
    , data : List (Array Expression)
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
                        expressionFromValue ir predicate
                            |> (\fieldExp -> Filter fieldExp source)
                    )

        Value.Apply _ (Value.Apply _ (Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "map" ] )) mappingFunction) sourceRelation ->
            objectExpressionFromValue ir sourceRelation
                |> Result.map (Select (namedExpressionsFromValue ir mappingFunction))

        other ->
            let
                _ =
                    Debug.log "Relational.Backend.mapValue unhandled" other
            in
            Err (UnhandledValue other)


namedExpressionsFromValue : IR -> TypedValue -> NamedExpressions
namedExpressionsFromValue ir typedValue =
    case typedValue of
        Value.Lambda _ _ (Value.Record _ fields) ->
            fields
                |> List.map
                    (\( name, value ) ->
                        ( name, expressionFromValue ir value )
                    )

        Value.FieldFunction _ name ->
            [ ( name, expressionFromValue ir typedValue ) ]

        _ ->
            []


expressionFromValue : IR -> TypedValue -> Expression
expressionFromValue ir morphirValue =
    case morphirValue of
        Value.Literal _ _ ->
            simpleExpressionFromValue ir morphirValue |> Simple

        Value.FieldFunction _ _ ->
            simpleExpressionFromValue ir morphirValue |> Simple

        Value.Field _ _ _ ->
            simpleExpressionFromValue ir morphirValue |> Simple

        Value.Lambda _ _ body ->
            expressionFromValue ir body

        Value.Apply _ (Value.Reference _ _) _ ->
            functionExpressionFromValue ir morphirValue |> Function

        Value.Apply _ (Value.Apply _ (Value.Reference _ (( package, modName, _ ) as ref)) arg) argValue ->
            -- check if the fqn is inherently supported and then map to
            -- the appropraite expression
            case ( package, modName ) of
                ( [ [ "morphir" ], [ "sdk" ] ], [ [ "basics" ] ] ) ->
                    Operator
                        ref
                        (expressionFromValue ir arg)
                        (expressionFromValue ir argValue)

                _ ->
                    functionExpressionFromValue ir morphirValue |> Function

        Value.Apply _ _ _ ->
            functionExpressionFromValue ir morphirValue |> Function

        Value.IfThenElse _ _ _ _ ->
            functionExpressionFromValue ir morphirValue |> Function

        Value.Reference _ fqName ->
            case IR.lookupValueDefinition fqName ir of
                Just { body } ->
                    functionExpressionFromValue ir body |> Function

                Nothing ->
                    simpleExpressionFromValue ir morphirValue |> Simple

        _ ->
            Unresolved morphirValue


functionExpressionFromValue : IR -> TypedValue -> FunctionExpression
functionExpressionFromValue ir morphirValue =
    case morphirValue of
        Value.Literal _ _ ->
            simpleExpressionFromValue ir morphirValue |> Value

        Value.Variable _ _ ->
            simpleExpressionFromValue ir morphirValue |> Value

        Value.Reference _ _ ->
            simpleExpressionFromValue ir morphirValue |> Value

        Value.IfThenElse _ cond thenBranch elseBranch ->
            WhenOtherwise
                (functionExpressionFromValue ir cond)
                (functionExpressionFromValue ir thenBranch)
                (functionExpressionFromValue ir elseBranch)

        Value.Apply _ ((Value.Reference _ fqName) as ref) arg ->
            case IR.lookupValueDefinition fqName ir of
                Just { body } ->
                    functionExpressionFromValue ir body

                Nothing ->
                    Apply
                        (functionExpressionFromValue ir ref)
                        (functionExpressionFromValue ir arg |> List.singleton)

        Value.Apply _ target arg ->
            let
                colName =
                    case arg of
                        Value.Field _ _ name ->
                            Name.toCamelCase name

                        Value.FieldFunction _ name ->
                            Name.toCamelCase name

                        _ ->
                            -- Todo Handle this better
                            ""

                -- TODO needs revision
                collectArgsAsList : TypedValue -> List SimpleExpression -> ( List SimpleExpression, FunctionExpression )
                collectArgsAsList v argsLifted =
                    case v of
                        Value.Apply _ body a ->
                            collectArgsAsList body (simpleExpressionFromValue ir a :: argsLifted)

                        Value.Reference _ _ ->
                            ( argsLifted
                            , simpleExpressionFromValue ir v |> Value
                            )

                        val ->
                            ( argsLifted, functionExpressionFromValue ir val )

                simpleExpressionToNamedArgs : SimpleExpression -> SimpleExpression
                simpleExpressionToNamedArgs simpleExpression =
                    case simpleExpression of
                        Column name ->
                            Variable name

                        other ->
                            other

                lambdaBody =
                    simpleExpressionFromValue ir arg
                        |> List.singleton
                        |> collectArgsAsList target
                        |> Tuple.mapFirst (List.map (simpleExpressionToNamedArgs >> Value))
                        |> (\( simpleExprs, fnExpr ) -> Apply fnExpr simpleExprs)
            in
            Transform (Column colName)
                (Lambda [ colName ] lambdaBody)

        other ->
            Value (simpleExpressionFromValue ir other)


simpleExpressionFromValue : IR -> TypedValue -> SimpleExpression
simpleExpressionFromValue ir morphirValue =
    case morphirValue of
        Value.Literal _ literal ->
            Literal literal

        Value.Variable _ name ->
            Name.toCamelCase name |> Variable

        Value.Reference _ fQName ->
            Reference fQName

        Value.Field _ _ name ->
            Name.toCamelCase name |> Column

        Value.FieldFunction _ name ->
            Name.toCamelCase name |> Column

        _ ->
            Unknown morphirValue
