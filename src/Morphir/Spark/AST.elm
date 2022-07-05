{-
   Copyright 2020 Morgan Stanley

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-}


module Morphir.Spark.AST exposing
    ( ObjectExpression(..), Expression(..), DataFrame
    , objectExpressionFromValue
    , Error, NamedExpressions
    )

{-| An abstract-syntax tree for Spark. This is a custom built AST that focuses on the subset of Spark features that our
generator uses.


# Abstract Syntax Tree

@docs ObjectExpression, Expression, NamedExpression, DataFrame


# Create

@docs objectExpressionFromValue, namedExpressionFromValue, expressionFromValue

-}

import Array exposing (Array)
import Dict
import Morphir.IR as IR exposing (..)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value exposing (TypedValue)
import Morphir.SDK.ResultList as ResultList


{-| An ObjectExpression represents a transformation that is applied directly to a Spark Data Frame.
Like in the case of df.select(...), df.filter(...), df.groupBy(...); these expressions apply a transformation step
to the data within a Data Frame. They are also referred to as **Transformations** within spark.
ObjectExpressions produce DataFrames as output, making chaining of these transformations possible and for this reason,
ObjectExpression is expressed as a recursive type.

These are the supported Transformations:

  - **From**
      - Specifies a source that other ObjectExpressions can be applied on
      - The general assumption is that all sources are spark DataFrames
  - **Filter**
      - Represents a `df.filter(...)` transformation to be applied on DataFrame ObjectExpression.
      - The two arguments are: the ColumnExpression and the ObjectExpression to apply a filter on.
  - **Select**
      - Represents a `df.select(...)` transformation.
      - The two arguments are:
          - A List of (Name, Expression) which represent a alias for a column expression and a column expression
            like `col(name)` within spark.
          - A target ObjectExpression from which to select.

-}
type ObjectExpression
    = From ObjectName
    | Filter Expression ObjectExpression
    | Select NamedExpressions ObjectExpression


{-| An Expression represents an column expression.
Expressions produce a value that is usually of type `Column` in spark. ,
An Expression could take in a `Column` type or `Any` type as input and also produce a Column type and for this reason,
Expression is expressed as a recursive type.

These are the supported Expressions:

  - **Column**
      - Specifies the name of a column in a DataFrame similar to the `col("name")` in spark
  - **Literal**
      - Represents a literal value like `1`, `"Hello"`, `2.3`.
  - **Variable**
      - Represents a variable name like `param`.
  - **BinaryOperation**
      - BinaryOperations represent binary operations like `1 + 2`.
      - The three arguments are: the operator, the left hand side expression, and the right hand side expression
  - **WhenOtherwise**
      - Represent a `when(expression, result).otherwise(expression, result)` in spark.
      - It maps directly to an IfElse statement and can be chained.
      - The three arguments are: the condition, the Then expression evaluated if the condition passes, and the Else expression.
  - **Apply**
      - Applies a list of arguments on a function.
      - The two arguments are: The fully qualified name of the function to invoke, and a list of arguments to invoke the function with

-}
type Expression
    = Column String
    | Literal Literal
    | Variable String
    | BinaryOperation String Expression Expression
    | WhenOtherwise Expression Expression Expression
    | Function String (List Expression)


{-| A List of (Name, Expression) where each Name represents an alias for a column expression,
and the Expression is a column expression like `col(name)` within spark that gets aliased.
-}
type alias NamedExpressions =
    List ( Name, Expression )


{-| A representation of an acceptable DataFrame structure
-}
type alias DataFrame =
    { schema : List FieldName
    , data : List (Array ObjectExpression)
    }


type alias ObjectName =
    Name


type alias FieldName =
    Name


type Error
    = UnhandledValue TypedValue
    | FunctionNotFound FQName
    | UnsupportedOperatorReference FQName
    | LambdaExpected TypedValue
    | ReferenceExpected
    | UnsupportedSDKFunction FQName


{-| provides a way to create ObjectExpressions from a Morphir Value.
This is where support for various top level expression is added. This function fails to produce an ObjectExpression
when it encounters a value that is not supported.
-}
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

        Value.LetDefinition _ _ _ _ ->
            inlineLetDef [] [] morphirValue
                |> objectExpressionFromValue ir

        other ->
            let
                _ =
                    Debug.log "Relational.Backend.mapValue unhandled" other
            in
            Err (UnhandledValue other)


{-| Provides a way to create NamedExpressions from a Morphir Value.
-}
namedExpressionsFromValue : IR -> TypedValue -> Result Error NamedExpressions
namedExpressionsFromValue ir typedValue =
    case typedValue of
        Value.Lambda _ _ (Value.Record _ fields) ->
            fields
                |> Dict.toList
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



{- | Helper function to replace the value declared in a lambda with a specific other value -}


replaceLambdaArg : TypedValue -> TypedValue -> Result Error TypedValue
replaceLambdaArg replacementValue lam =
    -- extract the name of the lambda arg and replace every variable with replacementValue
    case lam of
        Value.Lambda _ (Value.AsPattern _ _ name) body ->
            body
                |> Value.rewriteValue
                    (\currentValue ->
                        case currentValue of
                            Value.Variable _ otherName ->
                                if name == otherName then
                                    Just replacementValue

                                else
                                    Nothing

                            _ ->
                                Nothing
                    )
                |> Ok

        other ->
            UnhandledValue other |> Err


{-| Provides a way to create Expressions from a Morphir Value.
This is where support for various column expression is added. This function fails to produce an Expression
when it encounters a value that is not supported.
-}
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
            case morphirValue of
                Value.Apply _ (Value.Apply _ (Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "with", "default" ] )) elseValue) (Value.Apply _ (Value.Apply _ (Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "map" ] )) thenValue) sourceValue) ->
                    -- `value |> Maybe.map thenValue |> Maybe.withDefault elseValue` becomes `when(not(isnull(value)), thenValue).otherwise(elseValue)`
                    Result.map3
                        (\sourceExpr thenExpr elseExpr ->
                            WhenOtherwise (Function "not" [ Function "isnull" [ sourceExpr ] ]) thenExpr elseExpr
                        )
                        (expressionFromValue ir sourceValue)
                        (thenValue
                            |> replaceLambdaArg sourceValue
                            |> Result.andThen (expressionFromValue ir)
                        )
                        (expressionFromValue ir elseValue)

                Value.Apply _ (Value.Literal (Type.Function _ _ (Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "maybe" ] ) _)) (StringLiteral "Just")) arg ->
                    -- `Just arg` becomes `arg` if `Just` was a Maybe.
                    expressionFromValue ir arg

                Value.Apply _ (Value.Apply _ (Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "not", "equal" ] )) arg) (Value.Literal (Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "maybe" ] ) _) (StringLiteral "Nothing")) ->
                    -- `arg /= Nothing` becomes `not(isnull(arg))` if `Nothing` was a Maybe.
                    expressionFromValue ir arg
                        |> Result.map (\expr -> Function "not" [ Function "isnull" [ expr ] ])

                Value.Apply _ (Value.Apply _ (Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "equal" ] )) arg) (Value.Literal (Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "maybe" ] ) _) (StringLiteral "Nothing")) ->
                    -- `arg == Nothing` becomes `isnull(arg)` if `Nothing` was a Maybe.
                    expressionFromValue ir arg
                        |> Result.map (\expr -> Function "isnull" [ expr ])

                Value.Apply _ (Value.Apply _ (Value.Reference _ (( package, modName, _ ) as ref)) arg) argValue ->
                    case ( package, modName ) of
                        ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ] ) ->
                            Result.map3
                                BinaryOperation
                                (binaryOpString ref)
                                (expressionFromValue ir arg)
                                (expressionFromValue ir argValue)

                        _ ->
                            collectArgValues morphirValue []
                                |> (\( args, applyTarget ) -> mapApply ir args applyTarget)

                _ ->
                    collectArgValues morphirValue []
                        |> (\( args, applyTarget ) -> mapApply ir args applyTarget)

        Value.Reference _ _ ->
            mapApply ir [] morphirValue

        Value.IfThenElse _ cond thenBranch elseBranch ->
            Result.map3
                WhenOtherwise
                (expressionFromValue ir cond)
                (expressionFromValue ir thenBranch)
                (expressionFromValue ir elseBranch)

        Value.LetDefinition _ _ _ _ ->
            inlineLetDef [] [] morphirValue
                |> expressionFromValue ir

        other ->
            UnhandledValue other |> Err


{-| Turns a Value definition into a lambda function.
-}
lambdaFromDefinition : Value.Definition () (Type.Type ()) -> TypedValue
lambdaFromDefinition valueDef =
    valueDef.inputTypes
        |> List.foldr
            (\( name, va, _ ) val ->
                Value.Lambda va
                    (Value.AsPattern va
                        (Value.WildcardPattern va)
                        name
                    )
                    val
            )
            valueDef.body


{-| Inline simple let bindings
-}
inlineLetDef : List Name -> List TypedValue -> TypedValue -> TypedValue
inlineLetDef names letValues v =
    case v of
        Value.LetDefinition _ name def inValue ->
            let
                inlined =
                    inlineArguments names letValues def.body
            in
            inlineLetDef
                (List.append [ name ] names)
                ({ def | body = inlined }
                    |> lambdaFromDefinition
                    |> List.singleton
                    |> List.append letValues
                )
                inValue

        _ ->
            inlineArguments names letValues v


{-| Collect arguments that are applied on a value
-}
collectArgValues : TypedValue -> List TypedValue -> ( List TypedValue, TypedValue )
collectArgValues v argsSoFar =
    case v of
        Value.Apply _ body a ->
            collectArgValues body (a :: argsSoFar)

        _ ->
            ( argsSoFar, v )


{-| Collect the params in a lambda
-}
collectLambdaParams : TypedValue -> List Name -> List Name
collectLambdaParams value paramsCollected =
    case value of
        Value.Lambda _ pattern body ->
            case pattern of
                Value.AsPattern _ (Value.WildcardPattern _) name ->
                    List.concat [ paramsCollected, [ name ] ]
                        |> collectLambdaParams body

                _ ->
                    paramsCollected

        _ ->
            paramsCollected


{-| Creates Expression from a function application.
The input to this function include the list of arguments and the target of the apply.
If the `target` is a `Reference` it looks up the function and replaces all references to its
param variables with the arguments. If the `target` is a lambda, it first attempts to look into
the lambda body and rewrite any enclosed variables and then repeats the process for
the lambda's params.
-}
mapApply : IR -> List TypedValue -> TypedValue -> Result Error Expression
mapApply ir args target =
    case target of
        Value.Reference _ (( pkgName, modName, _ ) as fqn) ->
            case IR.lookupValueDefinition fqn ir of
                Just def ->
                    inlineArguments
                        (List.map (\( n, _, _ ) -> n) def.inputTypes)
                        args
                        def.body
                        |> expressionFromValue ir

                Nothing ->
                    case ( ( pkgName, modName ), args ) of
                        ( ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ] ), left :: right :: [] ) ->
                            Result.map3
                                BinaryOperation
                                (binaryOpString fqn)
                                (expressionFromValue ir left)
                                (expressionFromValue ir right)

                        _ ->
                            mapSDKFunctions ir args fqn

        Value.Lambda _ _ body ->
            inlineArguments
                (collectLambdaParams target [])
                args
                body
                |> expressionFromValue ir

        _ ->
            UnhandledValue target |> Err


{-| A utility function that replaces variables in a function with their values.
-}
inlineArguments : List Name -> List TypedValue -> TypedValue -> TypedValue
inlineArguments paramList argList fnBody =
    let
        overwriteValue : Name -> TypedValue -> TypedValue -> TypedValue
        overwriteValue searchTerm replacement scope =
            -- TODO handle replacement of the variable within a lambda
            case scope of
                Value.Apply a target ((Value.Variable _ name) as var) ->
                    if name == searchTerm then
                        -- Replace variable if the name matches the searchTerm
                        Value.Apply a
                            (overwriteValue searchTerm replacement target)
                            replacement

                    else
                        -- Name does not match. Maintain variable
                        Value.Apply a
                            (overwriteValue searchTerm replacement target)
                            var

                Value.Apply a target arg ->
                    Value.Apply a
                        (overwriteValue searchTerm replacement target)
                        (overwriteValue searchTerm replacement arg)

                Value.Lambda a pattern body ->
                    overwriteValue searchTerm replacement body
                        |> Value.Lambda a pattern

                _ ->
                    scope
    in
    paramList
        |> List.map2 Tuple.pair argList
        |> List.foldl
            (\( arg, varName ) body ->
                overwriteValue varName arg body
            )
            fnBody


mapSDKFunctions : IR -> List TypedValue -> FQName -> Result Error Expression
mapSDKFunctions ir args fQName =
    case ( FQName.toString fQName, args ) of
        ( "Morphir.SDK:String:replace", pattern :: replacement :: target :: [] ) ->
            [ target, pattern, replacement ]
                |> List.map (expressionFromValue ir)
                |> ResultList.keepFirstError
                |> Result.map (Function "regexp_replace")

        ( "Morphir.SDK:String:reverse", _ ) ->
            args
                |> List.map (expressionFromValue ir)
                |> ResultList.keepFirstError
                |> Result.map (Function "reverse")

        ( "Morphir.SDK:String:toUpper", _ ) ->
            args
                |> List.map (expressionFromValue ir)
                |> ResultList.keepFirstError
                |> Result.map (Function "upper")

        ( "Morphir.SDK:String:concat", _ ) ->
            UnsupportedSDKFunction fQName |> Err

        _ ->
            FunctionNotFound fQName |> Err


{-| A simple mapping for a Morphir.SDK:Basics binary operations to its spark string equivalent
-}
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
