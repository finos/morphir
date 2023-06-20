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
    ( ObjectExpression(..), JoinType(..), Expression(..), DataFrame
    , objectExpressionFromValue
    , Error, NamedExpressions
    )

{-| An abstract-syntax tree for Spark. This is a custom built AST that focuses on the subset of Spark features that our
generator uses.


# Abstract Syntax Tree

@docs ObjectExpression, JoinType, Expression, NamedExpression, DataFrame


# Create

@docs objectExpressionFromValue, namedExpressionFromValue, expressionFromValue

-}

import Array exposing (Array)
import Dict exposing (Dict)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value exposing (Pattern(..), TypedValue)
import Morphir.SDK.Aggregate exposing (AggregateValue(..), AggregationCall(..), ConstructAggregationError, constructAggregationCall)
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
  - **Join**
      - Represents a `df.join(...)` transformation.
      - The four arguments are:
          - The type of join to apply (inner or left-outer). Corresponds to the last string argument in the Spark API.
          - The base relation as an ObjectExpression.
          - The relation to join as an ObjectExpression.
          - The "on" clause of the join. This is a boolean expression that should compare fields of the base and the
            joined relation.
  - **Aggregate**
      - Represents a `df.groupBy(...).agg(...)` transformation.
      - The arguments are:
          - A String, which represents the column to group aggregations by.
          - A list of named expressions, which represent the aggregation methods being used on this dataset.
          - The ObjectExpression to aggregate the results of.

-}
type ObjectExpression
    = From ObjectName
    | Filter Expression ObjectExpression
    | Select NamedExpressions ObjectExpression
    | Join JoinType ObjectExpression ObjectExpression Expression
    | Aggregate String NamedExpressions ObjectExpression


{-| Specifies which type of join to use. For now we only support inner and left-outer joins since that covers the
majority of real-world use-cases and we want to minimize complexity.

  - **Inner**
      - Represents an inner join.
  - **Left**
      - Represents a left-outer join.

-}
type JoinType
    = Inner
    | Left


{-| Most object expressions work with a single object/relation/data set but when joins are involved the resulting data
structure includes multiple data sets. Since each join combines 2 relations the resulting structure can always be
described as a binary tree where the leaves are individual relations. The Morphir model keeps track of this structure
implicitly by mapping joins to tuples but this information is not available for the Spark API so we need to keep track
of it explicitly.
-}
type JoinHierarchy
    = SingleObject ObjectName
    | JoinedObjects JoinHierarchy JoinHierarchy


{-| Utility to extract all object names in a potentially joined relation. The order and nesting of object names is
relevant and follows the order in which relations appear in the joins.


# Important Note

It is possible to get the same object name back multiple times if the same relation is joined multiple times (which is
a valid real-world use-case). When this happens we should rewrite the object expression and add aliasing (which is not
supported at the time of writing).

-}
objectExpressionJoinHierarchy : ObjectExpression -> JoinHierarchy
objectExpressionJoinHierarchy objectExpression =
    case objectExpression of
        From objectName ->
            SingleObject objectName

        Filter _ baseExpression ->
            objectExpressionJoinHierarchy baseExpression

        Select _ baseExpression ->
            objectExpressionJoinHierarchy baseExpression

        Join _ baseExpression joinedExpression _ ->
            JoinedObjects (objectExpressionJoinHierarchy baseExpression) (objectExpressionJoinHierarchy joinedExpression)

        Aggregate _ _ baseExpression ->
            objectExpressionJoinHierarchy baseExpression


{-| Given an argument pattern and a join hierarchy return a dictionary that correlates variable names to object names.
The algorithm recursively traverses both hierarchies at the same time and builds a dictionary along the way. The
traversal only considers tuple patterns and variables during traversal and as soon as it runs into a mismatch between
the two hierarchies it returns an empty dictionary.

Given the argument pattern: `( ( a, b ), c )` and join hierarchy
`JoinedObjects (JoinedObject (SingleObject "rel1") (SingleObject "rel2")) (SingleObject "rel3")` the dictionary will be
`Dict.fromList [ ("a", "rel1"), ("b", "rel2"), ("c", "rel3") ]`.

-}
correlateVariableToObjectName : Value.Pattern va -> JoinHierarchy -> Dict Name ObjectName
correlateVariableToObjectName argPattern joinHierarchy =
    case ( argPattern, joinHierarchy ) of
        ( Value.TuplePattern _ [ leftValue, rightValue ], JoinedObjects leftHierarchy rightHierarchy ) ->
            Dict.union
                (correlateVariableToObjectName leftValue leftHierarchy)
                (correlateVariableToObjectName rightValue rightHierarchy)

        ( Value.AsPattern _ (Value.WildcardPattern _) varName, SingleObject objectName ) ->
            Dict.singleton varName objectName

        _ ->
            Dict.empty


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
  - **Method**
      - Applies a list of arguments on a method to a target instance.
      - The three arguments are: An expression denoting the target instance, the name of the method to invoke, and a list of arguments to invoke the method with
  - **Function**
      - Applies a list of arguments on a function.
      - The two arguments are: The fully qualified name of the function to invoke, and a list of arguments to invoke the function with

-}
type Expression
    = Column String
    | Literal Literal
    | Variable String
    | BinaryOperation String Expression Expression
    | WhenOtherwise Expression Expression Expression
    | Method Expression String (List Expression)
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


type alias Description =
    String


type Error
    = UnhandledValue TypedValue
    | FunctionNotFound FQName
    | UnsupportedOperatorReference FQName
    | LambdaExpected TypedValue
    | UnsupportedSDKFunction FQName
    | EmptyPatternMatch
    | UnhandledPatternMatch ( Pattern (Type.Type ()), TypedValue )
    | UnhandledNamedExpressions NamedExpressions
    | UnhandledObjectExpression ObjectExpression
    | UnhandledExpression Expression
    | AggregationError ConstructAggregationError
    | ObjectExpressionsNotUnique (List ObjectExpression)


appendFunctionToSelect : FQName -> ObjectExpression -> Result Error ObjectExpression
appendFunctionToSelect funcName sourceExpression =
    case sourceExpression of
        Select (( sourceName, sourceArgs ) :: []) sourceSource ->
            fQNameToPartialSparkFunction funcName
                |> Result.map
                    (\partialFunc ->
                        Select [ ( sourceName, partialFunc [ sourceArgs ] ) ] sourceSource
                    )

        other ->
            Err (UnhandledObjectExpression other)


mergeSelects : List ObjectExpression -> Result Error ObjectExpression
mergeSelects expressions =
    let
        collectNamedExpressions : Result Error NamedExpressions
        collectNamedExpressions =
            expressions
                |> List.map
                    (\expression ->
                        case expression of
                            Select [ namedExpression ] (From _) ->
                                namedExpression |> Ok

                            Select [ ( exprName, Function funcName [ funcArg ] ) ] (Filter filterExpression (From _)) ->
                                -- i.e. `source.filter(...).select(...)` into `source.select(...)`
                                Ok
                                    ( exprName
                                    , Function funcName [ Function "when" [ filterExpression, funcArg ] ]
                                    )

                            other ->
                                UnhandledObjectExpression other |> Err
                    )
                |> ResultList.keepFirstError

        getRootSourceRelation : ObjectExpression -> Result Error ObjectExpression
        getRootSourceRelation relation =
            case relation of
                From _ ->
                    Ok relation

                Filter _ sourceRelation ->
                    getRootSourceRelation sourceRelation

                Select _ sourceRelation ->
                    getRootSourceRelation sourceRelation

                Join _ _ _ _ ->
                    -- XXX: Joins merge two source relations, no one "root"
                    Err (UnhandledObjectExpression relation)

                Aggregate _ _ _ ->
                    -- XXX: I don't expect to ever see this
                    Err (UnhandledObjectExpression relation)

        unique_items : List ObjectExpression -> List ObjectExpression
        unique_items items =
            List.foldr
                (\item list ->
                    if List.member item list then
                        list

                    else
                        item :: list
                )
                []
                items

        unique_roots =
            expressions
                |> List.map getRootSourceRelation
                |> ResultList.keepFirstError
                |> Result.map unique_items

        only_root =
            unique_roots
                |> Result.andThen
                    (\roots ->
                        case roots of
                            head :: [] ->
                                head |> Ok

                            _ ->
                                ObjectExpressionsNotUnique roots |> Err
                    )
    in
    Result.map2
        Select
        collectNamedExpressions
        only_root


substituteOnlyFieldName : Name -> ObjectExpression -> Result Error ObjectExpression
substituteOnlyFieldName fieldName sourceExpression =
    case sourceExpression of
        Select [ ( name, expression ) ] source ->
            Select [ ( fieldName, expression ) ] source |> Ok

        _ ->
            Err (UnhandledObjectExpression sourceExpression)


{-| provides a way to create ObjectExpressions from a Morphir Value.
This is where support for various top level expression is added. This function fails to produce an ObjectExpression
when it encounters a value that is not supported.
-}
objectExpressionFromValue : Distribution -> TypedValue -> Result Error ObjectExpression
objectExpressionFromValue ir morphirValue =
    case morphirValue of
        Value.Variable _ varName ->
            From varName |> Ok

        Value.Apply _ (Value.Apply _ (Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "aggregate" ] ], [ "aggregate" ] )) aggregateBody) (Value.Apply _ (Value.Apply _ (Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "aggregate" ] ], [ "group", "by" ] )) groupKey) sourceRelation) ->
            constructAggregationCall aggregateBody groupKey sourceRelation
                |> Result.mapError AggregationError
                |> Result.andThen (objectExpressionFromAggregationCall ir)

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

        Value.Apply _ (Value.Apply _ (Value.Apply _ (Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "innerJoin" ] )) joinedRelation) onClause) baseRelation ->
            buildJoin ir Inner baseRelation joinedRelation onClause

        Value.Apply _ (Value.Apply _ (Value.Apply _ (Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "leftJoin" ] )) joinedRelation) onClause) baseRelation ->
            buildJoin ir Left baseRelation joinedRelation onClause

        Value.LetDefinition _ _ _ _ ->
            inlineLetDef [] [] morphirValue
                |> objectExpressionFromValue ir

        Value.Apply _ (Value.Reference _ applyFuncName) sourceRelation ->
            objectExpressionFromValue ir sourceRelation
                |> Result.andThen (appendFunctionToSelect applyFuncName)

        Value.Apply applyType (Value.Lambda lamType lamArgs (Value.List _ [ (Value.Record _ _) as record ])) sourceRelation ->
            Value.Apply applyType (Value.Lambda lamType lamArgs record) sourceRelation
                |> objectExpressionFromValue ir

        Value.Apply _ ((Value.Lambda _ _ (Value.Record ta relations)) as lam) sourceRelation ->
            relations
                |> Dict.toList
                |> List.map
                    (\( name, value ) ->
                        inlineArguments (collectLambdaParams lam []) [ sourceRelation ] value
                            |> Tuple.pair name
                    )
                |> Dict.fromList
                |> Value.Record ta
                |> objectExpressionFromValue ir

        Value.Record _ relations ->
            relations
                |> Dict.toList
                |> List.map
                    (\( name, value ) ->
                        objectExpressionFromValue ir value
                            |> Result.andThen (substituteOnlyFieldName name)
                    )
                |> ResultList.keepFirstError
                |> Result.andThen mergeSelects

        Value.Apply _ (Value.Lambda _ (Value.AsPattern _ (WildcardPattern _) label) body) sourceRelation ->
            -- Attempt to inline simple lambdas to see if that makes it readable before erroring
            inlineArguments [ label ] [ sourceRelation ] body
                |> objectExpressionFromValue ir

        other ->
            let
                _ =
                    Debug.log "Relational.Backend.mapValue unhandled" other
            in
            Err (UnhandledValue other)


buildJoin : Distribution -> JoinType -> TypedValue -> TypedValue -> TypedValue -> Result Error ObjectExpression
buildJoin ir joinType baseRelation joinedRelation onClause =
    Result.map3 (Join joinType)
        (objectExpressionFromValue ir baseRelation)
        (objectExpressionFromValue ir joinedRelation)
        (expressionFromValue ir onClause)


namedExpressionsFromFields : Distribution -> Dict Name TypedValue -> Result Error NamedExpressions
namedExpressionsFromFields ir fields =
    fields
        |> Dict.toList
        |> List.map
            (\( name, value ) ->
                expressionFromValue ir value
                    |> Result.map (Tuple.pair name)
            )
        |> ResultList.keepFirstError


objectExpressionFromAggregationCall : Distribution -> AggregationCall -> Result Error ObjectExpression
objectExpressionFromAggregationCall ir aggregationCall =
    let
        spliceFilterIntoFunction : Expression -> Expression -> Result Error Expression
        spliceFilterIntoFunction filterExpr function =
            case function of
                Function funcName [ funcArg ] ->
                    Function funcName [ Function "when" [ filterExpr, funcArg ] ] |> Ok

                other ->
                    UnhandledExpression other |> Err

        namedExpressionFromAggValue : AggregateValue -> Result Error ( Name, Expression )
        namedExpressionFromAggValue aggValue =
            case aggValue of
                AggregateValue fieldName filterFunc aggName aggArg ->
                    let
                        aggArgs =
                            aggArg
                                |> Maybe.map List.singleton
                                |> Maybe.withDefault []

                        aggExpr =
                            mapSDKFunctions ir aggArgs aggName
                    in
                    case filterFunc of
                        Just filt ->
                            Result.map2
                                spliceFilterIntoFunction
                                (expressionFromValue ir filt)
                                aggExpr
                                |> Result.andThen (Result.map (Tuple.pair fieldName))

                        Nothing ->
                            aggExpr |> Result.map (Tuple.pair fieldName)
    in
    case aggregationCall of
        AggregationCall groupKey _ aggValues sourceRelation ->
            -- not using returned group key yet
            Result.map3
                Aggregate
                (groupKey |> Name.toTitleCase |> Ok)
                (aggValues
                    |> List.map namedExpressionFromAggValue
                    |> ResultList.keepFirstError
                )
                (objectExpressionFromValue ir sourceRelation)


{-| Provides a way to create NamedExpressions from a Morphir Value.
-}
namedExpressionsFromValue : Distribution -> TypedValue -> Result Error NamedExpressions
namedExpressionsFromValue ir typedValue =
    case typedValue of
        Value.Lambda _ _ (Value.List _ [ Value.Record _ fields ]) ->
            namedExpressionsFromFields ir fields

        Value.Lambda _ _ (Value.Record _ fields) ->
            namedExpressionsFromFields ir fields

        Value.FieldFunction _ name ->
            expressionFromValue ir typedValue
                |> Result.map (Tuple.pair name >> List.singleton)

        _ ->
            LambdaExpected typedValue |> Err


{-| Helper function to replace the value declared in a lambda with a specific other value
-}
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


constructWhenEqualsOtherwise : Distribution -> TypedValue -> List ( Pattern (Type.Type ()), TypedValue ) -> TypedValue -> Expression -> Result Error Expression
constructWhenEqualsOtherwise ir thenValue remainingCases leftValue rightExpr =
    Result.map3
        (\leftExpr thenExpr otherwiseExpr ->
            WhenOtherwise
                (BinaryOperation "===" leftExpr rightExpr)
                thenExpr
                otherwiseExpr
        )
        (expressionFromValue ir leftValue)
        (expressionFromValue ir thenValue)
        (mapPatterns ir leftValue remainingCases)


{-| Transforms a list of pattern,value tuples into Expressions
-}
mapPatterns : Distribution -> TypedValue -> List ( Pattern (Type.Type ()), TypedValue ) -> Result Error Expression
mapPatterns ir onValue cases =
    case cases of
        [] ->
            EmptyPatternMatch |> Err

        ( LiteralPattern _ lit, thenValue ) :: remainingCases ->
            Literal lit
                |> constructWhenEqualsOtherwise ir thenValue remainingCases onValue

        ( ConstructorPattern va fqn [], thenValue ) :: remainingCases ->
            -- e.g. 'Bar'. Note, 'Just Bar' would require the third arg to not be an empty list.
            fqn
                |> FQName.getLocalName
                |> Name.toTitleCase
                |> StringLiteral
                |> Literal
                |> constructWhenEqualsOtherwise ir thenValue remainingCases onValue

        [ ( WildcardPattern _, thenValue ) ] ->
            expressionFromValue ir thenValue

        ( otherPattern, otherValue ) :: _ ->
            UnhandledPatternMatch ( otherPattern, otherValue ) |> Err


{-| Provides a way to create Expressions from a Morphir Value.
This is where support for various column expression is added. This function fails to produce an Expression
when it encounters a value that is not supported.
-}
expressionFromValue : Distribution -> TypedValue -> Result Error Expression
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

        Value.PatternMatch _ onValue cases ->
            mapPatterns ir onValue cases

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
                (List.append names [ name ])
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
mapApply : Distribution -> List TypedValue -> TypedValue -> Result Error Expression
mapApply ir args target =
    case target of
        Value.Reference _ (( pkgName, modName, _ ) as fqn) ->
            case Distribution.lookupValueDefinition fqn ir of
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
                Value.Variable _ name ->
                    if name == searchTerm then
                        replacement

                    else
                        scope

                Value.Apply a target arg ->
                    Value.Apply a
                        (overwriteValue searchTerm replacement target)
                        (overwriteValue searchTerm replacement arg)

                Value.Lambda a pattern body ->
                    overwriteValue searchTerm replacement body
                        |> Value.Lambda a pattern

                Value.Record a args ->
                    args
                        |> Dict.toList
                        |> List.map
                            (\( name, value ) ->
                                overwriteValue searchTerm replacement value
                                    |> Tuple.pair name
                            )
                        |> Dict.fromList
                        |> Value.Record a

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


fQNameToPartialSparkFunction : FQName -> Result Error (List Expression -> Expression)
fQNameToPartialSparkFunction fQName =
    -- doesn't cover every call in mapSDKFunctions because some functions need special treatment
    case FQName.toString fQName of
        -- String Functions
        "Morphir.SDK:String:replace" ->
            Function "regexp_replace" |> Ok

        "Morphir.SDK:String:reverse" ->
            Function "reverse" |> Ok

        "Morphir.SDK:String:toUpper" ->
            Function "upper" |> Ok

        "Morphir.SDK:String:concat" ->
            UnsupportedSDKFunction fQName |> Err

        -- List Functions
        "Morphir.SDK:List:maximum" ->
            Function "max" |> Ok

        "Morphir.SDK:List:minimum" ->
            Function "min" |> Ok

        "Morphir.SDK:List:length" ->
            Function "count" |> Ok

        "Morphir.SDK:List:sum" ->
            Function "sum" |> Ok

        -- Aggregation Functions
        "Morphir.SDK:Aggregate:sumOf" ->
            Function "sum" |> Ok

        "Morphir.SDK:Aggregate:averageOf" ->
            Function "avg" |> Ok

        "Morphir.SDK:Aggregate:minimumOf" ->
            Function "min" |> Ok

        "Morphir.SDK:Aggregate:maximumOf" ->
            Function "max" |> Ok

        "Morphir.SDK:Aggregate:weightedAverageOf" ->
            -- XXX: I can't see a Spark equivalent
            UnsupportedSDKFunction fQName |> Err

        _ ->
            FunctionNotFound fQName |> Err


mapSDKFunctions : Distribution -> List TypedValue -> FQName -> Result Error Expression
mapSDKFunctions ir args fQName =
    case ( FQName.toString fQName, args ) of
        ( "Morphir.SDK:String:replace", pattern :: replacement :: target :: [] ) ->
            Result.map2
                (\partialFunc exprArgs -> partialFunc exprArgs)
                (fQNameToPartialSparkFunction fQName)
                ([ target, pattern, replacement ]
                    |> List.map (expressionFromValue ir)
                    |> ResultList.keepFirstError
                )

        ( "Morphir.SDK:List:member", item :: (Value.List _ list) :: [] ) ->
            Result.map2
                (\itemExpr listExpr ->
                    Method itemExpr "isin" listExpr
                )
                (expressionFromValue ir item)
                (list
                    |> List.map (expressionFromValue ir)
                    |> ResultList.keepFirstError
                )

        ( "Morphir.SDK:Aggregate:count", [] ) ->
            -- morphir's count takes no arguments, but Spark's does
            Function "count" [ Function "lit" [ Literal (WholeNumberLiteral 1) ] ] |> Ok

        _ ->
            Result.map2
                (\partialFunc exprArgs -> partialFunc exprArgs)
                (fQNameToPartialSparkFunction fQName)
                (args
                    |> List.map (expressionFromValue ir)
                    |> ResultList.keepFirstError
                )


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
