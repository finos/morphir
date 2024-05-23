module Morphir.Type.Infer exposing (..)

import Dict exposing (Dict)
import Morphir.Compiler as Compiler
import Morphir.IR.AccessControlled exposing (AccessControlled)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Basics exposing (floatType)
import Morphir.IR.Type as Type exposing (Specification(..), Type)
import Morphir.IR.Value as Value exposing (Pattern(..), Value)
import Morphir.SDK.ResultList as ListOfResults
import Morphir.Type.Class as Class exposing (Class)
import Morphir.Type.Constraint exposing (Constraint(..), class, equality, isRecursive)
import Morphir.Type.ConstraintSet as ConstraintSet exposing (ConstraintSet(..))
import Morphir.Type.Count as Count exposing (Count)
import Morphir.Type.MetaType as MetaType exposing (MetaType(..), Variable, metaClosedRecord, metaFun, metaOpenRecord, metaTuple, metaUnit, metaVar)
import Morphir.Type.MetaTypeMapping exposing (LookupError(..), concreteTypeToMetaType, lookupConstructor, lookupValue, metaTypeToConcreteType)
import Morphir.Type.Solve as Solve exposing (SolutionMap(..), UnificationError(..), UnificationErrorType(..))
import Set exposing (Set)


type alias TypedValue va =
    Value () ( va, Type () )


type ValueTypeError
    = ValueTypeError Name TypeError


type TypeError
    = TypeErrors (List TypeError)
    | ClassConstraintViolation MetaType Class
    | RecursiveConstraint MetaType MetaType
    | LookupError LookupError
    | UnknownError String
    | UnifyError UnificationError


inferPackageDefinition : Distribution -> Package.Definition () va -> Result (List Compiler.Error) (Package.Definition () ( va, Type () ))
inferPackageDefinition refs packageDef =
    packageDef.modules
        |> Dict.toList
        |> List.map
            (\( moduleName, moduleDef ) ->
                inferModuleDefinition refs moduleName moduleDef.value
                    |> Result.map (AccessControlled moduleDef.access)
                    |> Result.map (Tuple.pair moduleName)
            )
        |> ListOfResults.keepAllErrors
        |> Result.map
            (\mappedModules ->
                { modules = Dict.fromList mappedModules
                }
            )


inferModuleDefinition : Distribution -> ModuleName -> Module.Definition () va -> Result Compiler.Error (Module.Definition () ( va, Type () ))
inferModuleDefinition refs moduleName moduleDef =
    moduleDef.values
        |> Dict.toList
        |> List.map
            (\( valueName, valueDef ) ->
                --let
                --    _ =
                --        Debug.log
                --            (String.concat [ "Inferring types for ", moduleName |> Path.toString Name.toTitleCase ".", ".", valueName |> Name.toCamelCase, " of size" ])
                --            (valueDef.value.value.body |> Value.countValueNodes)
                --in
                inferValueDefinition refs valueDef.value.value
                    |> Result.map (Documented valueDef.value.doc)
                    |> Result.map (AccessControlled valueDef.access)
                    |> Result.map (Tuple.pair valueName)
                    |> Result.mapError
                        (\typeError ->
                            Compiler.ErrorInSourceFile
                                (String.concat [ "Type error in value '", Name.toCamelCase valueName, "': ", typeErrorToMessage typeError ])
                                []
                        )
            )
        |> ListOfResults.keepAllErrors
        |> Result.map
            (\mappedValues ->
                { types = moduleDef.types
                , values = Dict.fromList mappedValues
                , doc = moduleDef.doc
                }
            )
        |> Result.mapError (Compiler.ErrorsInSourceFile (moduleName |> Path.toString Name.toTitleCase "."))


typeErrorToMessage : TypeError -> String
typeErrorToMessage typeError =
    case typeError of
        TypeErrors errors ->
            String.concat [ "Multiple errors: ", errors |> List.map typeErrorToMessage |> String.join ", " ]

        ClassConstraintViolation metaType class ->
            String.concat [ "Type '", MetaType.toString metaType, "' is not a ", Class.toString class ]

        LookupError lookupError ->
            case lookupError of
                CouldNotFindConstructor fQName ->
                    String.concat [ "Could not find constructor: ", FQName.toString fQName ]

                CouldNotFindValue fQName ->
                    String.concat [ "Could not find value: ", FQName.toString fQName ]

                CouldNotFindAlias fQName ->
                    String.concat [ "Could not find alias: ", FQName.toString fQName ]

                ExpectedAlias fQName ->
                    String.concat [ "Expected alias at: ", FQName.toString fQName ]

        UnknownError message ->
            String.concat [ "Unknown error: ", message ]

        UnifyError unificationError ->
            let
                mapUnificationError uniError =
                    case uniError of
                        CouldNotUnify errorType metaType1 metaType2 ->
                            let
                                cause =
                                    case errorType of
                                        NoUnificationRule ->
                                            "there are no unification rules to apply"

                                        TuplesOfDifferentSize ->
                                            "they are tuples of different sizes"

                                        RefMismatch ->
                                            "the references do not match"

                                        FieldMismatch ->
                                            "the fields don't match"
                            in
                            String.concat
                                [ "Could not unify '", MetaType.toString metaType1, "' with '", MetaType.toString metaType2, "' because ", cause ]

                        UnificationErrors unificationErrors ->
                            unificationErrors
                                |> List.map mapUnificationError
                                |> String.join ". "

                        CouldNotFindField name ->
                            String.concat
                                [ "Could not find field '", Name.toCamelCase name, "'" ]
            in
            mapUnificationError unificationError

        RecursiveConstraint metaType1 metaType2 ->
            String.concat [ "Recursive constraint: '", MetaType.toString metaType1, "' == '", MetaType.toString metaType2, "'" ]


inferValueDefinition : Distribution -> Value.Definition () va -> Result TypeError (Value.Definition () ( va, Type () ))
inferValueDefinition ir def =
    let
        ( count, ( defVar, annotatedDef, ( constraints, typeVarToIndex ) ) ) =
            constrainDefinition ir Dict.empty def
                |> Count.apply 0

        solution : Result TypeError ( ConstraintSet, SolutionMap )
        solution =
            solve ir constraints
    in
    solution
        |> Result.map (applySolutionToAnnotatedDefinition ir typeVarToIndex annotatedDef)


inferValue : Distribution -> Value () va -> Result TypeError (TypedValue va)
inferValue ir untypedValue =
    let
        ( count, ( annotatedValue, constraints ) ) =
            constrainValue ir Dict.empty Nothing untypedValue
                |> Count.apply 0

        solution : Result TypeError ( ConstraintSet, SolutionMap )
        solution =
            solve ir constraints
    in
    solution
        |> Result.map (applySolutionToAnnotatedValue ir annotatedValue)


{-| Takes an untyped value definition as an input and returns the same value definition annotated with meta type
variables and a set of type constraints that refer to those variables.

Detailed description of inputs and outputs:

    - Input
        - `IR` - used to resolve references to other types and values
        - `Dict Name Variable` - dictionary that assigns a meta type variable to each variable in the scope
        - `Value.Definition () va` - untyped value definition with an arbitrary attribute that will be retained
    - Output
        - `Count` - utility to allow generating a unique id for (counting) specific value nodes
        - `Variable` - meta type variable that refers to this definition. This is required because a value definition
        does not have it's own annotations so it cannot be returned as part of the value definition.
        - `Value.Definition () ( va, Variable )` - value definition that retains the attribute that was passed in and
        adds a meta type variable to each value node
        - `ConstraintSet` - set of type constraints that use the meta type variables that were added to each value node

-}
constrainDefinition : Distribution -> Dict Name Variable -> Value.Definition () va -> Count ( Variable, Value.Definition () ( va, Variable ), ( ConstraintSet, Dict Name Variable ) )
constrainDefinition ir vars def =
    let
        -- collect the names of all the type variables in all the input types
        inputTypeVars : Set Name
        inputTypeVars =
            def.inputTypes
                |> List.map
                    (\( _, _, declaredType ) ->
                        Type.collectVariables declaredType
                    )
                |> List.foldl Set.union Set.empty

        -- collect the names of all the type variables in the output type
        outputTypeVars : Set Name
        outputTypeVars =
            Type.collectVariables def.outputType

        -- assign a meta type variable to each type variable
        countTypeVarToMetaTypeVar : Count (Dict Name Variable)
        countTypeVarToMetaTypeVar =
            Set.union inputTypeVars outputTypeVars
                |> Set.toList
                |> List.map
                    (\varName ->
                        Count.one
                            (\varIndex ->
                                ( varName, MetaType.variableByIndex varIndex )
                            )
                    )
                |> Count.all
                |> Count.map Dict.fromList
    in
    countTypeVarToMetaTypeVar
        |> Count.andThen
            (\typeVarToMetaTypeVar ->
                def.inputTypes
                    |> List.map
                        (\( argName, va, declaredArgType ) ->
                            Count.map2
                                (\argTypeVar argMetaType ->
                                    ( argName
                                    , ( va, argTypeVar )
                                    , ( declaredArgType
                                      , ConstraintSet.singleton (equality (metaVar argTypeVar) argMetaType)
                                      )
                                    )
                                )
                                (Count.one MetaType.variableByIndex)
                                (concreteTypeToMetaType ir typeVarToMetaTypeVar declaredArgType)
                        )
                    |> Count.all
                    |> Count.andThen
                        (\argResults ->
                            concreteTypeToMetaType ir typeVarToMetaTypeVar def.outputType
                                |> Count.andThen
                                    (\outputMetaType ->
                                        let
                                            inputVars : Dict Name Variable
                                            inputVars =
                                                argResults
                                                    |> List.map
                                                        (\( name, ( _, argTypeVar ), _ ) ->
                                                            ( name, argTypeVar )
                                                        )
                                                    |> Dict.fromList
                                        in
                                        constrainValue ir (vars |> Dict.union inputVars) Nothing def.body
                                            |> Count.andThen
                                                (\( annotatedBody, bodyConstraints ) ->
                                                    Count.one
                                                        (\defIndex ->
                                                            let
                                                                annotatedInputTypes : List ( Name, ( va, Variable ), Type () )
                                                                annotatedInputTypes =
                                                                    argResults
                                                                        |> List.map
                                                                            (\( argName, ( va, argTypeVar ), ( declaredArgType, _ ) ) ->
                                                                                ( argName, ( va, argTypeVar ), declaredArgType )
                                                                            )

                                                                defTypeVar : Variable
                                                                defTypeVar =
                                                                    MetaType.variableByIndex defIndex

                                                                inputConstraints : ConstraintSet
                                                                inputConstraints =
                                                                    argResults
                                                                        |> List.map
                                                                            (\( _, _, ( _, argConstraints ) ) ->
                                                                                argConstraints
                                                                            )
                                                                        |> ConstraintSet.concat

                                                                outputConstraint : ConstraintSet
                                                                outputConstraint =
                                                                    ConstraintSet.singleton
                                                                        (equality
                                                                            (metaTypeVarForValue annotatedBody)
                                                                            outputMetaType
                                                                        )

                                                                defType : List MetaType -> MetaType -> MetaType
                                                                defType argTypes returnType =
                                                                    case argTypes of
                                                                        [] ->
                                                                            returnType

                                                                        firstArg :: restOfArgs ->
                                                                            metaFun firstArg (defType restOfArgs returnType)

                                                                defConstraints : ConstraintSet
                                                                defConstraints =
                                                                    ConstraintSet.fromList
                                                                        [ equality
                                                                            (metaVar defTypeVar)
                                                                            (defType
                                                                                (annotatedInputTypes |> List.map (\( _, ( _, argTypeVar ), _ ) -> metaVar argTypeVar))
                                                                                (metaTypeVarForValue annotatedBody)
                                                                            )
                                                                        ]
                                                            in
                                                            ( defTypeVar
                                                            , { inputTypes = annotatedInputTypes
                                                              , outputType = def.outputType
                                                              , body = annotatedBody
                                                              }
                                                            , ( ConstraintSet.concat
                                                                    [ bodyConstraints
                                                                    , inputConstraints
                                                                    , outputConstraint
                                                                    , defConstraints
                                                                    ]
                                                              , typeVarToMetaTypeVar
                                                              )
                                                            )
                                                        )
                                                )
                                    )
                        )
            )


{-| Takes an untyped value as an input and returns the same value annotated with meta type variables and a set of type
constraints that refer to those variables.

Detailed description of inputs and outputs:

    - Input
        - `IR` - used to resolve references to other types and values
        - `Dict Name Variable` - dictionary that assigns a meta type variable to each variable in the scope
        - `Value () va` - untyped value with an arbitrary attribute that will be retained
    - Output
        - `Count` - utility to allow generating a unique id for (counting) specific value nodes
        - `Value () ( va, Variable )` - value that retains the attribute that was passed in and adds a meta type
        variable to each value node
        - `ConstraintSet` - set of type constraints that use the meta type variables that were added to each value node

-}
constrainValue : Distribution -> Dict Name Variable -> Maybe Variable -> Value () va -> Count ( Value () ( va, Variable ), ConstraintSet )
constrainValue ir vars maybeThisTypeVar annotatedValue =
    case annotatedValue of
        Value.Literal va literalValue ->
            Count.oneOrReuse maybeThisTypeVar
                (\thisIndex ->
                    let
                        thisTypeVar : Variable
                        thisTypeVar =
                            MetaType.variableByIndex thisIndex
                    in
                    ( Value.Literal ( va, thisTypeVar ) literalValue
                    , constrainLiteral thisTypeVar literalValue
                    )
                )

        Value.Constructor va fQName ->
            case lookupConstructor ir fQName of
                Ok countedConstructorType ->
                    countedConstructorType
                        |> Count.andThen
                            (\referenceType ->
                                Count.oneOrReuse maybeThisTypeVar
                                    (\thisIndex ->
                                        let
                                            thisTypeVar : Variable
                                            thisTypeVar =
                                                MetaType.variableByIndex thisIndex
                                        in
                                        ( Value.Constructor ( va, thisTypeVar ) fQName
                                        , ConstraintSet.singleton (equality (metaVar thisTypeVar) referenceType)
                                        )
                                    )
                            )

                Err _ ->
                    Count.oneOrReuse maybeThisTypeVar
                        (\thisIndex ->
                            let
                                thisTypeVar : Variable
                                thisTypeVar =
                                    MetaType.variableByIndex thisIndex
                            in
                            ( Value.Constructor ( va, thisTypeVar ) fQName
                            , ConstraintSet.empty
                            )
                        )

        Value.Tuple va elems ->
            elems
                |> List.map (constrainValue ir vars Nothing)
                |> Count.all
                |> Count.andThen
                    (\elemResults ->
                        Count.oneOrReuse maybeThisTypeVar
                            (\thisIndex ->
                                let
                                    thisTypeVar : Variable
                                    thisTypeVar =
                                        MetaType.variableByIndex thisIndex

                                    annotatedElems : List (Value () ( va, Variable ))
                                    annotatedElems =
                                        elemResults
                                            |> List.map (\( annotatedElem, _ ) -> annotatedElem)

                                    elemsConstraints : List ConstraintSet
                                    elemsConstraints =
                                        elemResults
                                            |> List.map (\( _, elemConstraints ) -> elemConstraints)

                                    tupleConstraint : ConstraintSet
                                    tupleConstraint =
                                        ConstraintSet.singleton
                                            (equality
                                                (metaVar thisTypeVar)
                                                (annotatedElems
                                                    |> List.map metaTypeVarForValue
                                                    |> metaTuple
                                                )
                                            )
                                in
                                ( Value.Tuple ( va, thisTypeVar ) annotatedElems
                                , ConstraintSet.concat (tupleConstraint :: elemsConstraints)
                                )
                            )
                    )

        Value.List va items ->
            Count.oneOrReuse maybeThisTypeVar
                (\thisIndex ->
                    let
                        thisTypeVar : Variable
                        thisTypeVar =
                            MetaType.variableByIndex thisIndex
                    in
                    Count.one
                        (\itemIndex ->
                            let
                                itemTypeVar : Variable
                                itemTypeVar =
                                    MetaType.variableByIndex itemIndex

                                itemType : MetaType
                                itemType =
                                    metaVar itemTypeVar
                            in
                            items
                                |> List.map (constrainValue ir vars (Just itemTypeVar))
                                |> Count.all
                                |> Count.map
                                    (\itemResults ->
                                        let
                                            listConstraint : Constraint
                                            listConstraint =
                                                equality (metaVar thisTypeVar) (MetaType.listType itemType)

                                            annotatedItems : List (Value () ( va, Variable ))
                                            annotatedItems =
                                                itemResults
                                                    |> List.map (\( annotatedItem, _ ) -> annotatedItem)

                                            itemsConstraints : ConstraintSet
                                            itemsConstraints =
                                                itemResults
                                                    |> List.map
                                                        (\( annotatedItem, itemConstraints ) ->
                                                            itemConstraints
                                                                |> ConstraintSet.insert (equality itemType (metaTypeVarForValue annotatedItem))
                                                        )
                                                    |> ConstraintSet.concat
                                        in
                                        ( Value.List ( va, thisTypeVar ) annotatedItems
                                        , itemsConstraints
                                            |> ConstraintSet.insert listConstraint
                                        )
                                    )
                        )
                )
                |> Count.andThen identity
                |> Count.andThen identity

        Value.Record va fieldValues ->
            fieldValues
                |> Dict.toList
                |> List.map
                    (\( fieldName, fieldValue ) ->
                        constrainValue ir vars Nothing fieldValue
                            |> Count.map (Tuple.pair fieldName)
                    )
                |> Count.all
                |> Count.andThen
                    (\fieldResults ->
                        Count.two
                            (\thisIndex recordIndex ->
                                let
                                    thisTypeVar : Variable
                                    thisTypeVar =
                                        MetaType.variableByIndex thisIndex

                                    annotatedFieldValues : Dict Name (Value () ( va, Variable ))
                                    annotatedFieldValues =
                                        fieldResults
                                            |> List.map (\( fieldName, ( annotatedFieldValue, _ ) ) -> ( fieldName, annotatedFieldValue ))
                                            |> Dict.fromList

                                    fieldConstraints : ConstraintSet
                                    fieldConstraints =
                                        fieldResults
                                            |> List.map (\( _, ( _, fieldValueConstraints ) ) -> fieldValueConstraints)
                                            |> ConstraintSet.concat

                                    recordType : MetaType
                                    recordType =
                                        fieldResults
                                            |> List.map (\( fieldName, ( annotatedFieldValue, _ ) ) -> ( fieldName, metaTypeVarForValue annotatedFieldValue ))
                                            |> Dict.fromList
                                            |> metaClosedRecord (MetaType.variableByIndex recordIndex)

                                    recordConstraints : ConstraintSet
                                    recordConstraints =
                                        ConstraintSet.singleton
                                            (equality (metaVar thisTypeVar) recordType)
                                in
                                ( Value.Record ( va, thisTypeVar ) annotatedFieldValues
                                , ConstraintSet.concat
                                    [ fieldConstraints
                                    , recordConstraints
                                    ]
                                )
                            )
                    )

        Value.Variable va varName ->
            case vars |> Dict.get varName of
                Just varDecl ->
                    Count.none
                        ( Value.Variable ( va, varDecl ) varName
                        , ConstraintSet.empty
                        )

                Nothing ->
                    -- this should never happen if variables were validated earlier
                    Count.oneOrReuse maybeThisTypeVar
                        (\thisIndex ->
                            let
                                thisTypeVar : Variable
                                thisTypeVar =
                                    MetaType.variableByIndex thisIndex
                            in
                            ( Value.Variable ( va, thisTypeVar ) varName
                            , ConstraintSet.empty
                            )
                        )

        Value.Reference va fQName ->
            case lookupValue ir fQName of
                Ok countedReferenceType ->
                    countedReferenceType
                        |> Count.andThen
                            (\referenceType ->
                                Count.oneOrReuse maybeThisTypeVar
                                    (\thisIndex ->
                                        let
                                            thisTypeVar : Variable
                                            thisTypeVar =
                                                MetaType.variableByIndex thisIndex
                                        in
                                        ( Value.Reference ( va, thisTypeVar ) fQName
                                        , ConstraintSet.singleton (equality (metaVar thisTypeVar) referenceType)
                                        )
                                    )
                            )

                Err _ ->
                    Count.oneOrReuse maybeThisTypeVar
                        (\thisIndex ->
                            let
                                thisTypeVar : Variable
                                thisTypeVar =
                                    MetaType.variableByIndex thisIndex
                            in
                            ( Value.Reference ( va, thisTypeVar ) fQName
                            , ConstraintSet.empty
                            )
                        )

        Value.Field va subjectValue fieldName ->
            constrainValue ir vars Nothing subjectValue
                |> Count.andThen
                    (\( annotatedSubjectValue, subjectValueConstraints ) ->
                        Count.three
                            (\thisIndex extendsIndex fieldIndex ->
                                let
                                    thisTypeVar : Variable
                                    thisTypeVar =
                                        MetaType.variableByIndex thisIndex

                                    extendsVar : Variable
                                    extendsVar =
                                        MetaType.variableByIndex extendsIndex

                                    fieldType : MetaType
                                    fieldType =
                                        metaVar (MetaType.variableByIndex fieldIndex)

                                    extensibleRecordType : MetaType
                                    extensibleRecordType =
                                        metaOpenRecord extendsVar
                                            (Dict.singleton fieldName fieldType)

                                    subjectConstraint : ConstraintSet
                                    subjectConstraint =
                                        ConstraintSet.singleton
                                            (equality (metaTypeVarForValue annotatedSubjectValue) extensibleRecordType)

                                    fieldConstraints : ConstraintSet
                                    fieldConstraints =
                                        ConstraintSet.fromList
                                            [ equality (metaTypeVarForValue annotatedSubjectValue) extensibleRecordType
                                            , equality (metaVar thisTypeVar) fieldType
                                            ]
                                in
                                ( Value.Field ( va, thisTypeVar ) annotatedSubjectValue fieldName
                                , ConstraintSet.concat
                                    [ subjectValueConstraints
                                    , subjectConstraint
                                    , fieldConstraints
                                    ]
                                )
                            )
                    )

        Value.FieldFunction va fieldName ->
            Count.three
                (\thisIndex extendsIndex fieldIndex ->
                    let
                        thisTypeVar : Variable
                        thisTypeVar =
                            MetaType.variableByIndex thisIndex

                        extendsVar : Variable
                        extendsVar =
                            MetaType.variableByIndex extendsIndex

                        fieldType : MetaType
                        fieldType =
                            metaVar (MetaType.variableByIndex fieldIndex)

                        extensibleRecordType : MetaType
                        extensibleRecordType =
                            metaOpenRecord extendsVar
                                (Dict.singleton fieldName fieldType)
                    in
                    ( Value.FieldFunction ( va, thisTypeVar ) fieldName
                    , ConstraintSet.singleton
                        (equality
                            (metaVar thisTypeVar)
                            (metaFun extensibleRecordType fieldType)
                        )
                    )
                )

        Value.Apply va funValue argValue ->
            constrainValue ir vars Nothing funValue
                |> Count.andThen
                    (\( annotatedFunValue, funValueConstraints ) ->
                        constrainValue ir vars Nothing argValue
                            |> Count.andThen
                                (\( annotatedArgValue, argValueConstraints ) ->
                                    Count.oneOrReuse maybeThisTypeVar
                                        (\thisIndex ->
                                            let
                                                thisTypeVar : Variable
                                                thisTypeVar =
                                                    MetaType.variableByIndex thisIndex

                                                funType : MetaType
                                                funType =
                                                    metaFun
                                                        (metaTypeVarForValue annotatedArgValue)
                                                        (metaVar thisTypeVar)

                                                applyConstraints : ConstraintSet
                                                applyConstraints =
                                                    ConstraintSet.singleton
                                                        (equality (metaTypeVarForValue annotatedFunValue) funType)
                                            in
                                            ( Value.Apply ( va, thisTypeVar ) annotatedFunValue annotatedArgValue
                                            , ConstraintSet.concat
                                                [ funValueConstraints
                                                , argValueConstraints
                                                , applyConstraints
                                                ]
                                            )
                                        )
                                )
                    )

        Value.Lambda va argPattern bodyValue ->
            constrainPattern ir Nothing argPattern
                |> Count.andThen
                    (\( argPatternVariables, annotatedArgPattern, argPatternConstraints ) ->
                        constrainValue ir (Dict.union argPatternVariables vars) Nothing bodyValue
                            |> Count.andThen
                                (\( annotatedBodyValue, bodyValueConstraints ) ->
                                    Count.oneOrReuse maybeThisTypeVar
                                        (\thisIndex ->
                                            let
                                                thisTypeVar : Variable
                                                thisTypeVar =
                                                    MetaType.variableByIndex thisIndex

                                                lambdaType : MetaType
                                                lambdaType =
                                                    metaFun
                                                        (metaTypeVarForPattern annotatedArgPattern)
                                                        (metaTypeVarForValue annotatedBodyValue)

                                                lambdaConstraints : ConstraintSet
                                                lambdaConstraints =
                                                    ConstraintSet.singleton
                                                        (equality (metaVar thisTypeVar) lambdaType)
                                            in
                                            ( Value.Lambda ( va, thisTypeVar ) annotatedArgPattern annotatedBodyValue
                                            , ConstraintSet.concat
                                                [ lambdaConstraints
                                                , bodyValueConstraints
                                                , argPatternConstraints
                                                ]
                                            )
                                        )
                                )
                    )

        Value.LetDefinition va defName def inValue ->
            constrainDefinition ir vars def
                |> Count.andThen
                    (\( defVar, annotatedDef, ( defConstraints, _ ) ) ->
                        constrainValue ir (vars |> Dict.insert defName defVar) Nothing inValue
                            |> Count.andThen
                                (\( annotatedInValue, inValueConstraints ) ->
                                    Count.oneOrReuse maybeThisTypeVar
                                        (\thisIndex ->
                                            let
                                                thisTypeVar =
                                                    MetaType.variableByIndex thisIndex

                                                defType : List MetaType -> MetaType -> MetaType
                                                defType argTypes returnType =
                                                    case argTypes of
                                                        [] ->
                                                            returnType

                                                        firstArg :: restOfArgs ->
                                                            metaFun firstArg (defType restOfArgs returnType)

                                                letConstraints : ConstraintSet
                                                letConstraints =
                                                    ConstraintSet.singleton
                                                        (equality
                                                            (metaVar thisTypeVar)
                                                            (metaTypeVarForValue annotatedInValue)
                                                        )
                                            in
                                            ( Value.LetDefinition ( va, thisTypeVar ) defName annotatedDef annotatedInValue
                                            , ConstraintSet.concat
                                                [ defConstraints
                                                , inValueConstraints
                                                , letConstraints
                                                ]
                                            )
                                        )
                                )
                    )

        Value.LetRecursion va defs inValue ->
            defs
                |> Dict.toList
                |> List.map
                    (\( defName, def ) ->
                        constrainDefinition ir vars def
                            |> Count.map (Tuple.pair defName)
                    )
                |> Count.all
                |> Count.andThen
                    (\defResults ->
                        let
                            defVariables : Dict Name Variable
                            defVariables =
                                defResults
                                    |> List.map (\( defName, ( defVar, _, ( _, _ ) ) ) -> ( defName, defVar ))
                                    |> Dict.fromList
                        in
                        constrainValue ir (vars |> Dict.union defVariables) Nothing inValue
                            |> Count.andThen
                                (\( annotatedInValue, inValueConstraints ) ->
                                    Count.oneOrReuse maybeThisTypeVar
                                        (\thisIndex ->
                                            let
                                                thisTypeVar : Variable
                                                thisTypeVar =
                                                    MetaType.variableByIndex thisIndex

                                                annotatedDefs : Dict Name (Value.Definition () ( va, Variable ))
                                                annotatedDefs =
                                                    defResults
                                                        |> List.map (\( defName, ( _, annotatedDef, _ ) ) -> ( defName, annotatedDef ))
                                                        |> Dict.fromList

                                                defsConstraints : ConstraintSet
                                                defsConstraints =
                                                    defResults
                                                        |> List.map (\( _, ( _, _, ( defConstraints, _ ) ) ) -> defConstraints)
                                                        |> ConstraintSet.concat

                                                letConstraints : ConstraintSet
                                                letConstraints =
                                                    ConstraintSet.fromList
                                                        [ equality (metaVar thisTypeVar) (metaTypeVarForValue annotatedInValue)
                                                        ]
                                            in
                                            ( Value.LetRecursion ( va, thisTypeVar ) annotatedDefs annotatedInValue
                                            , ConstraintSet.concat
                                                [ defsConstraints
                                                , inValueConstraints
                                                , letConstraints
                                                ]
                                            )
                                        )
                                )
                    )

        Value.Destructure va bindPattern bindValue inValue ->
            constrainPattern ir Nothing bindPattern
                |> Count.andThen
                    (\( bindPatternVariables, annotatedBindPattern, bindPatternConstraints ) ->
                        constrainValue ir vars Nothing bindValue
                            |> Count.andThen
                                (\( annotatedBindValue, bindValueConstraints ) ->
                                    constrainValue ir (Dict.union bindPatternVariables vars) Nothing inValue
                                        |> Count.andThen
                                            (\( annotatedInValue, inValueConstraints ) ->
                                                Count.oneOrReuse maybeThisTypeVar
                                                    (\thisIndex ->
                                                        let
                                                            thisTypeVar : Variable
                                                            thisTypeVar =
                                                                MetaType.variableByIndex thisIndex

                                                            destructureConstraints : ConstraintSet
                                                            destructureConstraints =
                                                                ConstraintSet.fromList
                                                                    [ equality (metaVar thisTypeVar) (metaTypeVarForValue annotatedInValue)
                                                                    , equality (metaTypeVarForValue annotatedBindValue) (metaTypeVarForPattern annotatedBindPattern)
                                                                    ]
                                                        in
                                                        ( Value.Destructure ( va, thisTypeVar ) annotatedBindPattern annotatedBindValue annotatedInValue
                                                        , ConstraintSet.concat
                                                            [ bindPatternConstraints
                                                            , bindValueConstraints
                                                            , inValueConstraints
                                                            , destructureConstraints
                                                            ]
                                                        )
                                                    )
                                            )
                                )
                    )

        Value.IfThenElse va condition thenBranch elseBranch ->
            Count.oneOrReuse maybeThisTypeVar
                (\thisIndex ->
                    let
                        thisTypeVar : Variable
                        thisTypeVar =
                            MetaType.variableByIndex thisIndex
                    in
                    constrainValue ir vars Nothing condition
                        |> Count.andThen
                            (\( annotatedCondition, conditionConstraints ) ->
                                constrainValue ir vars (Just thisTypeVar) thenBranch
                                    |> Count.andThen
                                        (\( annotatedThenBranch, thenBranchConstraints ) ->
                                            constrainValue ir vars (Just thisTypeVar) elseBranch
                                                |> Count.map
                                                    (\( annotatedElseBranch, elseBranchConstraints ) ->
                                                        let
                                                            specificConstraints : ConstraintSet
                                                            specificConstraints =
                                                                ConstraintSet.fromList
                                                                    -- the condition should always be bool
                                                                    [ equality (metaTypeVarForValue annotatedCondition) MetaType.boolType

                                                                    -- the two branches should have the same type
                                                                    , equality (metaTypeVarForValue annotatedElseBranch) (metaTypeVarForValue annotatedThenBranch)

                                                                    -- the final type should be the same as the branches (can use any branch thanks to previous rule)
                                                                    , equality (metaVar thisTypeVar) (metaTypeVarForValue annotatedThenBranch)
                                                                    ]

                                                            childConstraints : List ConstraintSet
                                                            childConstraints =
                                                                [ conditionConstraints
                                                                , thenBranchConstraints
                                                                , elseBranchConstraints
                                                                ]
                                                        in
                                                        ( Value.IfThenElse ( va, thisTypeVar ) annotatedCondition annotatedThenBranch annotatedElseBranch
                                                        , ConstraintSet.concat (specificConstraints :: childConstraints)
                                                        )
                                                    )
                                        )
                            )
                )
                |> Count.andThen identity

        Value.PatternMatch va subjectValue cases ->
            constrainValue ir vars Nothing subjectValue
                |> Count.andThen
                    (\( annotatedSubjectValue, subjectValueConstraints ) ->
                        Count.oneOrReuse maybeThisTypeVar
                            (\subjectIndex ->
                                let
                                    patternMetaVariable : Variable
                                    patternMetaVariable =
                                        annotatedSubjectValue
                                            |> Value.valueAttribute
                                            |> Tuple.second

                                    thisTypeVar : Variable
                                    thisTypeVar =
                                        MetaType.variableByIndex subjectIndex
                                in
                                cases
                                    |> List.map
                                        (\( casePattern, caseValue ) ->
                                            constrainPattern ir (Just patternMetaVariable) casePattern
                                                |> Count.andThen
                                                    (\( casePatternVariables, annotatedCasePattern, casePatternConstraints ) ->
                                                        constrainValue ir (Dict.union casePatternVariables vars) (Just thisTypeVar) caseValue
                                                            |> Count.map
                                                                (\( annotatedCaseValue, caseValueConstraints ) ->
                                                                    ( ( annotatedCasePattern, casePatternConstraints ), ( annotatedCaseValue, caseValueConstraints ) )
                                                                )
                                                    )
                                        )
                                    |> Count.all
                                    |> Count.map
                                        (\caseResults ->
                                            let
                                                thisType : MetaType
                                                thisType =
                                                    metaVar thisTypeVar

                                                subjectType : MetaType
                                                subjectType =
                                                    metaTypeVarForValue annotatedSubjectValue

                                                casesConstraints : List ConstraintSet
                                                casesConstraints =
                                                    caseResults
                                                        |> List.map
                                                            (\( ( annotatedCasePattern, casePatternConstraints ), ( annotatedCaseValue, caseValueConstraints ) ) ->
                                                                let
                                                                    caseConstraints : ConstraintSet
                                                                    caseConstraints =
                                                                        ConstraintSet.fromList
                                                                            [ equality subjectType (metaTypeVarForPattern annotatedCasePattern)
                                                                            , equality thisType (metaTypeVarForValue annotatedCaseValue)
                                                                            ]
                                                                in
                                                                ConstraintSet.concat
                                                                    [ casePatternConstraints
                                                                    , caseValueConstraints
                                                                    , caseConstraints
                                                                    ]
                                                            )

                                                annotatedCases : List ( Pattern ( va, Variable ), Value () ( va, Variable ) )
                                                annotatedCases =
                                                    caseResults
                                                        |> List.map
                                                            (\( ( annotatedCasePattern, _ ), ( annotatedCaseValue, _ ) ) ->
                                                                ( annotatedCasePattern, annotatedCaseValue )
                                                            )
                                            in
                                            ( Value.PatternMatch ( va, thisTypeVar ) annotatedSubjectValue annotatedCases
                                            , ConstraintSet.concat (subjectValueConstraints :: casesConstraints)
                                            )
                                        )
                            )
                            |> Count.andThen identity
                    )

        Value.UpdateRecord va subjectValue fieldValues ->
            constrainValue ir vars Nothing subjectValue
                |> Count.andThen
                    (\( annotatedSubjectValue, subjectValueConstraints ) ->
                        fieldValues
                            |> Dict.toList
                            |> List.map
                                (\( fieldName, fieldValue ) ->
                                    constrainValue ir vars Nothing fieldValue
                                        |> Count.map (Tuple.pair fieldName)
                                )
                            |> Count.all
                            |> Count.andThen
                                (\fieldValueResults ->
                                    Count.two
                                        (\thisIndex extendsIndex ->
                                            let
                                                thisTypeVar : Variable
                                                thisTypeVar =
                                                    MetaType.variableByIndex thisIndex

                                                extendsVar : Variable
                                                extendsVar =
                                                    MetaType.variableByIndex extendsIndex

                                                annotatedFieldValues : Dict Name (Value () ( va, Variable ))
                                                annotatedFieldValues =
                                                    fieldValueResults
                                                        |> List.map
                                                            (\( fieldName, ( annotatedFieldValue, _ ) ) ->
                                                                ( fieldName, annotatedFieldValue )
                                                            )
                                                        |> Dict.fromList

                                                extensibleRecordType : MetaType
                                                extensibleRecordType =
                                                    metaOpenRecord extendsVar
                                                        (annotatedFieldValues
                                                            |> Dict.map
                                                                (\_ annotatedFieldValue ->
                                                                    metaTypeVarForValue annotatedFieldValue
                                                                )
                                                        )

                                                fieldValueConstraints : ConstraintSet
                                                fieldValueConstraints =
                                                    fieldValueResults
                                                        |> List.map
                                                            (\( _, ( _, fc ) ) ->
                                                                fc
                                                            )
                                                        |> ConstraintSet.concat

                                                fieldConstraints : ConstraintSet
                                                fieldConstraints =
                                                    ConstraintSet.fromList
                                                        [ equality (metaTypeVarForValue annotatedSubjectValue) extensibleRecordType
                                                        , equality (metaVar thisTypeVar) (metaTypeVarForValue annotatedSubjectValue)
                                                        ]
                                            in
                                            ( Value.UpdateRecord ( va, thisTypeVar ) annotatedSubjectValue annotatedFieldValues
                                            , ConstraintSet.concat
                                                [ subjectValueConstraints
                                                , fieldValueConstraints
                                                , fieldConstraints
                                                ]
                                            )
                                        )
                                )
                    )

        Value.Unit va ->
            Count.oneOrReuse maybeThisTypeVar
                (\thisIndex ->
                    let
                        thisTypeVar : Variable
                        thisTypeVar =
                            MetaType.variableByIndex thisIndex
                    in
                    ( Value.Unit ( va, thisTypeVar )
                    , ConstraintSet.singleton
                        (equality (metaVar thisTypeVar) metaUnit)
                    )
                )


{-| Function that extracts variables and generates constraints for a pattern.
-}
constrainPattern : Distribution -> Maybe Variable -> Pattern va -> Count ( Dict Name Variable, Pattern ( va, Variable ), ConstraintSet )
constrainPattern ir maybeThisTypeVar pattern =
    case pattern of
        Value.WildcardPattern va ->
            Count.oneOrReuse maybeThisTypeVar
                (\index ->
                    ( Dict.empty
                    , Value.WildcardPattern ( va, MetaType.variableByIndex index )
                    , ConstraintSet.empty
                    )
                )

        Value.AsPattern va nestedPattern alias ->
            constrainPattern ir maybeThisTypeVar nestedPattern
                |> Count.map
                    (\( nestedVariables, nestedAnnotatedPattern, nestedConstraints ) ->
                        ( nestedVariables |> Dict.insert alias (patternVariable nestedAnnotatedPattern)
                        , Value.AsPattern ( va, patternVariable nestedAnnotatedPattern ) nestedAnnotatedPattern alias
                        , nestedConstraints
                        )
                    )

        Value.TuplePattern va elemPatterns ->
            elemPatterns
                |> List.map (constrainPattern ir Nothing)
                |> Count.all
                |> Count.andThen
                    (\elemResults ->
                        Count.one
                            (\index ->
                                let
                                    thisTypeVar =
                                        MetaType.variableByIndex index

                                    elemsVariables : List (Dict Name Variable)
                                    elemsVariables =
                                        elemResults
                                            |> List.map (\( v, _, _ ) -> v)

                                    elemAnnotatedPatterns : List (Pattern ( va, Variable ))
                                    elemAnnotatedPatterns =
                                        elemResults
                                            |> List.map (\( _, p, _ ) -> p)

                                    elemsConstraints : List ConstraintSet
                                    elemsConstraints =
                                        elemResults
                                            |> List.map (\( _, _, c ) -> c)

                                    tupleConstraint : ConstraintSet
                                    tupleConstraint =
                                        ConstraintSet.singleton
                                            (equality
                                                (metaVar thisTypeVar)
                                                (elemAnnotatedPatterns
                                                    |> List.map metaTypeVarForPattern
                                                    |> metaTuple
                                                )
                                            )
                                in
                                ( List.foldl Dict.union Dict.empty elemsVariables
                                , Value.TuplePattern ( va, thisTypeVar ) elemAnnotatedPatterns
                                , ConstraintSet.concat (tupleConstraint :: elemsConstraints)
                                )
                            )
                    )

        Value.ConstructorPattern va fQName argPatterns ->
            argPatterns
                |> List.map (constrainPattern ir Nothing)
                |> Count.all
                |> Count.andThen
                    (\argPatternResults ->
                        Count.map2
                            (\thisTypeVar ctorTypeVar ->
                                let
                                    argVariables : List (Dict Name Variable)
                                    argVariables =
                                        argPatternResults
                                            |> List.map (\( v, _, _ ) -> v)

                                    argAnnotatedPatterns : List (Pattern ( va, Variable ))
                                    argAnnotatedPatterns =
                                        argPatternResults
                                            |> List.map (\( _, p, _ ) -> p)

                                    argConstraints : List ConstraintSet
                                    argConstraints =
                                        argPatternResults
                                            |> List.map (\( _, _, c ) -> c)

                                    ctorType : List MetaType -> MetaType
                                    ctorType args =
                                        case args of
                                            [] ->
                                                metaVar thisTypeVar

                                            firstArg :: restOfArgs ->
                                                metaFun
                                                    firstArg
                                                    (ctorType restOfArgs)

                                    resultType : MetaType -> MetaType
                                    resultType t =
                                        case t of
                                            MetaFun _ a r ->
                                                resultType r

                                            _ ->
                                                t

                                    customTypeConstraintCounter : Count ConstraintSet
                                    customTypeConstraintCounter =
                                        lookupConstructor ir fQName
                                            |> Result.map
                                                (\ctorFunTypeCounter ->
                                                    ctorFunTypeCounter
                                                        |> Count.map
                                                            (\ctorFunType ->
                                                                ConstraintSet.fromList
                                                                    [ equality (metaVar ctorTypeVar) ctorFunType
                                                                    , equality (metaVar thisTypeVar) (resultType ctorFunType)
                                                                    ]
                                                            )
                                                )
                                            |> Result.withDefault (Count.none ConstraintSet.empty)

                                    ctorFunConstraint : ConstraintSet
                                    ctorFunConstraint =
                                        ConstraintSet.singleton
                                            (equality
                                                (metaVar ctorTypeVar)
                                                (ctorType
                                                    (argAnnotatedPatterns
                                                        |> List.map metaTypeVarForPattern
                                                    )
                                                )
                                            )
                                in
                                customTypeConstraintCounter
                                    |> Count.map
                                        (\customTypeConstraint ->
                                            ( List.foldl Dict.union Dict.empty argVariables
                                            , Value.ConstructorPattern ( va, thisTypeVar ) fQName argAnnotatedPatterns
                                            , ConstraintSet.concat (customTypeConstraint :: ctorFunConstraint :: argConstraints)
                                            )
                                        )
                            )
                            (Count.oneOrReuse maybeThisTypeVar
                                (\thisIndex ->
                                    MetaType.variableByIndex thisIndex
                                )
                            )
                            (Count.one
                                (\ctorIndex ->
                                    MetaType.variableByIndex ctorIndex
                                )
                            )
                            |> Count.andThen identity
                    )

        Value.EmptyListPattern va ->
            Count.map2
                (\thisTypeVar itemType ->
                    let
                        listType : MetaType
                        listType =
                            MetaType.listType itemType
                    in
                    ( Dict.empty
                    , Value.EmptyListPattern ( va, thisTypeVar )
                    , ConstraintSet.singleton
                        (equality (metaVar thisTypeVar) listType)
                    )
                )
                (Count.oneOrReuse maybeThisTypeVar
                    (\listIndex ->
                        MetaType.variableByIndex listIndex
                    )
                )
                (Count.one
                    (\itemIndex ->
                        metaVar (MetaType.variableByIndex itemIndex)
                    )
                )

        Value.HeadTailPattern va headPattern tailPattern ->
            constrainPattern ir Nothing headPattern
                |> Count.andThen
                    (\( headVariables, headAnnotatedPattern, headConstraints ) ->
                        constrainPattern ir Nothing tailPattern
                            |> Count.andThen
                                (\( tailVariables, tailAnnotatedPattern, tailConstraints ) ->
                                    Count.one
                                        (\thisIndex ->
                                            let
                                                thisTypeVar : Variable
                                                thisTypeVar =
                                                    MetaType.variableByIndex thisIndex

                                                itemType : MetaType
                                                itemType =
                                                    metaTypeVarForPattern headAnnotatedPattern

                                                listType : MetaType
                                                listType =
                                                    MetaType.listType itemType

                                                thisPatternConstraints : ConstraintSet
                                                thisPatternConstraints =
                                                    ConstraintSet.fromList
                                                        [ equality (metaVar thisTypeVar) listType
                                                        , equality (metaTypeVarForPattern tailAnnotatedPattern) listType
                                                        ]
                                            in
                                            ( Dict.union headVariables tailVariables
                                            , Value.HeadTailPattern ( va, thisTypeVar ) headAnnotatedPattern tailAnnotatedPattern
                                            , ConstraintSet.concat
                                                [ headConstraints, tailConstraints, thisPatternConstraints ]
                                            )
                                        )
                                )
                    )

        Value.LiteralPattern va literalValue ->
            Count.oneOrReuse maybeThisTypeVar
                (\thisIndex ->
                    let
                        thisTypeVar : Variable
                        thisTypeVar =
                            MetaType.variableByIndex thisIndex
                    in
                    ( Dict.empty
                    , Value.LiteralPattern ( va, thisTypeVar ) literalValue
                    , constrainLiteral thisTypeVar literalValue
                    )
                )

        Value.UnitPattern va ->
            Count.oneOrReuse maybeThisTypeVar
                (\thisIndex ->
                    let
                        thisTypeVar : Variable
                        thisTypeVar =
                            MetaType.variableByIndex thisIndex
                    in
                    ( Dict.empty
                    , Value.UnitPattern ( va, thisTypeVar )
                    , ConstraintSet.singleton
                        (equality (metaVar thisTypeVar) metaUnit)
                    )
                )


constrainLiteral : Variable -> Literal -> ConstraintSet
constrainLiteral thisTypeVar literalValue =
    let
        expectExactType : MetaType -> ConstraintSet
        expectExactType expectedType =
            ConstraintSet.singleton
                (equality
                    (metaVar thisTypeVar)
                    expectedType
                )
    in
    case literalValue of
        BoolLiteral _ ->
            expectExactType MetaType.boolType

        CharLiteral _ ->
            expectExactType MetaType.charType

        StringLiteral _ ->
            expectExactType MetaType.stringType

        WholeNumberLiteral _ ->
            ConstraintSet.singleton
                (class (metaVar thisTypeVar) Class.Number)

        FloatLiteral _ ->
            expectExactType MetaType.floatType

        DecimalLiteral _ ->
            ConstraintSet.singleton
                (class (metaVar thisTypeVar) Class.Number)


solve : Distribution -> ConstraintSet -> Result TypeError ( ConstraintSet, SolutionMap )
solve refs constraintSet =
    solveHelp refs Solve.emptySolution constraintSet


solveHelp : Distribution -> SolutionMap -> ConstraintSet -> Result TypeError ( ConstraintSet, SolutionMap )
solveHelp ir solutionsSoFar ((ConstraintSet constraints) as constraintSet) =
    --let
    --    _ =
    --        constraints
    --            |> List.map (Constraint.toString >> Debug.log "constraints so far")
    --
    --    _ =
    --        Debug.log "solutions so far" (solutionsSoFar |> Solve.toList |> List.length)
    --in
    case validateConstraints constraints of
        Ok _ ->
            case solveStep ir solutionsSoFar constraintSet of
                Ok (Just ( newConstraints, mergedSolutions )) ->
                    if solutionsSoFar == mergedSolutions then
                        Ok ( newConstraints, mergedSolutions )

                    else
                        solveHelp ir mergedSolutions newConstraints

                Ok Nothing ->
                    Ok ( constraintSet, solutionsSoFar )

                Err error ->
                    Err error

        Err error ->
            Err error


solveStep : Distribution -> SolutionMap -> ConstraintSet -> Result TypeError (Maybe ( ConstraintSet, SolutionMap ))
solveStep refs solutionsSoFar ((ConstraintSet constraints) as constraintSet) =
    case validateConstraints constraints of
        Ok nonTrivialConstraints ->
            case Solve.findSubstitution refs nonTrivialConstraints of
                Ok maybeNewSolutions ->
                    case maybeNewSolutions of
                        Nothing ->
                            Ok Nothing

                        Just newSolutions ->
                            case Solve.mergeSolutions refs newSolutions solutionsSoFar of
                                Ok mergedSolutions ->
                                    let
                                        -- Compare the latest set of solutions to the previous set and keep only the new solutions
                                        newMergedSolutions : SolutionMap
                                        newMergedSolutions =
                                            solutionsSoFar |> Solve.diff mergedSolutions
                                    in
                                    Ok (Just ( constraintSet |> ConstraintSet.applySubstitutions newMergedSolutions, mergedSolutions ))

                                Err error ->
                                    Err (UnifyError error)

                Err error ->
                    Err (UnifyError error)

        Err error ->
            Err error


validateConstraints : List Constraint -> Result TypeError (List Constraint)
validateConstraints constraints =
    constraints
        |> List.map
            (\constraint ->
                case constraint of
                    Class _ (MetaVar _) _ ->
                        Ok constraint

                    Class _ metaType class ->
                        if Class.member metaType class then
                            Ok constraint

                        else
                            Err (ClassConstraintViolation metaType class)

                    Equality _ metaType1 metaType2 ->
                        if isRecursive constraint then
                            Err (RecursiveConstraint metaType1 metaType2)

                        else
                            Ok constraint
            )
        |> ListOfResults.keepAllErrors
        |> Result.mapError typeErrors


applySolutionToAnnotatedDefinition : Distribution -> Dict Name Variable -> Value.Definition ta ( va, Variable ) -> ( ConstraintSet, SolutionMap ) -> Value.Definition ta ( va, Type () )
applySolutionToAnnotatedDefinition ir typeVarByIndex annotatedDef ( residualConstraints, solutionMap ) =
    let
        typeVarByType : Dict Name (Type ())
        typeVarByType =
            typeVarByIndex
                |> Dict.toList
                |> List.map (\( name, idx ) -> ( [ "t", String.fromInt idx ], Type.Variable () name ))
                |> Dict.fromList
    in
    annotatedDef
        |> Value.mapDefinitionAttributes identity
            (\( va, metaVar ) ->
                ( va
                , solutionMap
                    |> Solve.get metaVar
                    |> Maybe.map (metaTypeToConcreteType solutionMap)
                    |> Maybe.map (Type.substituteTypeVariables typeVarByType)
                    |> Maybe.withDefault (Type.Variable () [ "t", String.fromInt metaVar ])
                )
            )
        |> (\valDef -> { valDef | body = valDef.body |> fixNumberLiterals ir })


applySolutionToAnnotatedValue : Distribution -> Value () ( va, Variable ) -> ( ConstraintSet, SolutionMap ) -> TypedValue va
applySolutionToAnnotatedValue ir annotatedValue ( residualConstraints, solutionMap ) =
    annotatedValue
        |> Value.mapValueAttributes identity
            (\( va, metaVar ) ->
                ( va
                , solutionMap
                    |> Solve.get metaVar
                    |> Maybe.map (metaTypeToConcreteType solutionMap)
                    |> Maybe.withDefault (Type.Variable () [ "t", String.fromInt metaVar ])
                )
            )
        |> fixNumberLiterals ir


fixNumberLiterals : Distribution -> Value ta ( va, Type () ) -> Value ta ( va, Type () )
fixNumberLiterals ir typedValue =
    typedValue
        |> Value.rewriteValue
            (\value ->
                case value of
                    Value.Literal ( va, tpe ) (WholeNumberLiteral v) ->
                        if (ir |> Distribution.resolveType tpe) == floatType () then
                            Value.Literal ( va, tpe ) (FloatLiteral (toFloat v)) |> Just

                        else
                            Nothing

                    _ ->
                        Nothing
            )


typeErrors : List TypeError -> TypeError
typeErrors errors =
    case errors of
        [ single ] ->
            single

        _ ->
            TypeErrors errors


metaTypeVarForValue : Value ta ( va, Variable ) -> MetaType
metaTypeVarForValue value =
    value
        |> Value.valueAttribute
        |> Tuple.second
        |> metaVar


metaTypeVarForPattern : Pattern ( va, Variable ) -> MetaType
metaTypeVarForPattern pattern =
    pattern
        |> Value.patternAttribute
        |> Tuple.second
        |> metaVar


patternVariable : Pattern ( va, Variable ) -> Variable
patternVariable pattern =
    pattern
        |> Value.patternAttribute
        |> Tuple.second
