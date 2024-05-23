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


module Morphir.IR.Value exposing
    ( Value(..), RawValue, TypedValue, literal, constructor, apply, field, fieldFunction, lambda, letDef, letDestruct, letRec, list, record, reference
    , tuple, variable, ifThenElse, patternMatch, update, unit
    , mapValueAttributes, rewriteMaybeToPatternMatch, replaceVariables
    , Pattern(..), wildcardPattern, asPattern, tuplePattern, constructorPattern, emptyListPattern, headTailPattern, literalPattern
    , Specification, mapSpecificationAttributes
    , Definition, mapDefinition, mapDefinitionAttributes
    , definitionToSpecification, typeAndValueToDefinition, uncurryApply, collectVariables, collectReferences, collectDefinitionAttributes, collectPatternAttributes
    , collectValueAttributes, indexedMapPattern, indexedMapValue, mapPatternAttributes, patternAttribute, valueAttribute
    , definitionToValue, rewriteValue, toRawValue, countValueNodes, collectPatternVariables, isData, toString
    , generateUniqueName
    , reduceValueBottomUp
    )

{-| In functional programming data and logic are treated the same way and we refer to both as values. This module
provides the building blocks for those values (data and logic) in the Morphir IR.

If you use Elm as your frontend language for Morphir then you should think about all the logic and constant values that
you can put in the body of a function. Here are a few examples:

    myThreshold =
        1000

    min a b =
        if a < b then
            a

        else
            b

    addTwo a =
        a + 2

All the above are values: the first one is just data, the second one is logic and the last one has both logic and data.
In either case each value is represented by a [`Value`](#Value) expression. This is a recursive data structure with
various node types representing each possible language construct. You can check out the documentation for values below
to find more details. Here are the Morphir IR snippets for the above values as a quick reference:

    myThreshold =
        Literal () (WholeNumberLiteral 1000)

    min a b =
        IfThenElse ()
            (Apply ()
                (Apply ()
                    (Reference () (fqn "Morphir.SDK" "Basics" "lessThan"))
                    (Variable () [ "a" ])
                )
                (Variable () [ "b" ])
            )
            (Variable () [ "a" ])
            (Variable () [ "b" ])

    addTwo a =
        Apply ()
            (Apply ()
                (Reference () (fqn "Morphir.SDK" "Basics" "add"))
                (Variable () [ "a" ])
            )
            (Literal () (WholeNumberLiteral 2))


# Value

Value is the top level building block for data and logic. See the constructor functions below for details on each node type.

@docs Value, RawValue, TypedValue, literal, constructor, apply, field, fieldFunction, lambda, letDef, letDestruct, letRec, list, record, reference
@docs tuple, variable, ifThenElse, patternMatch, update, unit
@docs mapValueAttributes, rewriteMaybeToPatternMatch, replaceVariables


# Pattern

Patterns are used in multiple ways in the IR: they can take apart a structured value into smaller pieces (destructure) and they
can also filter values. The combination of these two features creates a very powerful method tool that can be used in two ways:
destructuring and pattern-matching. Pattern-matching is a combination of destructuring, filtering and branching.

@docs Pattern, wildcardPattern, asPattern, tuplePattern, constructorPattern, emptyListPattern, headTailPattern, literalPattern


# Specification

The specification of what the value or function
is without the actual data or logic behind it.

@docs Specification, mapSpecificationAttributes


# Definition

A definition is the actual data or logic as opposed to a specification
which is just the specification of those. Value definitions can be typed or untyped. Exposed values have to be typed.

@docs Definition, mapDefinition, mapDefinitionAttributes


# Utilities

@docs definitionToSpecification, typeAndValueToDefinition, uncurryApply, collectVariables, collectReferences, collectDefinitionAttributes, collectPatternAttributes
@docs collectValueAttributes, indexedMapPattern, indexedMapValue, mapPatternAttributes, patternAttribute, valueAttribute
@docs definitionToValue, rewriteValue, toRawValue, countValueNodes, collectPatternVariables, isData, toString
@docs generateUniqueName
@docs reduceValueBottomUp

-}

import Dict exposing (Dict)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type exposing (Type)
import Morphir.SDK.Decimal as Decimal
import Morphir.SDK.UUID exposing (UUID)
import Morphir.SDK.ResultList as ListOfResults
import Set exposing (Set)


{-| Type that represents a value expression. This is a recursive data structure with various node types representing
each possible language construct.

The extra type parameters `ta` and `va` allow you to add type and value attributes. Type attributes allow you to add
extra information to each type node. Value attributes do the same for value nodes. In many cases you might not need this
in which case you can just put a unit (`()`) type or a type variable as a placeholder.

These are the supported node types:

  - **Literal**
      - Represents a literal value like 13, True or "foo".
      - See the documentation in the [Literal](Morphir-IR-Literal) module for details on the supported literal types.
      - See [Wikipedia: Literal](https://en.wikipedia.org/wiki/Literal_(computer_programming)) for more details on
        literals.
  - **Constructor**
      - Reference to a custom type constructor name.
      - If the type constructor has arguments this node will be wrapped into some `Apply` nodes depending on the number
        of arguments.
  - **Tuple**
      - Represents a tuple value.
      - Each element of the tuple is in turn a `Value`.
  - **List**
      - Represents a list of values.
      - Each item of the list is in turn a `Value`.
  - **Record**
      - Represents a record value.
      - Each field value of the record is in turn a `Value`.
  - **Variable**
      - Reference to a variable.
  - **Reference**
      - Reference to another value within or outside the module.
      - References are always full-qualified to make resolution easier.
  - **Field**
      - Represents accessing a field on a record together with the target expression.
      - This is done using the dot notation in Elm: `foo.bar`
  - **FieldFunction**
      - Represents accessing a field on a record without the target expression.
      - This is a shortcut to refer to the function that extracts the field from the input.
      - This is done using the dot notation in Elm without a target expression: `.bar`
  - **Apply**
      - Represents a function application.
      - The two arguments are the target function and the argument.
      - Multi-argument invocations are expressed by wrapping multiple `Apply` nodes in each other (currying).
  - **Lambda**
      - Represents a lambda abstraction.
      - The first argument is a pattern to match on the input, the second is the lambda expression's body.
  - **LetDefinition**
      - Represents a single let binding.
      - Multiple let bindings are achieved through wrapping multiple let expressions into each other.
  - **LetRecursion**
      - Special let binding that allows mutual recursion between the bindings.
      - This is necessary because `LetDefinition` will not make recursion possible due to its scoping rules.
  - **Destructure**
      - Applies a pattern match to the first expression and passes any extracted variables to the second expression.
      - This can be represented as a let expression with a pattern binding or a single-case pattern-match in Elm.
  - **IfThenElse**
      - Represents a simple if/then/else expression.
      - The 3 arguments are: the condition, the then branch and the else branch.
  - **PatternMatch**
      - Represents a pattern-match.
  - **UpdateRecord**
      - Expression to update one or more fields of a record.
      - As usual in FP this is a copy-on-update so no mutation is happening.
  - **Unit**
      - Represents the single value in the Unit type.
      - When you find Unit in the IR it usually means: "There's nothing useful here".

-}
type Value ta va
    = Literal va Literal
    | Constructor va FQName
    | Tuple va (List (Value ta va))
    | List va (List (Value ta va))
    | Record va (Dict Name (Value ta va))
    | Variable va Name
    | Reference va FQName
    | Field va (Value ta va) Name
    | FieldFunction va Name
    | Apply va (Value ta va) (Value ta va)
    | Lambda va (Pattern va) (Value ta va)
    | LetDefinition va Name (Definition ta va) (Value ta va)
    | LetRecursion va (Dict Name (Definition ta va)) (Value ta va)
    | Destructure va (Pattern va) (Value ta va) (Value ta va)
    | IfThenElse va (Value ta va) (Value ta va) (Value ta va)
    | PatternMatch va (Value ta va) (List ( Pattern va, Value ta va ))
    | UpdateRecord va (Value ta va) (Dict Name (Value ta va))
    | Unit va


{-| A value without any additional information.
-}
type alias RawValue =
    Value () ()


{-| Clear all type and value annotations to get a raw value.
-}
toRawValue : Value ta va -> RawValue
toRawValue value =
    value |> mapValueAttributes (always ()) (always ())


{-| A value with type information.
-}
type alias TypedValue =
    Value () (Type ())


{-| Type that represents a pattern. A pattern can do two things: match on a specific shape or exact value and extract
parts of a value into variables. It's a recursive data structure made of of the following building blocks:

  - **WildcardPattern**
      - Matches any value and does not extract any variables.
      - `_` in Elm
  - **AsPattern**
      - Assigns a variable name to the value matched by a nested pattern.
      - `(...) as foo` in Elm
      - Special case: when there is just a variable name in a pattern in Elm it will be represented as a
        `WildcardPattern` wrapped in an `AsPattern`
  - **TuplePattern**
      - Matches on a tuple where each element matches the nested patterns.
  - **ConstructorPattern**
      - Matches on a type constructor and its arguments.
  - **EmptyListPattern**
      - Matches on an empty list.
  - **HeadTailPattern**
      - Matches on the head and the tail of a list.
      - Combined with `EmptyListPattern` it can match on lists of any specific sizes.
  - **LiteralPattern**
      - Matches an an exact literal value.
  - **UnitPattern**
      - Matches the `Unit` value only.

-}
type Pattern a
    = WildcardPattern a
    | AsPattern a (Pattern a) Name
    | TuplePattern a (List (Pattern a))
    | ConstructorPattern a FQName (List (Pattern a))
    | EmptyListPattern a
    | HeadTailPattern a (Pattern a) (Pattern a)
    | LiteralPattern a Literal
    | UnitPattern a


{-| Type that represents a value or function specification. The specification of what the value or function
is without the actual data or logic behind it.
-}
type alias Specification ta =
    { inputs : List ( Name, Type ta )
    , output : Type ta
    }


{-| Type that represents a value or function definition. A definition is the actual data or logic as opposed to a specification
which is just the specification of those. Value definitions can be typed or untyped. Exposed values have to be typed.
-}
type alias Definition ta va =
    { inputTypes : List ( Name, va, Type ta )
    , outputType : Type ta
    , body : Value ta va
    }


{-| Turns a definition into a specification by removing implementation details.
-}
definitionToSpecification : Definition ta va -> Specification ta
definitionToSpecification def =
    { inputs =
        def.inputTypes
            |> List.map
                (\( name, _, tpe ) ->
                    ( name, tpe )
                )
    , output =
        def.outputType
    }


{-| Turn a value definition into a value by wrapping the body value as needed based on the number of arguments the
definition has. For example, if the definition specifies 2 inputs it will wrap the body into 2 lambdas each taking one
argument:

    definitionToValue
        (Definition
            { inputTypes =
                [ ( [ "foo" ], (), intType () )
                , ( [ "bar" ], (), intType () )
                ]
            , outputType =
                intType ()
            , body =
                Tuple () [ Variable () [ "foo" ], Variable () [ "bar" ] ]
            }
        )
    -- Lambda (AsPattern () (WildcardPattern ()) [ "foo" ])
    --     (Lambda (AsPattern () (WildcardPattern ()) [ "bar" ])
    --         (Tuple () [ Variable () [ "foo" ], Variable () [ "bar" ] ])
    --     )

-}
definitionToValue : Definition ta va -> Value ta va
definitionToValue def =
    case def.inputTypes of
        [] ->
            def.body

        ( firstArgName, va, _ ) :: restOfArgs ->
            Lambda va
                (AsPattern va (WildcardPattern va) firstArgName)
                (definitionToValue
                    { def
                        | inputTypes = restOfArgs
                    }
                )


{-| Moves lambda arguments into function arguments as much as possible. For example given this function definition:

    foo : Int -> Bool -> ( Int, Int ) -> String
    foo =
        \a ->
            \b ->
                ( c, d ) ->
                    doSomething a b c d

It turns it into the following:

    foo : Int -> Bool -> ( Int, Int ) -> String
    foo a b =
        ( c, d ) ->
            doSomething a b c d

-}
typeAndValueToDefinition : Type ta -> Value ta va -> Definition ta va
typeAndValueToDefinition valueType value =
    let
        liftLambdaArguments : List ( Name, va, Type ta ) -> Type ta -> Value ta va -> Definition ta va
        liftLambdaArguments args bodyType body =
            case ( body, bodyType ) of
                ( Lambda va (AsPattern _ (WildcardPattern _) argName) lambdaBody, Type.Function _ argType returnType ) ->
                    liftLambdaArguments
                        (List.append args [ ( argName, va, argType ) ])
                        returnType
                        lambdaBody

                _ ->
                    { inputTypes = args
                    , outputType = bodyType
                    , body = body
                    }
    in
    liftLambdaArguments [] valueType value


{-| -}
mapDefinition : (Type ta -> Result e (Type ta)) -> (Value ta va -> Result e (Value ta va)) -> Definition ta va -> Result (List e) (Definition ta va)
mapDefinition mapType mapValue def =
    Result.map3 (\inputTypes outputType body -> Definition inputTypes outputType body)
        (def.inputTypes
            |> List.map
                (\( name, attr, tpe ) ->
                    mapType tpe
                        |> Result.map
                            (\t ->
                                ( name, attr, t )
                            )
                )
            |> ListOfResults.keepAllErrors
        )
        (mapType def.outputType |> Result.mapError List.singleton)
        (mapValue def.body |> Result.mapError List.singleton)


{-| -}
mapSpecificationAttributes : (a -> b) -> Specification a -> Specification b
mapSpecificationAttributes f spec =
    Specification
        (spec.inputs
            |> List.map
                (\( name, tpe ) ->
                    ( name, Type.mapTypeAttributes f tpe )
                )
        )
        (Type.mapTypeAttributes f spec.output)


{-| -}
valueAttribute : Value ta va -> va
valueAttribute v =
    case v of
        Literal a _ ->
            a

        Constructor a _ ->
            a

        Tuple a _ ->
            a

        List a _ ->
            a

        Record a _ ->
            a

        Variable a _ ->
            a

        Reference a _ ->
            a

        Field a _ _ ->
            a

        FieldFunction a _ ->
            a

        Apply a _ _ ->
            a

        Lambda a _ _ ->
            a

        LetDefinition a _ _ _ ->
            a

        LetRecursion a _ _ ->
            a

        Destructure a _ _ _ ->
            a

        IfThenElse a _ _ _ ->
            a

        PatternMatch a _ _ ->
            a

        UpdateRecord a _ _ ->
            a

        Unit a ->
            a


{-| -}
patternAttribute : Pattern a -> a
patternAttribute p =
    case p of
        WildcardPattern a ->
            a

        AsPattern a _ _ ->
            a

        TuplePattern a _ ->
            a

        ConstructorPattern a _ _ ->
            a

        EmptyListPattern a ->
            a

        HeadTailPattern a _ _ ->
            a

        LiteralPattern a _ ->
            a

        UnitPattern a ->
            a


{-| -}
mapValueAttributes : (ta -> tb) -> (va -> vb) -> Value ta va -> Value tb vb
mapValueAttributes f g v =
    case v of
        Literal a value ->
            Literal (g a) value

        Constructor a fullyQualifiedName ->
            Constructor (g a) fullyQualifiedName

        Tuple a elements ->
            Tuple (g a) (elements |> List.map (mapValueAttributes f g))

        List a items ->
            List (g a) (items |> List.map (mapValueAttributes f g))

        Record a fields ->
            Record (g a)
                (fields
                    |> Dict.map
                        (\_ fieldValue ->
                            mapValueAttributes f g fieldValue
                        )
                )

        Variable a name ->
            Variable (g a) name

        Reference a fullyQualifiedName ->
            Reference (g a) fullyQualifiedName

        Field a subjectValue fieldName ->
            Field (g a) (mapValueAttributes f g subjectValue) fieldName

        FieldFunction a fieldName ->
            FieldFunction (g a) fieldName

        Apply a function argument ->
            Apply (g a) (mapValueAttributes f g function) (mapValueAttributes f g argument)

        Lambda a argumentPattern body ->
            Lambda (g a) (mapPatternAttributes g argumentPattern) (mapValueAttributes f g body)

        LetDefinition a valueName valueDefinition inValue ->
            LetDefinition (g a) valueName (mapDefinitionAttributes f g valueDefinition) (mapValueAttributes f g inValue)

        LetRecursion a valueDefinitions inValue ->
            LetRecursion (g a)
                (valueDefinitions
                    |> Dict.map
                        (\_ def ->
                            mapDefinitionAttributes f g def
                        )
                )
                (mapValueAttributes f g inValue)

        Destructure a pattern valueToDestruct inValue ->
            Destructure (g a) (mapPatternAttributes g pattern) (mapValueAttributes f g valueToDestruct) (mapValueAttributes f g inValue)

        IfThenElse a condition thenBranch elseBranch ->
            IfThenElse (g a) (mapValueAttributes f g condition) (mapValueAttributes f g thenBranch) (mapValueAttributes f g elseBranch)

        PatternMatch a branchOutOn cases ->
            PatternMatch (g a)
                (mapValueAttributes f g branchOutOn)
                (cases
                    |> List.map
                        (\( pattern, body ) ->
                            ( mapPatternAttributes g pattern, mapValueAttributes f g body )
                        )
                )

        UpdateRecord a valueToUpdate fieldsToUpdate ->
            UpdateRecord (g a)
                (mapValueAttributes f g valueToUpdate)
                (fieldsToUpdate
                    |> Dict.map
                        (\_ fieldValue ->
                            mapValueAttributes f g fieldValue
                        )
                )

        Unit a ->
            Unit (g a)


{-| -}
mapPatternAttributes : (a -> b) -> Pattern a -> Pattern b
mapPatternAttributes f p =
    case p of
        WildcardPattern a ->
            WildcardPattern (f a)

        AsPattern a p2 name ->
            AsPattern (f a) (mapPatternAttributes f p2) name

        TuplePattern a elementPatterns ->
            TuplePattern (f a) (elementPatterns |> List.map (mapPatternAttributes f))

        ConstructorPattern a constructorName argumentPatterns ->
            ConstructorPattern (f a) constructorName (argumentPatterns |> List.map (mapPatternAttributes f))

        EmptyListPattern a ->
            EmptyListPattern (f a)

        HeadTailPattern a headPattern tailPattern ->
            HeadTailPattern (f a) (mapPatternAttributes f headPattern) (mapPatternAttributes f tailPattern)

        LiteralPattern a value ->
            LiteralPattern (f a) value

        UnitPattern a ->
            UnitPattern (f a)


{-| -}
mapDefinitionAttributes : (ta -> tb) -> (va -> vb) -> Definition ta va -> Definition tb vb
mapDefinitionAttributes f g d =
    Definition
        (d.inputTypes |> List.map (\( name, attr, tpe ) -> ( name, g attr, Type.mapTypeAttributes f tpe )))
        (Type.mapTypeAttributes f d.outputType)
        (mapValueAttributes f g d.body)


{-| Function to traverse a value expression tree bottom-up and apply a function to an accumulator value at each step
to come up with a final value that was derived from the whole tree. It's very similar to a fold but there are a few
differences since it works on a tree instead of a list.

The function takes a lambda that will be invoked on each node with two arguments:

1.  The value node that is currently being processed.
2.  The list of accumulator values returned by the node's children (will be empty in case of a leaf node).

The lambda should calculate and return an accumulator value that will be continuously rolled up to the top of the
expression tree and returned at the root.

This is a very flexible utility function that can be used to do a lot of things by supplying different lambdas.
Here are a few examples:

  - Count the number of nodes: \`reduceValueBottomUp (\_ childCounts -> List.sum childCounts + 1)
  - Get the depth of the tree: `reduceValueBottomUp (\_ childDepths -> (List.maximum childDepths |> Maybe.withDefault 0) + 1)`

These are simple examples that return a single value but you could also use a more complex accumulator value.
For example you could collect things by using a list accumulator or build a new tree.

-}
reduceValueBottomUp : (Value typeAttribute valueAttribute -> List accumulator -> accumulator) -> Value typeAttribute valueAttribute -> accumulator
reduceValueBottomUp mapNode currentValue =
    case currentValue of
        Tuple _ elements ->
            elements
                |> List.map (reduceValueBottomUp mapNode)
                |> mapNode currentValue

        List _ items ->
            items
                |> List.map (reduceValueBottomUp mapNode)
                |> mapNode currentValue

        Record _ fields ->
            fields
                |> Dict.values
                |> List.map (reduceValueBottomUp mapNode)
                |> mapNode currentValue

        Field _ subjectValue _ ->
            mapNode currentValue
                [ reduceValueBottomUp mapNode subjectValue ]

        Apply _ function argument ->
            mapNode currentValue
                [ reduceValueBottomUp mapNode function
                , reduceValueBottomUp mapNode argument
                ]

        Lambda _ _ body ->
            mapNode currentValue
                [ reduceValueBottomUp mapNode body ]

        LetDefinition _ _ _ inValue ->
            mapNode currentValue
                [ reduceValueBottomUp mapNode inValue ]

        LetRecursion _ _ inValue ->
            mapNode currentValue
                [ reduceValueBottomUp mapNode inValue ]

        Destructure _ _ valueToDestruct inValue ->
            mapNode currentValue
                [ reduceValueBottomUp mapNode valueToDestruct
                , reduceValueBottomUp mapNode inValue
                ]

        IfThenElse _ condition thenBranch elseBranch ->
            mapNode currentValue
                [ reduceValueBottomUp mapNode condition
                , reduceValueBottomUp mapNode thenBranch
                , reduceValueBottomUp mapNode elseBranch
                ]

        PatternMatch _ branchOutOn cases ->
            mapNode currentValue
                (cases
                    |> List.map Tuple.second
                    |> List.map (reduceValueBottomUp mapNode)
                    |> List.append [ reduceValueBottomUp mapNode branchOutOn ]
                )

        UpdateRecord _ valueToUpdate fieldsToUpdate ->
            mapNode currentValue
                (fieldsToUpdate
                    |> Dict.values
                    |> List.map (reduceValueBottomUp mapNode)
                    |> List.append [ reduceValueBottomUp mapNode valueToUpdate ]
                )

        _ ->
            mapNode currentValue []


{-| -}
collectValueAttributes : Value ta va -> List va
collectValueAttributes v =
    case v of
        Literal a _ ->
            [ a ]

        Constructor a _ ->
            [ a ]

        Tuple a elements ->
            a :: (elements |> List.concatMap collectValueAttributes)

        List a items ->
            a :: (items |> List.concatMap collectValueAttributes)

        Record a fields ->
            a :: (fields |> Dict.values |> List.concatMap collectValueAttributes)

        Variable a _ ->
            [ a ]

        Reference a _ ->
            [ a ]

        Field a subjectValue _ ->
            a :: collectValueAttributes subjectValue

        FieldFunction a _ ->
            [ a ]

        Apply a function argument ->
            a :: List.concat [ collectValueAttributes function, collectValueAttributes argument ]

        Lambda a argumentPattern body ->
            a :: List.concat [ collectPatternAttributes argumentPattern, collectValueAttributes body ]

        LetDefinition a _ valueDefinition inValue ->
            a :: List.concat [ collectDefinitionAttributes valueDefinition, collectValueAttributes inValue ]

        LetRecursion a valueDefinitions inValue ->
            a
                :: List.append
                    (valueDefinitions
                        |> Dict.toList
                        |> List.concatMap (Tuple.second >> collectDefinitionAttributes)
                    )
                    (collectValueAttributes inValue)

        Destructure a pattern valueToDestruct inValue ->
            a :: List.concat [ collectPatternAttributes pattern, collectValueAttributes valueToDestruct, collectValueAttributes inValue ]

        IfThenElse a condition thenBranch elseBranch ->
            a :: List.concat [ collectValueAttributes condition, collectValueAttributes thenBranch, collectValueAttributes elseBranch ]

        PatternMatch a branchOutOn cases ->
            a
                :: List.append
                    (collectValueAttributes branchOutOn)
                    (cases
                        |> List.concatMap
                            (\( pattern, body ) ->
                                List.concat [ collectPatternAttributes pattern, collectValueAttributes body ]
                            )
                    )

        UpdateRecord a valueToUpdate fieldsToUpdate ->
            a
                :: List.append
                    (collectValueAttributes valueToUpdate)
                    (fieldsToUpdate
                        |> Dict.values
                        |> List.concatMap collectValueAttributes
                    )

        Unit a ->
            [ a ]


{-| -}
countValueNodes : Value ta va -> Int
countValueNodes value =
    value
        |> collectValueAttributes
        |> List.length


{-| -}
collectPatternAttributes : Pattern a -> List a
collectPatternAttributes p =
    case p of
        WildcardPattern a ->
            [ a ]

        AsPattern a p2 _ ->
            a :: collectPatternAttributes p2

        TuplePattern a elementPatterns ->
            a :: (elementPatterns |> List.concatMap collectPatternAttributes)

        ConstructorPattern a _ argumentPatterns ->
            a :: (argumentPatterns |> List.concatMap collectPatternAttributes)

        EmptyListPattern a ->
            [ a ]

        HeadTailPattern a headPattern tailPattern ->
            a :: List.concat [ collectPatternAttributes headPattern, collectPatternAttributes tailPattern ]

        LiteralPattern a _ ->
            [ a ]

        UnitPattern a ->
            [ a ]


{-| -}
collectDefinitionAttributes : Definition ta va -> List va
collectDefinitionAttributes d =
    List.append
        (d.inputTypes |> List.map (\( _, attr, _ ) -> attr))
        (collectValueAttributes d.body)


{-| Collect all variables in a value recursively.
-}
collectVariables : Value ta va -> Set Name
collectVariables value =
    let
        collectUnion : List (Value ta va) -> Set Name
        collectUnion values =
            values
                |> List.map collectVariables
                |> List.foldl Set.union Set.empty
    in
    case value of
        Tuple _ elements ->
            collectUnion elements

        List _ items ->
            collectUnion items

        Record _ fields ->
            collectUnion (Dict.values fields)

        Variable _ name ->
            Set.singleton name

        Field _ subjectValue _ ->
            collectVariables subjectValue

        Apply _ function argument ->
            collectUnion [ function, argument ]

        Lambda _ _ body ->
            collectVariables body

        LetDefinition _ valueName valueDefinition inValue ->
            collectUnion [ valueDefinition.body, inValue ]
                |> Set.insert valueName

        LetRecursion _ valueDefinitions inValue ->
            List.foldl Set.union
                Set.empty
                (valueDefinitions
                    |> Dict.toList
                    |> List.map
                        (\( defName, def ) ->
                            collectVariables def.body
                                |> Set.insert defName
                        )
                    |> List.append [ collectVariables inValue ]
                )

        Destructure _ _ valueToDestruct inValue ->
            collectUnion [ valueToDestruct, inValue ]

        IfThenElse _ condition thenBranch elseBranch ->
            collectUnion [ condition, thenBranch, elseBranch ]

        PatternMatch _ branchOutOn cases ->
            collectUnion (cases |> List.map Tuple.second)
                |> Set.union (collectVariables branchOutOn)

        UpdateRecord _ valueToUpdate fieldsToUpdate ->
            collectUnion (fieldsToUpdate |> Dict.values)
                |> Set.union (collectVariables valueToUpdate)

        _ ->
            Set.empty


{-| Generate a unique name that is not used in the given value
-}
generateUniqueName : Value ta va -> Name
generateUniqueName value =
    let
        existingVariableNames : Set Name
        existingVariableNames =
            collectVariables value

        chars : List (List String)
        chars =
            String.split "" "abcdefghijklmnopqrstuvwxyz" |> List.map List.singleton
    in
    case List.head <| List.filter (\var -> not (Set.member var existingVariableNames)) chars of
        Just name ->
            name

        Nothing ->
            existingVariableNames |> Set.toList |> List.concat


{-| Rewrite "... |> Maybe.map .. |> Maybe.withDefault ..." to a pattern match with a Just and a Nothing branch
-}
rewriteMaybeToPatternMatch : Value ta va -> Value ta va
rewriteMaybeToPatternMatch value =
    value
        |> rewriteValue
            (\val ->
                case val of
                    Apply tpe (Apply _ (Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "with", "default" ] )) defaultValue) (Apply maybetpe (Apply _ (Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "map" ] )) mapLambda) inputMaybe) ->
                        case mapLambda of
                            Lambda _ argPattern bodyValue ->
                                Just <|
                                    PatternMatch tpe
                                        inputMaybe
                                        [ ( ConstructorPattern maybetpe ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] ) [ argPattern ], rewriteMaybeToPatternMatch bodyValue )
                                        , ( ConstructorPattern maybetpe ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ) [], defaultValue )
                                        ]

                            _ ->
                                let
                                    argName =
                                        generateUniqueName mapLambda
                                in
                                Just <|
                                    PatternMatch tpe
                                        inputMaybe
                                        [ ( ConstructorPattern maybetpe ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] ) [ AsPattern tpe (WildcardPattern tpe) argName ], Apply tpe (rewriteMaybeToPatternMatch mapLambda) (Variable tpe argName) )
                                        , ( ConstructorPattern maybetpe ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ) [], defaultValue )
                                        ]

                    _ ->
                        Nothing
            )


{-| Find and replace variables with another value based on the mapping provided.
-}
replaceVariables : Value ta va -> Dict Name.Name (Value ta va) -> Value ta va
replaceVariables value mapping =
    value
        |> rewriteValue
            (\val ->
                case val of
                    Variable _ name ->
                        Just (Dict.get name mapping |> Maybe.withDefault val)

                    _ ->
                        Nothing
            )


{-| Collect all references in a value recursively.
-}
collectReferences : Value ta va -> Set FQName
collectReferences value =
    let
        collectUnion : List (Value ta va) -> Set FQName
        collectUnion values =
            values
                |> List.map collectReferences
                |> List.foldl Set.union Set.empty
    in
    case value of
        Tuple _ elements ->
            collectUnion elements

        List _ items ->
            collectUnion items

        Record _ fields ->
            collectUnion (Dict.values fields)

        Reference _ fQName ->
            Set.singleton fQName

        Field _ subjectValue _ ->
            collectReferences subjectValue

        Apply _ function argument ->
            collectUnion [ function, argument ]

        Lambda _ _ body ->
            collectReferences body

        LetDefinition _ _ valueDefinition inValue ->
            collectUnion [ valueDefinition.body, inValue ]

        LetRecursion _ valueDefinitions inValue ->
            List.foldl Set.union
                Set.empty
                (valueDefinitions
                    |> Dict.toList
                    |> List.map
                        (\( _, def ) ->
                            collectReferences def.body
                        )
                    |> List.append [ collectReferences inValue ]
                )

        Destructure _ _ valueToDestruct inValue ->
            collectUnion [ valueToDestruct, inValue ]

        IfThenElse _ condition thenBranch elseBranch ->
            collectUnion [ condition, thenBranch, elseBranch ]

        PatternMatch _ branchOutOn cases ->
            collectUnion (cases |> List.map Tuple.second)
                |> Set.union (collectReferences branchOutOn)

        UpdateRecord _ valueToUpdate fieldsToUpdate ->
            collectUnion (fieldsToUpdate |> Dict.values)
                |> Set.union (collectReferences valueToUpdate)

        _ ->
            Set.empty


{-| Collect all variables in a pattern.
-}
collectPatternVariables : Pattern va -> Set Name
collectPatternVariables pattern =
    case pattern of
        WildcardPattern _ ->
            Set.empty

        AsPattern _ subject name ->
            collectPatternVariables subject
                |> Set.insert name

        TuplePattern _ elemPatterns ->
            elemPatterns
                |> List.map collectPatternVariables
                |> List.foldl Set.union Set.empty

        ConstructorPattern _ _ argPatterns ->
            argPatterns
                |> List.map collectPatternVariables
                |> List.foldl Set.union Set.empty

        EmptyListPattern _ ->
            Set.empty

        HeadTailPattern _ headPattern tailPattern ->
            Set.union (collectPatternVariables headPattern) (collectPatternVariables tailPattern)

        LiteralPattern _ _ ->
            Set.empty

        UnitPattern _ ->
            Set.empty


{-| Collect all references in a pattern.
-}
collectPatternReferences : Pattern va -> Set FQName
collectPatternReferences pattern =
    case pattern of
        WildcardPattern _ ->
            Set.empty

        AsPattern _ subject _ ->
            collectPatternReferences subject

        TuplePattern _ elemPatterns ->
            elemPatterns
                |> List.map collectPatternReferences
                |> List.foldl Set.union Set.empty

        ConstructorPattern _ fQName argPatterns ->
            argPatterns
                |> List.map collectPatternReferences
                |> List.foldl Set.union Set.empty
                |> Set.insert fQName

        EmptyListPattern _ ->
            Set.empty

        HeadTailPattern _ headPattern tailPattern ->
            Set.union (collectPatternReferences headPattern) (collectPatternReferences tailPattern)

        LiteralPattern _ _ ->
            Set.empty

        UnitPattern _ ->
            Set.empty


{-| Map attributes of a value while supplying an index to the map function. The index is incremented depth first.
-}
indexedMapValue : (Int -> a -> b) -> Int -> Value ta a -> ( Value ta b, Int )
indexedMapValue f baseIndex value =
    case value of
        Literal a lit ->
            ( Literal (f baseIndex a) lit, baseIndex )

        Constructor a fullyQualifiedName ->
            ( Constructor (f baseIndex a) fullyQualifiedName, baseIndex )

        Tuple a elems ->
            let
                ( mappedElems, elemsLastIndex ) =
                    indexedMapListHelp (indexedMapValue f) baseIndex elems
            in
            ( Tuple (f baseIndex a) mappedElems, elemsLastIndex )

        List a values ->
            let
                ( mappedValues, valuesLastIndex ) =
                    indexedMapListHelp (indexedMapValue f) baseIndex values
            in
            ( List (f baseIndex a) mappedValues, valuesLastIndex )

        Record a fields ->
            let
                ( mappedFields, valuesLastIndex ) =
                    indexedMapListHelp
                        (\fieldBaseIndex ( fieldName, fieldValue ) ->
                            let
                                ( mappedFieldValue, lastFieldIndex ) =
                                    indexedMapValue f fieldBaseIndex fieldValue
                            in
                            ( ( fieldName, mappedFieldValue ), lastFieldIndex )
                        )
                        baseIndex
                        (Dict.toList fields)
            in
            ( Record (f baseIndex a) (Dict.fromList mappedFields), valuesLastIndex )

        Variable a name ->
            ( Variable (f baseIndex a) name, baseIndex )

        Reference a fQName ->
            ( Reference (f baseIndex a) fQName, baseIndex )

        Field a subjectValue name ->
            let
                ( mappedSubjectValue, subjectValueLastIndex ) =
                    indexedMapValue f (baseIndex + 1) subjectValue
            in
            ( Field (f baseIndex a) mappedSubjectValue name, subjectValueLastIndex )

        FieldFunction a name ->
            ( FieldFunction (f baseIndex a) name, baseIndex )

        Apply a funValue argValue ->
            let
                ( mappedFunValue, funValueLastIndex ) =
                    indexedMapValue f (baseIndex + 1) funValue

                ( mappedArgValue, argValueLastIndex ) =
                    indexedMapValue f (funValueLastIndex + 1) argValue
            in
            ( Apply (f baseIndex a) mappedFunValue mappedArgValue, argValueLastIndex )

        Lambda a argPattern bodyValue ->
            let
                ( mappedArgPattern, argPatternLastIndex ) =
                    indexedMapPattern f (baseIndex + 1) argPattern

                ( mappedBodyValue, bodyValueLastIndex ) =
                    indexedMapValue f (argPatternLastIndex + 1) bodyValue
            in
            ( Lambda (f baseIndex a) mappedArgPattern mappedBodyValue, bodyValueLastIndex )

        LetDefinition a defName def inValue ->
            let
                ( mappedDefArgs, defArgsLastIndex ) =
                    indexedMapListHelp
                        (\inputBaseIndex ( inputName, inputA, inputType ) ->
                            ( ( inputName, f inputBaseIndex inputA, inputType ), inputBaseIndex )
                        )
                        baseIndex
                        def.inputTypes

                ( mappedDefBody, defBodyLastIndex ) =
                    indexedMapValue f (defArgsLastIndex + 1) def.body

                mappedDef : Definition ta b
                mappedDef =
                    { inputTypes =
                        mappedDefArgs
                    , outputType =
                        def.outputType
                    , body =
                        mappedDefBody
                    }

                ( mappedInValue, inValueLastIndex ) =
                    indexedMapValue f (defBodyLastIndex + 1) inValue
            in
            ( LetDefinition (f baseIndex a) defName mappedDef mappedInValue, inValueLastIndex )

        LetRecursion a defs inValue ->
            let
                ( mappedDefs, defsLastIndex ) =
                    if Dict.isEmpty defs then
                        ( [], baseIndex )

                    else
                        indexedMapListHelp
                            (\defBaseIndex ( defName, def ) ->
                                let
                                    ( mappedDefArgs, defArgsLastIndex ) =
                                        indexedMapListHelp
                                            (\inputBaseIndex ( inputName, inputA, inputType ) ->
                                                ( ( inputName, f inputBaseIndex inputA, inputType ), inputBaseIndex )
                                            )
                                            (defBaseIndex - 1)
                                            def.inputTypes

                                    ( mappedDefBody, defBodyLastIndex ) =
                                        indexedMapValue f (defArgsLastIndex + 1) def.body

                                    mappedDef : Definition ta b
                                    mappedDef =
                                        { inputTypes =
                                            mappedDefArgs
                                        , outputType =
                                            def.outputType
                                        , body =
                                            mappedDefBody
                                        }
                                in
                                ( ( defName, mappedDef ), defBodyLastIndex )
                            )
                            baseIndex
                            (defs |> Dict.toList)

                ( mappedInValue, inValueLastIndex ) =
                    indexedMapValue f (defsLastIndex + 1) inValue
            in
            ( LetRecursion (f baseIndex a) (mappedDefs |> Dict.fromList) mappedInValue, inValueLastIndex )

        Destructure a bindPattern bindValue inValue ->
            let
                ( mappedBindPattern, bindPatternLastIndex ) =
                    indexedMapPattern f (baseIndex + 1) bindPattern

                ( mappedBindValue, bindValueLastIndex ) =
                    indexedMapValue f (bindPatternLastIndex + 1) bindValue

                ( mappedInValue, inValueLastIndex ) =
                    indexedMapValue f (bindValueLastIndex + 1) inValue
            in
            ( Destructure (f baseIndex a) mappedBindPattern mappedBindValue mappedInValue, inValueLastIndex )

        IfThenElse a condValue thenValue elseValue ->
            let
                ( mappedCondValue, condValueLastIndex ) =
                    indexedMapValue f (baseIndex + 1) condValue

                ( mappedThenValue, thenValueLastIndex ) =
                    indexedMapValue f (condValueLastIndex + 1) thenValue

                ( mappedElseValue, elseValueLastIndex ) =
                    indexedMapValue f (thenValueLastIndex + 1) elseValue
            in
            ( IfThenElse (f baseIndex a) mappedCondValue mappedThenValue mappedElseValue, elseValueLastIndex )

        PatternMatch a subjectValue cases ->
            let
                ( mappedSubjectValue, subjectValueLastIndex ) =
                    indexedMapValue f (baseIndex + 1) subjectValue

                ( mappedCases, casesLastIndex ) =
                    indexedMapListHelp
                        (\fieldBaseIndex ( casePattern, caseBody ) ->
                            let
                                ( mappedCasePattern, casePatternLastIndex ) =
                                    indexedMapPattern f fieldBaseIndex casePattern

                                ( mappedCaseBody, caseBodyLastIndex ) =
                                    indexedMapValue f (casePatternLastIndex + 1) caseBody
                            in
                            ( ( mappedCasePattern, mappedCaseBody ), caseBodyLastIndex )
                        )
                        (subjectValueLastIndex + 1)
                        cases
            in
            ( PatternMatch (f baseIndex a) mappedSubjectValue mappedCases, casesLastIndex )

        UpdateRecord a subjectValue fields ->
            let
                ( mappedSubjectValue, subjectValueLastIndex ) =
                    indexedMapValue f (baseIndex + 1) subjectValue

                ( mappedFields, valuesLastIndex ) =
                    indexedMapListHelp
                        (\fieldBaseIndex ( fieldName, fieldValue ) ->
                            let
                                ( mappedFieldValue, lastFieldIndex ) =
                                    indexedMapValue f fieldBaseIndex fieldValue
                            in
                            ( ( fieldName, mappedFieldValue ), lastFieldIndex )
                        )
                        (subjectValueLastIndex + 1)
                        (Dict.toList fields)
            in
            ( UpdateRecord (f baseIndex a) mappedSubjectValue (Dict.fromList mappedFields), valuesLastIndex )

        Unit a ->
            ( Unit (f baseIndex a), baseIndex )


{-| Map attributes of a pattern while supplying an index to the map function. The index is incremented depth first.
-}
indexedMapPattern : (Int -> a -> b) -> Int -> Pattern a -> ( Pattern b, Int )
indexedMapPattern f baseIndex pattern =
    case pattern of
        WildcardPattern a ->
            ( WildcardPattern (f baseIndex a), baseIndex )

        AsPattern a aliasedPattern alias ->
            let
                ( mappedAliasedPattern, lastIndex ) =
                    indexedMapPattern f (baseIndex + 1) aliasedPattern
            in
            ( AsPattern (f baseIndex a) mappedAliasedPattern alias, lastIndex )

        TuplePattern a elemPatterns ->
            let
                ( mappedElemPatterns, elemsLastIndex ) =
                    indexedMapListHelp (indexedMapPattern f) baseIndex elemPatterns
            in
            ( TuplePattern (f baseIndex a) mappedElemPatterns, elemsLastIndex )

        ConstructorPattern a fQName argPatterns ->
            let
                ( mappedArgPatterns, argPatternsLastIndex ) =
                    indexedMapListHelp (indexedMapPattern f) baseIndex argPatterns
            in
            ( ConstructorPattern (f baseIndex a) fQName mappedArgPatterns, argPatternsLastIndex )

        EmptyListPattern a ->
            ( EmptyListPattern (f baseIndex a), baseIndex )

        HeadTailPattern a headPattern tailPattern ->
            let
                ( mappedHeadPattern, lastIndexHeadPattern ) =
                    indexedMapPattern f (baseIndex + 1) headPattern

                ( mappedTailPattern, lastIndexTailPattern ) =
                    indexedMapPattern f (lastIndexHeadPattern + 1) tailPattern
            in
            ( HeadTailPattern (f baseIndex a) mappedHeadPattern mappedTailPattern, lastIndexTailPattern )

        LiteralPattern a lit ->
            ( LiteralPattern (f baseIndex a) lit, baseIndex )

        UnitPattern a ->
            ( UnitPattern (f baseIndex a), baseIndex )


{-| Helper function to `indexMap` a list of nodes in the IR.
-}
indexedMapListHelp : (Int -> a -> ( b, Int )) -> Int -> List a -> ( List b, Int )
indexedMapListHelp f baseIndex elemList =
    elemList
        |> List.foldl
            (\nextElem ( elemsSoFar, lastIndexSoFar ) ->
                let
                    ( mappedElem, lastIndex ) =
                        f (lastIndexSoFar + 1) nextElem
                in
                ( List.append elemsSoFar [ mappedElem ], lastIndex )
            )
            ( [], baseIndex )


{-| Recursively rewrite a value using the supplied mapping function.
-}
rewriteValue : (Value ta va -> Maybe (Value ta va)) -> Value ta va -> Value ta va
rewriteValue f value =
    case f value of
        Just newValue ->
            newValue

        Nothing ->
            case value of
                Tuple va elems ->
                    Tuple va (elems |> List.map (rewriteValue f))

                List va items ->
                    List va (items |> List.map (rewriteValue f))

                Record va fields ->
                    Record va (fields |> Dict.map (\_ v -> rewriteValue f v))

                Field va subject name ->
                    Field va (rewriteValue f subject) name

                Apply va fun arg ->
                    Apply va (rewriteValue f fun) (rewriteValue f arg)

                Lambda va pattern body ->
                    Lambda va pattern (rewriteValue f body)

                LetDefinition va defName def inValue ->
                    LetDefinition va
                        defName
                        { def | body = rewriteValue f def.body }
                        (rewriteValue f inValue)

                LetRecursion va defs inValue ->
                    LetRecursion va
                        (defs |> Dict.map (\_ def -> { def | body = rewriteValue f def.body }))
                        (rewriteValue f inValue)

                Destructure va bindPattern bindValue inValue ->
                    Destructure va
                        bindPattern
                        (rewriteValue f bindValue)
                        (rewriteValue f inValue)

                IfThenElse va condition thenBranch elseBranch ->
                    IfThenElse va
                        (rewriteValue f condition)
                        (rewriteValue f thenBranch)
                        (rewriteValue f elseBranch)

                PatternMatch va subject cases ->
                    PatternMatch va
                        (rewriteValue f subject)
                        (cases |> List.map (\( p, v ) -> ( p, rewriteValue f v )))

                UpdateRecord va subject fields ->
                    UpdateRecord va
                        (rewriteValue f subject)
                        (fields |> Dict.map (\_ v -> rewriteValue f v))

                _ ->
                    value



--rewriteValue : Rewrite e (Value a)
--rewriteValue rewriteBranch rewriteLeaf valueToRewrite =
--    case valueToRewrite of
--        Tuple a elements ->
--            elements
--                |> List.map rewriteBranch
--                |> ResultList.liftLastError
--                |> Result.map (Tuple a)
--
--        List a items ->
--            items
--                |> List.map rewriteBranch
--                |> ResultList.liftLastError
--                |> Result.map (List a)
--
--        Record a fields ->
--            fields
--                |> List.map
--                    (\( fieldName, fieldValue ) ->
--                        rewriteBranch fieldValue
--                            |> Result.map (Tuple.pair fieldName)
--                    )
--                |> ResultList.liftLastError
--                |> Result.map (Record a)
--
--        Field a subjectValue fieldName ->
--            rewriteBranch subjectValue
--                |> Result.map
--                    (\subject ->
--                        Field a subject fieldName
--                    )
--
--        Apply a function argument ->
--            Result.map2 (Apply a)
--                (rewriteBranch function)
--                (rewriteBranch argument)
--
--        Lambda a argumentPattern body ->
--            Lambda (f a) (mapPatternAttributes f argumentPattern) (mapValueAttributes f body)
--
--        LetDefinition a valueName valueDefinition inValue ->
--            LetDefinition (f a) valueName (mapDefinitionAttributes f valueDefinition) (mapValueAttributes f inValue)
--
--        LetRecursion a valueDefinitions inValue ->
--            LetRecursion (f a)
--                (valueDefinitions
--                    |> List.map
--                        (\( name, def ) ->
--                            ( name, mapDefinitionAttributes f def )
--                        )
--                )
--                (mapValueAttributes f inValue)
--
--        Destructure a pattern valueToDestruct inValue ->
--            Destructure (f a) (mapPatternAttributes f pattern) (mapValueAttributes f valueToDestruct) (mapValueAttributes f inValue)
--
--        IfThenElse a condition thenBranch elseBranch ->
--            IfThenElse (f a) (mapValueAttributes f condition) (mapValueAttributes f thenBranch) (mapValueAttributes f elseBranch)
--
--        PatternMatch a branchOutOn cases ->
--            PatternMatch (f a)
--                (mapValueAttributes f branchOutOn)
--                (cases
--                    |> List.map
--                        (\( pattern, body ) ->
--                            ( mapPatternAttributes f pattern, mapValueAttributes f body )
--                        )
--                )
--
--        UpdateRecord a valueToUpdate fieldsToUpdate ->
--            UpdateRecord (f a)
--                (mapValueAttributes f valueToUpdate)
--                (fieldsToUpdate
--                    |> List.map
--                        (\( fieldName, fieldValue ) ->
--                            ( fieldName, mapValueAttributes f fieldValue )
--                        )
--                )
--
--        _ ->
--            rewriteLeaf valueToRewrite


{-| A [literal][lit] represents a fixed value in the IR. We only allow values of basic types: bool, char, string, int, float.

    True -- Literal (BoolLiteral True)

    'a' -- Literal (CharLiteral 'a')

    "foo" -- Literal (StringLiteral "foo")

    13 -- Literal (WholeNumberLiteral 13)

    15.4 -- Literal (FloatLiteral 15.4)

[lit]: https://en.wikipedia.org/wiki/Literal_(computer_programming)

-}
literal : va -> Literal -> Value ta va
literal attributes value =
    Literal attributes value


{-| A reference to a constructor of a custom type.

    Nothing -- Constructor ( ..., [ [ "maybe" ] ], [ "nothing" ] )

    Foo.Bar -- Constructor ( ..., [ [ "foo" ] ], [ "bar" ] )

-}
constructor : va -> FQName -> Value ta va
constructor attributes fullyQualifiedName =
    Constructor attributes fullyQualifiedName


{-| A [tuple] represents an ordered list of values where each value can be of a different type.

**Note**: Tuples with zero values are considered to be the special value [`Unit`](#unit)

    ( 1, True ) -- Tuple [ Literal (WholeNumberLiteral 1), Literal (BoolLiteral True) ]

    ( "foo", True, 3 ) -- Tuple [ Literal (StringLiteral "foo"), Literal (BoolLiteral True), Literal (WholeNumberLiteral 3) ]

    () -- Unit

[tuple]: https://en.wikipedia.org/wiki/Tuple

-}
tuple : va -> List (Value ta va) -> Value ta va
tuple attributes elements =
    Tuple attributes elements


{-| A [list] represents an ordered list of values where every value has to be of the same type.

    [ 1, 3, 5 ] -- List [ Literal (WholeNumberLiteral 1), Literal (WholeNumberLiteral 3), Literal (WholeNumberLiteral 5) ]

    [] -- List []

[list]: https://en.wikipedia.org/wiki/List_(abstract_data_type)

-}
list : va -> List (Value ta va) -> Value ta va
list attributes items =
    List attributes items


{-| A [record] represents a dictionary of fields where the keys are the field names, and the values are the field values

    { foo = "bar" } -- Record [ ( [ "foo" ], Literal (StringLiteral "bar") ) ]

    { foo = "bar", baz = 1 } -- Record [ ( [ "foo" ], Literal (StringLiteral "bar") ), ( [ "baz" ], Literal (WholeNumberLiteral 1) ) ]

    {} -- Record []

[record]: https://en.wikipedia.org/wiki/Record_(computer_science)

-}
record : va -> Dict Name (Value ta va) -> Value ta va
record attributes fields =
    Record attributes fields


{-| A [variable] represents a reference to a named value in the scope.

    a -- Variable [ "a" ]

    fooBar15 -- Variable [ "foo", "bar", "15" ]

[variable]: https://en.wikipedia.org/wiki/Variable_(computer_science)

-}
variable : va -> Name -> Value ta va
variable attributes name =
    Variable attributes name


{-| A reference that refers to a function or a value with its fully-qualified name.

    List.map -- Reference ( [ ..., [ [ "list" ] ], [ "map" ] )

-}
reference : va -> FQName -> Value ta va
reference attributes fullyQualifiedName =
    Reference attributes fullyQualifiedName


{-| Extracts the value of a record's field.

    a.foo -- Field (Variable [ "a" ]) [ "foo" ]

-}
field : va -> Value ta va -> Name -> Value ta va
field attributes subjectValue fieldName =
    Field attributes subjectValue fieldName


{-| Represents a function that extract a field from a record value passed to it.

    .foo -- FieldFunction [ "foo" ]

-}
fieldFunction : va -> Name -> Value ta va
fieldFunction attributes fieldName =
    FieldFunction attributes fieldName


{-| Represents a function invocation. We use currying to represent function invocations with multiple arguments.

**Note**: Operators are mapped to well-known function names.

    not True -- Apply (Reference ( ..., [ [ "basics" ] ], [ "not" ])) (Literal (BoolLiteral True))

    True || False -- Apply (Apply (Reference ( ..., [ [ "basics" ] ], [ "and" ]))) (Literal (BoolLiteral True)) (Literal (BoolLiteral True))

-}
apply : va -> Value ta va -> Value ta va -> Value ta va
apply attributes function argument =
    Apply attributes function argument


{-| Represents a lambda abstraction.

**Note**:

  - We use currying to represent lambda abstractions with multiple arguments.
  - Arguments are not just names, they are patterns.

```
\a -> a -- Lambda (AsPattern WildcardPattern [ "a" ]) (Variable [ "a" ])

\a b -> a -- Lambda (AsPattern WildcardPattern [ "a" ]) (Lambda (AsPattern WildcardPattern [ "b" ]) (Variable [ "a" ]))
```

-}
lambda : va -> Pattern va -> Value ta va -> Value ta va
lambda attributes argumentPattern body =
    Lambda attributes argumentPattern body


{-| Represents a let expression that assigns a value (and optionally type) to a name.

**Note**: We use currying to represent let expressions with multiple name bindings.

    let
        a =
            b
    in
    a
    -- LetDef [ "a" ]
    --     (UntypedDefinition [] (Variable [ "b" ]))
    --     (Variable [ "a" ])

    let
        a : Bool
        a =
            b

        c x =
            a
    in
    c
    -- LetDef [ "a" ]
    --     (TypedDefinition (Basic BoolType) [] (Variable [ "b" ]))
    --     (LetDef [ "c" ]
    --         (UntypedDefinition [ [ "x" ] ] (Variable [ "a" ]))
    --         (Variable [ "c" ])
    --     )

-}
letDef : va -> Name -> Definition ta va -> Value ta va -> Value ta va
letDef attributes valueName valueDefinition inValue =
    LetDefinition attributes valueName valueDefinition inValue


{-| Represents a let expression with one or many recursive definitions.

    let
        a =
            b

        b =
            a
    in
    a
    -- LetRec
    --     [ ( [ "a" ], UntypedDefinition [] (Variable [ "b" ]) )
    --     , ( [ "b" ], UntypedDefinition [] (Variable [ "a" ]) )
    --     ]
    --     (Variable [ "a" ])

-}
letRec : va -> Dict Name (Definition ta va) -> Value ta va -> Value ta va
letRec attributes valueDefinitions inValue =
    LetRecursion attributes valueDefinitions inValue


{-| Represents a let expression that extracts values using a pattern.

    let
        ( a, b ) =
            c
    in
    a
    -- LetDestruct
    --     (TuplePattern [ AsPattern WildcardPattern ["a"], AsPattern WildcardPattern ["b"] ])
    --     (Variable ["a"])

-}
letDestruct : va -> Pattern va -> Value ta va -> Value ta va -> Value ta va
letDestruct attributes pattern valueToDestruct inValue =
    Destructure attributes pattern valueToDestruct inValue


{-| Represents and if/then/else expression.

    if a then
        b
    else
        c
    -- IfThenElse (Variable ["a"])
    --     (Variable ["b"])
    --     (Variable ["c"])

-}
ifThenElse : va -> Value ta va -> Value ta va -> Value ta va -> Value ta va
ifThenElse attributes condition thenBranch elseBranch =
    IfThenElse attributes condition thenBranch elseBranch


{-| Represents a pattern-match.

    case a of
        1 ->
            "yea"

        _ ->
            "nay"
    -- PatternMatch (Variable ["a"])
    --     [ ( LiteralPattern (WholeNumberLiteral 1), Literal (StringLiteral "yea") )
    --     , ( WildcardPattern, Literal (StringLiteral "nay") )
    --     ]

-}
patternMatch : va -> Value ta va -> List ( Pattern va, Value ta va ) -> Value ta va
patternMatch attributes branchOutOn cases =
    PatternMatch attributes branchOutOn cases


{-| Update one or many fields of a record value.

    { a | foo = 1 } -- Update (Variable ["a"]) [ ( ["foo"], Literal (WholeNumberLiteral 1) ) ]

-}
update : va -> Value ta va -> Dict Name (Value ta va) -> Value ta va
update attributes valueToUpdate fieldsToUpdate =
    UpdateRecord attributes valueToUpdate fieldsToUpdate


{-| Represents the unit value.

    () -- Unit

-}
unit : va -> Value ta va
unit attributes =
    Unit attributes


{-| Matches any value and ignores it (assigns no variable name).

    _ -- WildcardPattern

-}
wildcardPattern : a -> Pattern a
wildcardPattern attributes =
    WildcardPattern attributes


{-| Assigns a variable name to a pattern.

    _ as foo -- AsPattern WildcardPattern ["foo"]

    foo -- AsPattern WildcardPattern ["foo"]

    [] as foo -- AsPattern EmptyListPattern ["foo"]

-}
asPattern : a -> Pattern a -> Name -> Pattern a
asPattern attributes pattern name =
    AsPattern attributes pattern name


{-| Destructures a tuple using a pattern for every element.

    ( _, foo ) -- TuplePattern [ WildcardPattern, AsPattern WildcardPattern ["foo"] ]

-}
tuplePattern : a -> List (Pattern a) -> Pattern a
tuplePattern attributes elementPatterns =
    TuplePattern attributes elementPatterns


{-| Matches on a custom type's constructor.

**Note**: When the custom type has a single constructor this can be used for destructuring.
When there are multiple constructors it also does filtering so it cannot be used in a
[`LetDestruct`](#letDestruct) but it can be used in a [pattern-match](#patternMatch).

    Just _ -- ConstructorPattern ( ..., [["maybe"]], ["just"]) [ WildcardPattern ]

-}
constructorPattern : a -> FQName -> List (Pattern a) -> Pattern a
constructorPattern attributes constructorName argumentPatterns =
    ConstructorPattern attributes constructorName argumentPatterns


{-| Matches an empty list. Can be used standalon but frequently used as a terminal pattern
in a [`HeadTailPattern`](#headTailPattern).

    [] -- EmptyListPattern

    [ _ ]
    -- HeadTailPattern
    --     WildcardPattern
    --     EmptyListPattern

-}
emptyListPattern : a -> Pattern a
emptyListPattern attributes =
    EmptyListPattern attributes


{-| Matches the head and the tail of a list. It can be used to match lists of at least N items
by nesting this pattern N times and terminating with [`EmptyListPattern`](#emptyListPattern).

    [ a ]
    -- HeadTailPattern
    --     (AsPattern WildcardPattern ["a"])
    --     EmptyListPattern

    a :: b
    -- HeadTailPattern
    --     (AsPattern WildcardPattern ["a"])
    --     (AsPattern WildcardPattern ["b"])

    [ a, b ]
    -- HeadTailPattern
    --     (AsPattern WildcardPattern ["a"])
    --     (HeadTailPattern
    --         (AsPattern WildcardPattern ["b"])
    --         EmptyListPattern
    --     )

-}
headTailPattern : a -> Pattern a -> Pattern a -> Pattern a
headTailPattern attributes headPattern tailPattern =
    HeadTailPattern attributes headPattern tailPattern


{-| Matches a specific literal value. This pattern can only be used in a [pattern-match](#patternMatch)
since it always filters.

    True -- LiteralPattern (BoolLiteral True)

    'a' -- LiteralPattern (CharLiteral 'a')

    "foo" -- LiteralPattern (StringLiteral "foo")

    13 -- LiteralPattern (WholeNumberLiteral 13)

    15.4 -- LiteralPattern (FloatLiteral 15.4)

-}
literalPattern : a -> Literal -> Pattern a
literalPattern attributes value =
    LiteralPattern attributes value


{-| Extract the argument list from a curried apply tree. It takes the two arguments of an apply and returns a tuple of
the function and a list of arguments.

    uncurryApply (Apply () f a) b == ( f, [ a, b ] )

-}
uncurryApply : Value ta va -> Value ta va -> ( Value ta va, List (Value ta va) )
uncurryApply fun lastArg =
    case fun of
        Apply _ nestedFun nestedArg ->
            let
                ( f, initArgs ) =
                    uncurryApply nestedFun nestedArg
            in
            ( f, List.append initArgs [ lastArg ] )

        _ ->
            ( fun, [ lastArg ] )


{-| Check if the value has any logic in it all is all just data.
-}
isData : Value ta va -> Bool
isData value =
    case value of
        Literal _ _ ->
            True

        Constructor _ _ ->
            True

        Tuple _ elems ->
            List.all isData elems

        List _ items ->
            List.all isData items

        Record _ fields ->
            fields
                |> Dict.values
                |> List.all isData

        Apply _ fun arg ->
            -- most Apply nodes will be logic but if it's a Constructor with arguments it is still considered data
            isData fun && isData arg

        Unit _ ->
            True

        _ ->
            -- everything else is considered logic
            False


{-| Simple string version of a value tree. The output is mostly compatible with the Elm syntax except where Elm uses
indentation to separate values. This representation uses semicolons in those places.
-}
toString : Value ta va -> String
toString value =
    let
        literalToString : Literal -> String
        literalToString lit =
            case lit of
                BoolLiteral bool ->
                    if bool then
                        "True"

                    else
                        "False"

                CharLiteral char ->
                    String.concat [ "'", String.fromChar char, "'" ]

                StringLiteral string ->
                    String.concat [ "\"", string, "\"" ]

                WholeNumberLiteral int ->
                    String.fromInt int

                FloatLiteral float ->
                    String.fromFloat float

                DecimalLiteral decimal ->
                    Decimal.toString decimal


        patternToString : Pattern va -> String
        patternToString pattern =
            case pattern of
                WildcardPattern _ ->
                    "_"

                AsPattern _ (WildcardPattern _) alias ->
                    Name.toCamelCase alias

                AsPattern _ subjectPattern alias ->
                    String.concat [ patternToString subjectPattern, " as ", Name.toCamelCase alias ]

                TuplePattern _ elems ->
                    String.concat [ "( ", elems |> List.map patternToString |> String.join ", ", " )" ]

                ConstructorPattern _ ( packageName, moduleName, localName ) argPatterns ->
                    let
                        constructorString : String
                        constructorString =
                            String.join "."
                                [ Path.toString Name.toTitleCase "." packageName
                                , Path.toString Name.toTitleCase "." moduleName
                                , Name.toTitleCase localName
                                ]
                    in
                    String.join " " (constructorString :: (argPatterns |> List.map patternToString))

                EmptyListPattern _ ->
                    "[]"

                HeadTailPattern _ headPattern tailPattern ->
                    String.concat [ patternToString headPattern, " :: ", patternToString tailPattern ]

                LiteralPattern _ lit ->
                    literalToString lit

                UnitPattern _ ->
                    "()"

        valueToString : Value ta va -> String
        valueToString v =
            case v of
                Literal _ lit ->
                    literalToString lit

                Constructor _ ( packageName, moduleName, localName ) ->
                    String.join "."
                        [ Path.toString Name.toTitleCase "." packageName
                        , Path.toString Name.toTitleCase "." moduleName
                        , Name.toTitleCase localName
                        ]

                Tuple _ elems ->
                    String.concat [ "( ", elems |> List.map toString |> String.join ", ", " )" ]

                List _ items ->
                    String.concat [ "[ ", items |> List.map toString |> String.join ", ", " ]" ]

                Record _ fields ->
                    String.concat
                        [ "{ "
                        , fields
                            |> Dict.toList
                            |> List.map
                                (\( fieldName, fieldValue ) ->
                                    String.concat [ Name.toCamelCase fieldName, " = ", toString fieldValue ]
                                )
                            |> String.join ", "
                        , " }"
                        ]

                Variable _ name ->
                    Name.toCamelCase name

                Reference _ ( packageName, moduleName, localName ) ->
                    String.join "."
                        [ Path.toString Name.toTitleCase "." packageName
                        , Path.toString Name.toTitleCase "." moduleName
                        , Name.toCamelCase localName
                        ]

                Field _ subject fieldName ->
                    String.join "."
                        [ valueToString subject
                        , Name.toCamelCase fieldName
                        ]

                FieldFunction _ fieldName ->
                    String.concat [ ".", Name.toCamelCase fieldName ]

                Apply _ fun arg ->
                    String.join " " [ toString fun, toString arg ]

                Lambda _ argPattern body ->
                    String.concat [ "(\\", patternToString argPattern, " -> ", valueToString body, ")" ]

                LetDefinition _ name def inValue ->
                    let
                        args : List String
                        args =
                            def.inputTypes
                                |> List.map (\( argName, _, _ ) -> Name.toCamelCase argName)
                    in
                    String.concat [ "let ", Name.toCamelCase name, String.join " " args, " = ", valueToString def.body, " in ", valueToString inValue ]

                LetRecursion _ defs inValue ->
                    let
                        args : Definition ta va -> List String
                        args def =
                            def.inputTypes
                                |> List.map (\( argName, _, _ ) -> Name.toCamelCase argName)

                        defStrings : List String
                        defStrings =
                            defs
                                |> Dict.toList
                                |> List.map
                                    (\( name, def ) ->
                                        String.concat [ Name.toCamelCase name, String.join " " (args def), " = ", valueToString def.body ]
                                    )
                    in
                    String.concat [ "let ", String.join "; " defStrings, " in ", valueToString inValue ]

                Destructure _ bindPattern bindValue inValue ->
                    String.concat [ "let ", patternToString bindPattern, " = ", valueToString bindValue, " in ", valueToString inValue ]

                IfThenElse _ cond thenBranch elseBranch ->
                    String.concat [ "if ", valueToString cond, " then ", valueToString thenBranch, " else ", valueToString elseBranch ]

                PatternMatch _ subject cases ->
                    String.concat
                        [ "case "
                        , valueToString subject
                        , " of "
                        , cases
                            |> List.map
                                (\( casePattern, caseBody ) ->
                                    String.concat [ patternToString casePattern, " -> ", valueToString caseBody ]
                                )
                            |> String.join "; "
                        ]

                UpdateRecord _ subject fields ->
                    String.concat
                        [ "{ "
                        , valueToString subject
                        , " | "
                        , fields
                            |> Dict.toList
                            |> List.map
                                (\( fieldName, fieldValue ) ->
                                    String.concat [ Name.toCamelCase fieldName, " = ", toString fieldValue ]
                                )
                            |> String.join ", "
                        , " }"
                        ]

                Unit _ ->
                    "()"
    in
    valueToString value
