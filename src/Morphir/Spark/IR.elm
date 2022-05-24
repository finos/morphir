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


type Expression
    = Column String
    | Literal Literal
    | Variable String
    | BinaryOperation String Expression Expression
    | WhenOtherwise Expression Expression Expression
    | Apply FQName (List Expression)


type alias NamedExpressions =
    List ( Name, Expression )


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
    | UnknownValueReturnedByFunction TypedValue
    | FunctionNotFound FQName
    | UnknownArgumentType (Type ())
    | UnsupportedOperatorReference FQName
    | LambdaExpected TypedValue
    | ReferenceExpected


objectExpressionFromValue : IR -> TypedValue -> Result Error ObjectExpression
objectExpressionFromValue ir morphirValue =
    case morphirValue of
        Value.Variable _ varName ->
            From varName |> Ok

        Value.Apply _ (Value.Apply _ (Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "filter" ] )) predicate) sourceRelation ->
            objectExpressionFromValue ir sourceRelation
                |> Result.andThen
                    (\source ->
                        expressionFromValue ir predicate
                            |> Result.map (\fieldExp -> Filter fieldExp source)
                    )

        Value.Apply _ (Value.Apply _ (Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "map" ] )) mappingFunction) sourceRelation ->
            objectExpressionFromValue ir sourceRelation
                |> Result.andThen
                    (\source ->
                        namedExpressionsFromValue ir mappingFunction
                            |> Result.map (\expr -> Select expr source)
                    )

        other ->
            let
                _ =
                    Debug.log "Relational.Backend.mapValue unhandled" other
            in
            Err (UnhandledValue other)


namedExpressionsFromValue : IR -> TypedValue -> Result Error NamedExpressions
namedExpressionsFromValue ir typedValue =
    case typedValue of
        Value.Lambda _ _ (Value.Record _ fields) ->
            fields
                |> List.map
                    (\( name, value ) ->
                        expressionFromValue ir value
                            |> Result.map (Tuple.pair name)
                    )
                |> ResultList.keepFirstError

        Value.FieldFunction _ name ->
            expressionFromValue ir typedValue
                |> Result.map (Tuple.pair name >> List.singleton)

        _ ->
            LambdaExpected typedValue |> Err


expressionFromValue : IR -> TypedValue -> Result Error Expression
expressionFromValue ir morphirValue =
    case morphirValue of
        Value.Literal _ literal ->
            Literal literal |> Ok

        Value.Variable _ name ->
            Name.toCamelCase name |> Variable |> Ok

        Value.Field _ _ name ->
            Name.toCamelCase name |> Column |> Ok

        Value.FieldFunction _ name ->
            Name.toCamelCase name |> Column |> Ok

        Value.Lambda _ _ body ->
            expressionFromValue ir body

        Value.Apply _ _ _ ->
            let
                collectArgsAsList : TypedValue -> List Expression -> Result Error ( List Expression, FQName )
                collectArgsAsList v argsLifted =
                    case v of
                        Value.Apply _ body a ->
                            expressionFromValue ir a
                                |> Result.andThen
                                    (\expr ->
                                        collectArgsAsList body (expr :: argsLifted)
                                    )

                        Value.Reference _ fqn ->
                            Ok ( argsLifted, fqn )

                        _ ->
                            Err ReferenceExpected
            in
            case morphirValue of
                Value.Apply _ ((Value.Apply _ (Value.Reference _ (( package, modName, _ ) as ref)) arg) as target) argValue ->
                    case ( package, modName ) of
                        ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ] ) ->
                            Result.map3
                                BinaryOperation
                                (binaryOpString ref)
                                (expressionFromValue ir arg)
                                (expressionFromValue ir argValue)

                        _ ->
                            expressionFromValue ir argValue
                                |> Result.andThen (List.singleton >> collectArgsAsList target)
                                |> Result.map (\( expressions, targetFQN ) -> Apply targetFQN expressions)

                Value.Apply _ (Value.Reference _ fqName) arg ->
                    expressionFromValue ir arg
                        |> Result.map
                            (List.singleton
                                >> Apply fqName
                            )

                _ ->
                    collectArgsAsList morphirValue []
                        |> Result.map (\( expressions, targetFQN ) -> Apply targetFQN expressions)

        Value.Reference _ fqName ->
            case IR.lookupValueDefinition fqName ir of
                Just { body } ->
                    expressionFromValue ir body

                Nothing ->
                    FunctionNotFound fqName |> Err

        Value.IfThenElse _ cond thenBranch elseBranch ->
            Result.map3
                WhenOtherwise
                (expressionFromValue ir cond)
                (expressionFromValue ir thenBranch)
                (expressionFromValue ir elseBranch)

        other ->
            UnhandledValue other |> Err


binaryOpString : FQName -> Result Error String
binaryOpString fQName =
    case FQName.toString fQName of
        "Morphir.SDK:Basics:equal" ->
            Ok "==="

        "Morphir.SDK:Basics:notEqual" ->
            Ok "=!="

        "Morphir.SDK:Basics:add" ->
            Ok "+"

        "Morphir.SDK:Basics:subtract" ->
            Ok "-"

        "Morphir.SDK:Basics:multiply" ->
            Ok "*"

        "Morphir.SDK:Basics:divide" ->
            Ok "/"

        "Morphir.SDK:Basics:power" ->
            Ok "pow"

        "Morphir.SDK:Basics:modBy" ->
            Ok "mod"

        "Morphir.SDK:Basics:remainderBy" ->
            Ok "%"

        "Morphir.SDK:Basics:logBase" ->
            Ok "log"

        "Morphir.SDK:Basics:atan2" ->
            Ok "atan2"

        "Morphir.SDK:Basics:lessThan" ->
            Ok "<"

        "Morphir.SDK:Basics:greaterThan" ->
            Ok ">"

        "Morphir.SDK:Basics:lessThanOrEqual" ->
            Ok "<="

        "Morphir.SDK:Basics:greaterThanOrEqual" ->
            Ok ">="

        "Morphir.SDK:Basics:max" ->
            Ok "max"

        "Morphir.SDK:Basics:min" ->
            Ok "min"

        "Morphir.SDK:Basics:and" ->
            Ok "and"

        "Morphir.SDK:Basics:or" ->
            Ok "or"

        "Morphir.SDK:Basics:xor" ->
            Ok "xor"

        _ ->
            UnsupportedOperatorReference fQName |> Err
