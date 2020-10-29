module Morphir.Type.Infer exposing (..)

import Dict exposing (Dict)
import Morphir.IR.FQName exposing (FQName(..), fqn)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Type as Type exposing (Specification(..), Type)
import Morphir.IR.Value as Value exposing (Pattern(..), Value)
import Morphir.ListOfResults as ListOfResults
import Morphir.Type.Class as Class exposing (Class)
import Morphir.Type.Constraint as Constraint exposing (Constraint(..), Target(..), class, equality, lookupCtor, lookupValue)
import Morphir.Type.ConstraintSet as ConstraintSet exposing (ConstraintSet(..))
import Morphir.Type.MetaType as MetaType exposing (MetaType(..))
import Morphir.Type.MetaVar as MetaVar exposing (Variable)
import Morphir.Type.SolutionMap as SolutionMap exposing (SolutionMap(..))
import Set exposing (Set)


type alias References =
    Dict PackageName (Package.Specification ())


type alias TypedValue va =
    Value () ( va, Type () )


type TypeError
    = TypeMismatch MetaType MetaType
    | TypeErrors (List TypeError)
    | ClassConstraintViolation MetaType Class
    | CouldNotFindConstructor FQName
    | CouldNotFindValue FQName


inferDefinition : References -> Value.Definition () va -> Result TypeError (Value.Definition () ( va, Type () ))
inferDefinition refs def =
    let
        annotatedDef : Value.Definition () ( va, Variable )
        annotatedDef =
            annotateDefinition 0 def

        constraints : ConstraintSet
        constraints =
            constrainDefinition (MetaVar.variable 0) Dict.empty annotatedDef

        solution : Result TypeError ( ConstraintSet, SolutionMap )
        solution =
            solve refs constraints
    in
    solution
        |> Result.map (applySolutionToAnnotatedDefinition annotatedDef)


inferValue : References -> Value () va -> Result TypeError (TypedValue va)
inferValue refs untypedValue =
    let
        annotatedValue : Value () ( va, Variable )
        annotatedValue =
            annotateValue 0 untypedValue

        constraints : ConstraintSet
        constraints =
            constrainValue Dict.empty annotatedValue

        solution : Result TypeError ( ConstraintSet, SolutionMap )
        solution =
            solve refs constraints
    in
    solution
        |> Result.map (applySolutionToAnnotatedValue annotatedValue)


annotateDefinition : Int -> Value.Definition () va -> Value.Definition () ( va, Variable )
annotateDefinition baseIndex def =
    let
        annotatedInputTypes : List ( Name, ( va, Variable ), Type () )
        annotatedInputTypes =
            def.inputTypes
                |> List.indexedMap
                    (\index ( name, va, tpe ) ->
                        ( name, ( va, MetaVar.variable (baseIndex + index) ), tpe )
                    )

        annotatedBody : Value () ( va, Variable )
        annotatedBody =
            annotateValue (baseIndex + List.length def.inputTypes) def.body
    in
    { inputTypes =
        annotatedInputTypes
    , outputType =
        def.outputType
    , body =
        annotatedBody
    }


annotateValue : Int -> Value () va -> Value () ( va, Variable )
annotateValue baseIndex untypedValue =
    untypedValue
        |> Value.indexedMapValue (\index va -> ( va, MetaVar.variable index )) baseIndex
        |> Tuple.first


constrainDefinition : Variable -> Dict Name Variable -> Value.Definition () ( va, Variable ) -> ConstraintSet
constrainDefinition baseVar vars def =
    let
        inputTypeVars : Set Name
        inputTypeVars =
            def.inputTypes
                |> List.map
                    (\( _, _, declaredType ) ->
                        Type.collectVariables declaredType
                    )
                |> List.foldl Set.union Set.empty

        outputTypeVars : Set Name
        outputTypeVars =
            Type.collectVariables def.outputType

        varToMeta : Dict Name Variable
        varToMeta =
            concreteVarsToMetaVars baseVar
                (Set.union inputTypeVars outputTypeVars)

        inputConstraints : ConstraintSet
        inputConstraints =
            def.inputTypes
                |> List.map
                    (\( _, ( _, thisTypeVar ), declaredType ) ->
                        equality
                            (MetaVar thisTypeVar)
                            (typeToMetaType thisTypeVar varToMeta declaredType)
                    )
                |> ConstraintSet.fromList

        outputConstraints : ConstraintSet
        outputConstraints =
            ConstraintSet.singleton
                (equality
                    (metaTypeVarForValue def.body)
                    (typeToMetaType baseVar varToMeta def.outputType)
                )

        inputVars : Dict Name Variable
        inputVars =
            def.inputTypes
                |> List.map
                    (\( name, ( _, thisTypeVar ), _ ) ->
                        ( name, thisTypeVar )
                    )
                |> Dict.fromList

        bodyConstraints : ConstraintSet
        bodyConstraints =
            constrainValue (vars |> Dict.union inputVars) def.body
    in
    ConstraintSet.concat
        [ inputConstraints
        , outputConstraints
        , bodyConstraints
        ]


constrainValue : Dict Name Variable -> Value () ( va, Variable ) -> ConstraintSet
constrainValue vars annotatedValue =
    case annotatedValue of
        Value.Literal ( _, thisTypeVar ) literalValue ->
            constrainLiteral thisTypeVar literalValue

        Value.Constructor ( _, thisTypeVar ) fQName ->
            ConstraintSet.singleton
                (lookupCtor (MetaVar thisTypeVar) fQName)

        Value.Tuple ( _, thisTypeVar ) elems ->
            let
                elemsConstraints : List ConstraintSet
                elemsConstraints =
                    elems
                        |> List.map (constrainValue vars)

                tupleConstraint : ConstraintSet
                tupleConstraint =
                    ConstraintSet.singleton
                        (equality
                            (MetaVar thisTypeVar)
                            (elems
                                |> List.map metaTypeVarForValue
                                |> MetaTuple
                            )
                        )
            in
            ConstraintSet.concat (tupleConstraint :: elemsConstraints)

        Value.List ( _, thisTypeVar ) items ->
            let
                itemType : MetaType
                itemType =
                    MetaVar (thisTypeVar |> MetaVar.subVariable)

                listConstraint : Constraint
                listConstraint =
                    equality (MetaVar thisTypeVar) (MetaType.listType itemType)

                itemConstraints : ConstraintSet
                itemConstraints =
                    items
                        |> List.map
                            (\item ->
                                constrainValue vars item
                                    |> ConstraintSet.insert (equality (metaTypeVarForValue item) itemType)
                            )
                        |> ConstraintSet.concat
            in
            itemConstraints
                |> ConstraintSet.insert listConstraint

        Value.Record ( _, thisTypeVar ) fieldValues ->
            let
                fieldConstraints : ConstraintSet
                fieldConstraints =
                    fieldValues
                        |> List.map (Tuple.second >> constrainValue vars)
                        |> ConstraintSet.concat

                recordType : MetaType
                recordType =
                    fieldValues
                        |> List.map
                            (\( fieldName, fieldValue ) ->
                                ( fieldName, metaTypeVarForValue fieldValue )
                            )
                        |> Dict.fromList
                        |> MetaRecord Nothing

                recordConstraints : ConstraintSet
                recordConstraints =
                    ConstraintSet.singleton
                        (equality (MetaVar thisTypeVar) recordType)
            in
            ConstraintSet.concat
                [ fieldConstraints
                , recordConstraints
                ]

        Value.Variable ( _, varUse ) varName ->
            case vars |> Dict.get varName of
                Just varDecl ->
                    ConstraintSet.singleton (equality (MetaVar varUse) (MetaVar varDecl))

                Nothing ->
                    -- this should never happen if variables were validated earlier
                    ConstraintSet.empty

        Value.Reference ( _, thisTypeVar ) fQName ->
            ConstraintSet.singleton
                (lookupValue (MetaVar thisTypeVar) fQName)

        Value.Field ( _, thisTypeVar ) subjectValue fieldName ->
            let
                extendsVar : Variable
                extendsVar =
                    thisTypeVar
                        |> MetaVar.subVariable

                extendsType : MetaType
                extendsType =
                    MetaVar extendsVar

                fieldType : MetaType
                fieldType =
                    extendsVar
                        |> MetaVar.subVariable
                        |> MetaVar

                extensibleRecordType : MetaType
                extensibleRecordType =
                    MetaRecord (Just extendsType)
                        (Dict.singleton fieldName fieldType)

                fieldConstraints : ConstraintSet
                fieldConstraints =
                    ConstraintSet.fromList
                        [ equality (metaTypeVarForValue subjectValue) extensibleRecordType
                        , equality (MetaVar thisTypeVar) fieldType
                        ]
            in
            ConstraintSet.concat
                [ constrainValue vars subjectValue
                , fieldConstraints
                ]

        Value.FieldFunction ( _, thisTypeVar ) fieldName ->
            let
                extendsVar : Variable
                extendsVar =
                    thisTypeVar
                        |> MetaVar.subVariable

                extendsType : MetaType
                extendsType =
                    MetaVar extendsVar

                fieldType : MetaType
                fieldType =
                    extendsVar
                        |> MetaVar.subVariable
                        |> MetaVar

                extensibleRecordType : MetaType
                extensibleRecordType =
                    MetaRecord (Just extendsType)
                        (Dict.singleton fieldName fieldType)
            in
            ConstraintSet.singleton
                (equality (MetaVar thisTypeVar) (MetaFun extensibleRecordType fieldType))

        Value.Apply ( _, thisTypeVar ) funValue argValue ->
            let
                funType : MetaType
                funType =
                    MetaFun
                        (metaTypeVarForValue argValue)
                        (MetaVar thisTypeVar)

                applyConstraints : ConstraintSet
                applyConstraints =
                    ConstraintSet.singleton
                        (equality (metaTypeVarForValue funValue) funType)
            in
            ConstraintSet.concat
                [ constrainValue vars funValue
                , constrainValue vars argValue
                , applyConstraints
                ]

        Value.Lambda ( _, thisTypeVar ) argPattern bodyValue ->
            let
                ( argVariables, argConstraints ) =
                    constrainPattern argPattern

                lambdaType : MetaType
                lambdaType =
                    MetaFun
                        (metaTypeVarForPattern argPattern)
                        (metaTypeVarForValue bodyValue)

                lambdaConstraints : ConstraintSet
                lambdaConstraints =
                    ConstraintSet.singleton
                        (equality (MetaVar thisTypeVar) lambdaType)
            in
            ConstraintSet.concat
                [ lambdaConstraints
                , constrainValue (Dict.union argVariables vars) bodyValue
                , argConstraints
                ]

        Value.LetDefinition ( _, thisTypeVar ) defName def inValue ->
            let
                defConstraints : ConstraintSet
                defConstraints =
                    constrainDefinition thisTypeVar vars def

                defTypeVar : Variable
                defTypeVar =
                    thisTypeVar |> MetaVar.subVariable

                defType : List MetaType -> MetaType -> MetaType
                defType argTypes returnType =
                    case argTypes of
                        [] ->
                            returnType

                        firstArg :: restOfArgs ->
                            MetaFun firstArg (defType restOfArgs returnType)

                inConstraints : ConstraintSet
                inConstraints =
                    constrainValue
                        (vars
                            |> Dict.insert defName defTypeVar
                        )
                        inValue

                letConstraints : ConstraintSet
                letConstraints =
                    ConstraintSet.fromList
                        [ equality (MetaVar thisTypeVar) (metaTypeVarForValue inValue)
                        , equality (MetaVar defTypeVar)
                            (defType
                                (def.inputTypes |> List.map (\( _, ( _, argTypeVar ), _ ) -> MetaVar argTypeVar))
                                (metaTypeVarForValue def.body)
                            )
                        ]
            in
            ConstraintSet.concat
                [ defConstraints
                , inConstraints
                , letConstraints
                ]

        Value.LetRecursion ( _, thisTypeVar ) defs inValue ->
            let
                defType : List MetaType -> MetaType -> MetaType
                defType argTypes returnType =
                    case argTypes of
                        [] ->
                            returnType

                        firstArg :: restOfArgs ->
                            MetaFun firstArg (defType restOfArgs returnType)

                ( lastDefTypeVar, defDeclsConstraints, defVariables ) =
                    defs
                        |> Dict.toList
                        |> List.foldl
                            (\( defName, def ) ( lastTypeVar, constraintsSoFar, variablesSoFar ) ->
                                let
                                    nextTypeVar : Variable
                                    nextTypeVar =
                                        lastTypeVar |> MetaVar.subVariable

                                    letConstraint : ConstraintSet
                                    letConstraint =
                                        ConstraintSet.fromList
                                            [ equality (MetaVar nextTypeVar)
                                                (defType
                                                    (def.inputTypes |> List.map (\( _, ( _, argTypeVar ), _ ) -> MetaVar argTypeVar))
                                                    (metaTypeVarForValue def.body)
                                                )
                                            ]
                                in
                                ( nextTypeVar, letConstraint :: constraintsSoFar, ( defName, nextTypeVar ) :: variablesSoFar )
                            )
                            ( thisTypeVar, [], [] )

                defsConstraints =
                    defs
                        |> Dict.toList
                        |> List.foldl
                            (\( _, def ) ( lastTypeVar, constraintsSoFar ) ->
                                let
                                    nextTypeVar : Variable
                                    nextTypeVar =
                                        lastTypeVar |> MetaVar.subVariable

                                    defConstraints : ConstraintSet
                                    defConstraints =
                                        constrainDefinition lastTypeVar vars def
                                in
                                ( nextTypeVar, defConstraints :: constraintsSoFar )
                            )
                            ( lastDefTypeVar, defDeclsConstraints )
                        |> Tuple.second
                        |> ConstraintSet.concat

                inConstraints : ConstraintSet
                inConstraints =
                    constrainValue
                        (vars
                            |> Dict.union (defVariables |> Dict.fromList)
                        )
                        inValue

                letConstraints : ConstraintSet
                letConstraints =
                    ConstraintSet.fromList
                        [ equality (MetaVar thisTypeVar) (metaTypeVarForValue inValue)
                        ]
            in
            ConstraintSet.concat
                [ defsConstraints
                , inConstraints
                , letConstraints
                ]

        Value.Destructure ( _, thisTypeVar ) bindPattern bindValue inValue ->
            let
                ( bindPatternVariables, bindPatternConstraints ) =
                    constrainPattern bindPattern

                bindValueConstraints : ConstraintSet
                bindValueConstraints =
                    constrainValue vars bindValue

                inValueConstraints : ConstraintSet
                inValueConstraints =
                    constrainValue (Dict.union bindPatternVariables vars) inValue

                destructureConstraints : ConstraintSet
                destructureConstraints =
                    ConstraintSet.fromList
                        [ equality (MetaVar thisTypeVar) (metaTypeVarForValue inValue)
                        , equality (metaTypeVarForValue bindValue) (metaTypeVarForPattern bindPattern)
                        ]
            in
            ConstraintSet.concat
                [ bindPatternConstraints
                , bindValueConstraints
                , inValueConstraints
                , destructureConstraints
                ]

        Value.IfThenElse ( _, thisTypeVar ) condition thenBranch elseBranch ->
            let
                specificConstraints : ConstraintSet
                specificConstraints =
                    ConstraintSet.fromList
                        -- the condition should always be bool
                        [ equality (metaTypeVarForValue condition) MetaType.boolType

                        -- the two branches should have the same type
                        , equality (metaTypeVarForValue elseBranch) (metaTypeVarForValue thenBranch)

                        -- the final type should be the same as the branches (can use any branch thanks to previous rule)
                        , equality (MetaVar thisTypeVar) (metaTypeVarForValue thenBranch)
                        ]

                childConstraints : List ConstraintSet
                childConstraints =
                    [ constrainValue vars condition
                    , constrainValue vars thenBranch
                    , constrainValue vars elseBranch
                    ]
            in
            ConstraintSet.concat (specificConstraints :: childConstraints)

        Value.PatternMatch ( _, thisTypeVar ) subjectValue cases ->
            let
                thisType : MetaType
                thisType =
                    MetaVar thisTypeVar

                subjectType : MetaType
                subjectType =
                    metaTypeVarForValue subjectValue

                casesConstraints : List ConstraintSet
                casesConstraints =
                    cases
                        |> List.map
                            (\( casePattern, caseValue ) ->
                                let
                                    ( casePatternVariables, casePatternConstraints ) =
                                        constrainPattern casePattern

                                    caseValueConstraints : ConstraintSet
                                    caseValueConstraints =
                                        constrainValue (Dict.union casePatternVariables vars) caseValue

                                    caseConstraints : ConstraintSet
                                    caseConstraints =
                                        ConstraintSet.fromList
                                            [ equality subjectType (metaTypeVarForPattern casePattern)
                                            , equality thisType (metaTypeVarForValue caseValue)
                                            ]
                                in
                                ConstraintSet.concat
                                    [ casePatternConstraints
                                    , caseValueConstraints
                                    , caseConstraints
                                    ]
                            )
            in
            ConstraintSet.concat casesConstraints

        Value.UpdateRecord ( _, thisTypeVar ) subjectValue fieldValues ->
            let
                extendsVar : Variable
                extendsVar =
                    thisTypeVar
                        |> MetaVar.subVariable

                extendsType : MetaType
                extendsType =
                    MetaVar extendsVar

                extensibleRecordType : MetaType
                extensibleRecordType =
                    MetaRecord (Just extendsType)
                        (fieldValues
                            |> List.map
                                (\( fieldName, fieldValue ) ->
                                    ( fieldName, metaTypeVarForValue fieldValue )
                                )
                            |> Dict.fromList
                        )

                fieldValueConstraints : ConstraintSet
                fieldValueConstraints =
                    fieldValues
                        |> List.map
                            (\( _, fieldValue ) ->
                                constrainValue vars fieldValue
                            )
                        |> ConstraintSet.concat

                fieldConstraints : ConstraintSet
                fieldConstraints =
                    ConstraintSet.fromList
                        [ equality (metaTypeVarForValue subjectValue) extensibleRecordType
                        , equality (MetaVar thisTypeVar) (metaTypeVarForValue subjectValue)
                        ]
            in
            ConstraintSet.concat
                [ constrainValue vars subjectValue
                , fieldValueConstraints
                , fieldConstraints
                ]

        Value.Unit ( _, thisTypeVar ) ->
            ConstraintSet.singleton
                (equality (MetaVar thisTypeVar) MetaUnit)


constrainPattern : Pattern ( va, Variable ) -> ( Dict Name Variable, ConstraintSet )
constrainPattern untypedPattern =
    case untypedPattern of
        Value.WildcardPattern _ ->
            ( Dict.empty, ConstraintSet.empty )

        Value.AsPattern ( _, thisTypeVar ) nestedPattern alias ->
            let
                ( nestedVariables, nestedConstraints ) =
                    constrainPattern nestedPattern

                thisPatternConstraints : ConstraintSet
                thisPatternConstraints =
                    ConstraintSet.singleton
                        (equality (MetaVar thisTypeVar) (metaTypeVarForPattern nestedPattern))
            in
            ( nestedVariables |> Dict.insert alias thisTypeVar
            , ConstraintSet.union nestedConstraints thisPatternConstraints
            )

        Value.TuplePattern ( _, thisTypeVar ) elemPatterns ->
            let
                ( elemsVariables, elemsConstraints ) =
                    elemPatterns
                        |> List.map constrainPattern
                        |> List.unzip

                tupleConstraint : ConstraintSet
                tupleConstraint =
                    ConstraintSet.singleton
                        (equality
                            (MetaVar thisTypeVar)
                            (elemPatterns
                                |> List.map metaTypeVarForPattern
                                |> MetaTuple
                            )
                        )
            in
            ( List.foldl Dict.union Dict.empty elemsVariables
            , ConstraintSet.concat (tupleConstraint :: elemsConstraints)
            )

        Value.ConstructorPattern ( _, thisTypeVar ) fQName argPatterns ->
            let
                ctorConstraints : ConstraintSet
                ctorConstraints =
                    ConstraintSet.singleton
                        (lookupCtor (MetaVar thisTypeVar) fQName)

                ( argVariables, argConstraints ) =
                    argPatterns
                        |> List.map constrainPattern
                        |> List.unzip
            in
            ( List.foldl Dict.union Dict.empty argVariables
            , ConstraintSet.concat (ctorConstraints :: argConstraints)
            )

        Value.EmptyListPattern ( _, thisTypeVar ) ->
            let
                itemType : MetaType
                itemType =
                    MetaVar (thisTypeVar |> MetaVar.subVariable)

                listType : MetaType
                listType =
                    MetaType.listType itemType
            in
            ( Dict.empty
            , ConstraintSet.singleton
                (equality (MetaVar thisTypeVar) listType)
            )

        Value.HeadTailPattern ( _, thisTypeVar ) headPattern tailPattern ->
            let
                ( headVariables, headConstraints ) =
                    constrainPattern headPattern

                ( tailVariables, tailConstraints ) =
                    constrainPattern tailPattern

                itemType : MetaType
                itemType =
                    metaTypeVarForPattern headPattern

                listType : MetaType
                listType =
                    MetaType.listType itemType

                thisPatternConstraints : ConstraintSet
                thisPatternConstraints =
                    ConstraintSet.fromList
                        [ equality (MetaVar thisTypeVar) listType
                        , equality (metaTypeVarForPattern tailPattern) listType
                        ]
            in
            ( Dict.union headVariables tailVariables
            , ConstraintSet.concat
                [ headConstraints, tailConstraints, thisPatternConstraints ]
            )

        Value.LiteralPattern ( _, thisTypeVar ) literalValue ->
            ( Dict.empty, constrainLiteral thisTypeVar literalValue )

        Value.UnitPattern ( _, thisTypeVar ) ->
            ( Dict.empty
            , ConstraintSet.singleton
                (equality (MetaVar thisTypeVar) MetaUnit)
            )


constrainLiteral : Variable -> Literal -> ConstraintSet
constrainLiteral thisTypeVar literalValue =
    let
        expectExactType : MetaType -> ConstraintSet
        expectExactType expectedType =
            ConstraintSet.singleton
                (equality
                    (MetaVar thisTypeVar)
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

        IntLiteral _ ->
            ConstraintSet.singleton
                (class (MetaVar thisTypeVar) Class.Number)

        FloatLiteral _ ->
            expectExactType MetaType.floatType


solve : References -> ConstraintSet -> Result TypeError ( ConstraintSet, SolutionMap )
solve refs constraintSet =
    solveHelp refs SolutionMap.empty constraintSet


solveHelp : References -> SolutionMap -> ConstraintSet -> Result TypeError ( ConstraintSet, SolutionMap )
solveHelp refs solutionsSoFar ((ConstraintSet constraints) as constraintSet) =
    constraints
        |> validateConstraints
        |> Result.map removeTrivialConstraints
        |> Result.andThen
            (\nonTrivialConstraints ->
                nonTrivialConstraints
                    |> findSubstitution refs
                    |> Result.andThen
                        (\maybeNewSolutions ->
                            case maybeNewSolutions of
                                Nothing ->
                                    Ok ( ConstraintSet.fromList nonTrivialConstraints, solutionsSoFar )

                                Just newSolutions ->
                                    solutionsSoFar
                                        |> mergeSolutions newSolutions
                                        |> Result.andThen
                                            (\mergedSolutions ->
                                                solveHelp refs mergedSolutions (constraintSet |> ConstraintSet.applySubstitutions mergedSolutions)
                                            )
                        )
            )


removeTrivialConstraints : List Constraint -> List Constraint
removeTrivialConstraints constraints =
    constraints
        |> List.filter
            (\constraint ->
                case constraint of
                    Equality metaType1 metaType2 ->
                        metaType1 /= metaType2

                    Class metaType _ ->
                        case metaType of
                            -- If this is a variable we still need to resolve it
                            MetaVar _ ->
                                True

                            -- Otherwise it's a specific type already so we can remove this constraint
                            _ ->
                                False

                    Lookup _ metaType _ ->
                        case metaType of
                            -- If this is a variable we still need to resolve it
                            MetaVar _ ->
                                True

                            -- Otherwise it's a specific type already so we can remove this constraint
                            _ ->
                                False
            )


validateConstraints : List Constraint -> Result TypeError (List Constraint)
validateConstraints constraints =
    constraints
        |> List.map
            (\constraint ->
                case constraint of
                    Class (MetaVar _) _ ->
                        Ok constraint

                    Class metaType class ->
                        if Class.member metaType class then
                            Ok constraint

                        else
                            Err (ClassConstraintViolation metaType class)

                    _ ->
                        Ok constraint
            )
        |> ListOfResults.liftAllErrors
        |> Result.mapError typeErrors


findSubstitution : References -> List Constraint -> Result TypeError (Maybe SolutionMap)
findSubstitution refs constraints =
    case constraints of
        [] ->
            Ok Nothing

        firstConstraint :: restOfConstraints ->
            case firstConstraint of
                Equality metaType1 metaType2 ->
                    unifyMetaType metaType1 metaType2
                        |> Result.andThen
                            (\solutions ->
                                if SolutionMap.isEmpty solutions then
                                    findSubstitution refs restOfConstraints

                                else
                                    Ok (Just solutions)
                            )

                Class _ _ ->
                    findSubstitution refs restOfConstraints

                Lookup target metaType1 fQName ->
                    let
                        baseVar =
                            case metaType1 of
                                MetaVar v ->
                                    v

                                other ->
                                    Debug.todo ("baseVar cannot be derived " ++ Debug.toString other)
                    in
                    lookupMetaType baseVar refs target fQName
                        |> Result.andThen
                            (\metaType2 ->
                                unifyMetaType metaType1 metaType2
                                    |> Result.andThen
                                        (\solutions ->
                                            if SolutionMap.isEmpty solutions then
                                                findSubstitution refs restOfConstraints

                                            else
                                                Ok (Just solutions)
                                        )
                            )


lookupMetaType : Variable -> References -> Target -> FQName -> Result TypeError MetaType
lookupMetaType baseVar refs target ((FQName packageName moduleName localName) as fQName) =
    case target of
        Ctor ->
            refs
                |> Dict.get packageName
                |> Maybe.andThen (.modules >> Dict.get moduleName)
                |> Maybe.andThen
                    (\moduleSpec ->
                        moduleSpec.types
                            |> Dict.toList
                            |> List.concatMap
                                (\( typeName, typeSpec ) ->
                                    case typeSpec.value of
                                        Type.CustomTypeSpecification paramNames ctors ->
                                            ctors
                                                |> List.filterMap
                                                    (\(Type.Constructor ctorName ctorArgs) ->
                                                        if ctorName == localName then
                                                            Just (ctorToMetaType baseVar (MetaRef (FQName packageName moduleName typeName)) paramNames (ctorArgs |> List.map Tuple.second))

                                                        else
                                                            Nothing
                                                    )

                                        _ ->
                                            []
                                )
                            |> List.head
                    )
                |> Result.fromMaybe (CouldNotFindConstructor fQName)

        Value ->
            refs
                |> Dict.get packageName
                |> Maybe.andThen (.modules >> Dict.get moduleName)
                |> Maybe.andThen (.values >> Dict.get localName)
                |> Maybe.map (valueSpecToMetaType baseVar)
                |> Result.fromMaybe (CouldNotFindValue fQName)


ctorToMetaType : Variable -> MetaType -> List Name -> List (Type ()) -> MetaType
ctorToMetaType baseVar baseType paramNames ctorArgs =
    let
        argVariables : Set Name
        argVariables =
            ctorArgs
                |> List.map Type.collectVariables
                |> List.foldl Set.union Set.empty

        allVariables : Set Name
        allVariables =
            paramNames
                |> Set.fromList
                |> Set.union argVariables

        varToMeta : Dict Name Variable
        varToMeta =
            allVariables
                |> concreteVarsToMetaVars baseVar

        recurse cargs =
            case cargs of
                [] ->
                    paramNames
                        |> List.foldl
                            (\paramName metaTypeSoFar ->
                                MetaApply metaTypeSoFar
                                    (varToMeta
                                        |> Dict.get paramName
                                        -- this should never happen
                                        |> Maybe.withDefault baseVar
                                        |> MetaVar
                                    )
                            )
                            baseType

                firstCtorArg :: restOfCtorArgs ->
                    MetaFun
                        (typeToMetaType baseVar varToMeta firstCtorArg)
                        (recurse restOfCtorArgs)
    in
    recurse ctorArgs


valueSpecToMetaType : Variable -> Value.Specification () -> MetaType
valueSpecToMetaType baseVar valueSpec =
    let
        specToFunctionType : List (Type ()) -> Type () -> Type ()
        specToFunctionType argTypes returnType =
            case argTypes of
                [] ->
                    returnType

                firstArg :: restOfArgs ->
                    Type.Function () firstArg (specToFunctionType restOfArgs returnType)

        functionType : Type ()
        functionType =
            specToFunctionType (valueSpec.inputs |> List.map Tuple.second) valueSpec.output

        varToMeta : Dict Name Variable
        varToMeta =
            functionType
                |> Type.collectVariables
                |> concreteVarsToMetaVars baseVar
    in
    typeToMetaType baseVar varToMeta functionType


concreteVarsToMetaVars : Variable -> Set Name -> Dict Name Variable
concreteVarsToMetaVars baseVar variables =
    variables
        |> Set.toList
        |> List.foldl
            (\varName ( metaVarSoFar, varToMetaSoFar ) ->
                let
                    nextVar =
                        metaVarSoFar |> MetaVar.subVariable
                in
                ( nextVar
                , varToMetaSoFar
                    |> Dict.insert varName nextVar
                )
            )
            ( baseVar, Dict.empty )
        |> Tuple.second


typeToMetaType : Variable -> Dict Name Variable -> Type () -> MetaType
typeToMetaType baseVar varToMeta tpe =
    case tpe of
        Type.Variable () varName ->
            varToMeta
                |> Dict.get varName
                -- this should never happen
                |> Maybe.withDefault baseVar
                |> MetaVar

        Type.Reference () fQName args ->
            let
                curry : List (Type ()) -> MetaType
                curry argsReversed =
                    case argsReversed of
                        [] ->
                            MetaRef fQName

                        lastArg :: initArgsReversed ->
                            MetaApply
                                (curry initArgsReversed)
                                (typeToMetaType baseVar varToMeta lastArg)
            in
            curry (args |> List.reverse)

        Type.Tuple () elemTypes ->
            MetaTuple
                (elemTypes
                    |> List.map (typeToMetaType baseVar varToMeta)
                )

        Type.Record () fieldTypes ->
            MetaRecord Nothing
                (fieldTypes
                    |> List.map
                        (\field ->
                            ( field.name, typeToMetaType baseVar varToMeta field.tpe )
                        )
                    |> Dict.fromList
                )

        Type.ExtensibleRecord () subjectName fieldTypes ->
            MetaRecord
                (varToMeta
                    |> Dict.get subjectName
                    |> Maybe.map MetaVar
                )
                (fieldTypes
                    |> List.map
                        (\field ->
                            ( field.name, typeToMetaType baseVar varToMeta field.tpe )
                        )
                    |> Dict.fromList
                )

        Type.Function () argType returnType ->
            MetaFun
                (typeToMetaType baseVar varToMeta argType)
                (typeToMetaType baseVar varToMeta returnType)

        Type.Unit () ->
            MetaUnit


addSolution : Variable -> MetaType -> SolutionMap -> Result TypeError SolutionMap
addSolution var newSolution (SolutionMap currentSolutions) =
    case Dict.get var currentSolutions of
        Just existingSolution ->
            -- Unify with the existing solution
            unifyMetaType existingSolution newSolution
                |> Result.map
                    (\(SolutionMap newSubstitutions) ->
                        -- If it unifies apply the substitutions to the existing solution and add all new substitutions
                        SolutionMap
                            (currentSolutions
                                |> Dict.insert var
                                    (existingSolution
                                        |> MetaType.substituteVariables (Dict.toList newSubstitutions)
                                    )
                                |> Dict.union newSubstitutions
                            )
                    )

        Nothing ->
            -- Simply substitute and insert the new solution
            currentSolutions
                |> Dict.insert var newSolution
                |> SolutionMap
                |> SolutionMap.substituteVariable var newSolution
                |> Ok


mergeSolutions : SolutionMap -> SolutionMap -> Result TypeError SolutionMap
mergeSolutions (SolutionMap newSolutions) currentSolutions =
    newSolutions
        |> Dict.toList
        |> List.foldl
            (\( var, newSolution ) solutionsSoFar ->
                solutionsSoFar
                    |> Result.andThen (addSolution var newSolution)
            )
            (Ok currentSolutions)


unifyMetaType : MetaType -> MetaType -> Result TypeError SolutionMap
unifyMetaType metaType1 metaType2 =
    if metaType1 == metaType2 then
        Ok SolutionMap.empty

    else
        case ( metaType1, metaType2 ) of
            ( MetaVar var1, _ ) ->
                unifyVariable var1 metaType2

            ( _, MetaVar var2 ) ->
                unifyVariable var2 metaType1

            ( MetaTuple elems1, _ ) ->
                unifyTuple elems1 metaType2

            ( MetaRef ref1, _ ) ->
                unifyRef ref1 metaType2

            ( MetaApply fun1 arg1, _ ) ->
                unifyApply fun1 arg1 metaType2

            ( MetaFun arg1 return1, _ ) ->
                unifyFun arg1 return1 metaType2

            other ->
                Debug.todo ("implement " ++ Debug.toString other)


unifyVariable : Variable -> MetaType -> Result TypeError SolutionMap
unifyVariable var1 metaType2 =
    Ok (SolutionMap.singleton var1 metaType2)


unifyTuple : List MetaType -> MetaType -> Result TypeError SolutionMap
unifyTuple elems1 metaType2 =
    case metaType2 of
        MetaTuple elems2 ->
            if List.length elems1 == List.length elems2 then
                List.map2 unifyMetaType elems1 elems2
                    |> ListOfResults.liftAllErrors
                    |> Result.mapError TypeErrors
                    |> Result.andThen
                        (\solutionMaps ->
                            solutionMaps
                                |> List.foldl
                                    (\nextSolutions resultSoFar ->
                                        resultSoFar
                                            |> Result.andThen
                                                (\solutionsSoFar ->
                                                    mergeSolutions solutionsSoFar nextSolutions
                                                )
                                    )
                                    (Ok SolutionMap.empty)
                        )

            else
                Debug.todo "implement"

        _ ->
            Debug.todo "implement"


unifyRef : FQName -> MetaType -> Result TypeError SolutionMap
unifyRef ref1 metaType2 =
    case metaType2 of
        MetaRef ref2 ->
            if ref1 == ref2 then
                Ok SolutionMap.empty

            else
                Err (TypeMismatch (MetaRef ref1) metaType2)

        other ->
            Debug.todo ("implement " ++ Debug.toString other)


unifyApply : MetaType -> MetaType -> MetaType -> Result TypeError SolutionMap
unifyApply fun1 arg1 metaType2 =
    case metaType2 of
        MetaApply fun2 arg2 ->
            Result.andThen identity
                (Result.map2 mergeSolutions
                    (unifyMetaType fun1 fun2)
                    (unifyMetaType arg1 arg2)
                )

        _ ->
            Debug.todo "implement"


unifyFun : MetaType -> MetaType -> MetaType -> Result TypeError SolutionMap
unifyFun arg1 return1 metaType2 =
    case metaType2 of
        MetaFun arg2 return2 ->
            Result.andThen identity
                (Result.map2 mergeSolutions
                    (unifyMetaType arg1 arg2)
                    (unifyMetaType return1 return2)
                )

        _ ->
            Debug.todo "implement"


applySolutionToAnnotatedDefinition : Value.Definition () ( va, Variable ) -> ( ConstraintSet, SolutionMap ) -> Value.Definition () ( va, Type () )
applySolutionToAnnotatedDefinition annotatedDef ( residualConstraints, solutionMap ) =
    annotatedDef
        |> Value.mapDefinitionAttributes identity
            (\( va, metaVar ) ->
                ( va
                , solutionMap
                    |> SolutionMap.get metaVar
                    |> Maybe.map (metaToConcreteType solutionMap)
                    |> Maybe.withDefault (metaVar |> MetaVar.toName |> Type.Variable ())
                )
            )


applySolutionToAnnotatedValue : Value () ( va, Variable ) -> ( ConstraintSet, SolutionMap ) -> TypedValue va
applySolutionToAnnotatedValue annotatedValue ( residualConstraints, solutionMap ) =
    annotatedValue
        |> Value.mapValueAttributes identity
            (\( va, metaVar ) ->
                ( va
                , solutionMap
                    |> SolutionMap.get metaVar
                    |> Maybe.map (metaToConcreteType solutionMap)
                    |> Maybe.withDefault (metaVar |> MetaVar.toName |> Type.Variable ())
                )
            )


metaToConcreteType : SolutionMap -> MetaType -> Type ()
metaToConcreteType solutionMap metaType =
    case metaType of
        MetaVar metaVar ->
            solutionMap
                |> SolutionMap.get metaVar
                |> Maybe.map (metaToConcreteType solutionMap)
                |> Maybe.withDefault (metaVar |> MetaVar.toName |> Type.Variable ())

        MetaTuple metaElems ->
            Type.Tuple ()
                (metaElems
                    |> List.map (metaToConcreteType solutionMap)
                )

        MetaRecord extends metaFields ->
            case extends of
                Nothing ->
                    Type.Record ()
                        (metaFields
                            |> Dict.toList
                            |> List.map
                                (\( fieldName, fieldType ) ->
                                    Type.Field fieldName
                                        (metaToConcreteType solutionMap fieldType)
                                )
                        )

                Just baseType ->
                    case baseType of
                        MetaVar metaVar ->
                            Type.ExtensibleRecord ()
                                (metaVar |> MetaVar.toName)
                                (metaFields
                                    |> Dict.toList
                                    |> List.map
                                        (\( fieldName, fieldType ) ->
                                            Type.Field fieldName
                                                (metaToConcreteType solutionMap fieldType)
                                        )
                                )

                        _ ->
                            Debug.todo ("implement " ++ Debug.toString metaType)

        MetaApply _ _ ->
            let
                uncurry mt =
                    case mt of
                        MetaApply mf ma ->
                            let
                                ( f, args ) =
                                    uncurry mf
                            in
                            ( f, args ++ [ ma ] )

                        _ ->
                            ( mt, [] )

                ( metaFun, metaArgs ) =
                    uncurry metaType
            in
            case metaFun of
                MetaRef fQName ->
                    metaArgs
                        |> List.map (metaToConcreteType solutionMap)
                        |> Type.Reference () fQName

                other ->
                    metaToConcreteType solutionMap other

        MetaFun argType returnType ->
            Type.Function ()
                (metaToConcreteType solutionMap argType)
                (metaToConcreteType solutionMap returnType)

        MetaRef fQName ->
            Type.Reference () fQName []

        MetaUnit ->
            Type.Unit ()


typeErrors : List TypeError -> TypeError
typeErrors errors =
    case errors of
        [ single ] ->
            single

        _ ->
            TypeErrors errors


metaTypeVarForValue : Value () ( va, Variable ) -> MetaType
metaTypeVarForValue value =
    value
        |> Value.valueAttribute
        |> Tuple.second
        |> MetaVar


metaTypeVarForPattern : Pattern ( va, Variable ) -> MetaType
metaTypeVarForPattern pattern =
    pattern
        |> Value.patternAttribute
        |> Tuple.second
        |> MetaVar
