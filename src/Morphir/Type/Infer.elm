module Morphir.Type.Infer exposing (..)

import Dict exposing (Dict)
import Morphir.Compiler as Compiler
import Morphir.IR as IR exposing (IR)
import Morphir.IR.AccessControlled exposing (AccessControlled)
import Morphir.IR.Documented as Documented exposing (Documented)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Basics exposing (floatType)
import Morphir.IR.Type as Type exposing (Specification(..), Type)
import Morphir.IR.Value as Value exposing (Pattern(..), Value)
import Morphir.ListOfResults as ListOfResults
import Morphir.Type.Class as Class exposing (Class)
import Morphir.Type.Constraint as Constraint exposing (Constraint(..), class, equality, isRecursive)
import Morphir.Type.ConstraintSet as ConstraintSet exposing (ConstraintSet(..))
import Morphir.Type.MetaType as MetaType exposing (MetaType(..), Variable, metaFun, metaRecord, metaTuple, metaUnit, metaVar, variableByName)
import Morphir.Type.MetaTypeMapping exposing (LookupError(..), concreteTypeToMetaType, concreteVarsToMetaVars, lookupConstructor, lookupValue, metaTypeToConcreteType)
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


inferPackageDefinition : IR -> Package.Definition () va -> Result (List Compiler.Error) (Package.Definition () ( va, Type () ))
inferPackageDefinition refs packageDef =
    packageDef.modules
        |> Dict.toList
        |> List.map
            (\( moduleName, moduleDef ) ->
                inferModuleDefinition refs moduleName moduleDef.value
                    |> Result.map (AccessControlled moduleDef.access)
                    |> Result.map (Tuple.pair moduleName)
            )
        |> ListOfResults.liftAllErrors
        |> Result.map
            (\mappedModules ->
                { modules = Dict.fromList mappedModules
                }
            )


inferModuleDefinition : IR -> ModuleName -> Module.Definition () va -> Result Compiler.Error (Module.Definition () ( va, Type () ))
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
        |> ListOfResults.liftAllErrors
        |> Result.map
            (\mappedValues ->
                { types = moduleDef.types
                , values = Dict.fromList mappedValues
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


inferValueDefinition : IR -> Value.Definition () va -> Result TypeError (Value.Definition () ( va, Type () ))
inferValueDefinition ir def =
    let
        ( annotatedDef, lastVarIndex ) =
            annotateDefinition 1 def

        constraints : ConstraintSet
        constraints =
            let
                cs =
                    constrainDefinition
                        (MetaType.variableByIndex 0)
                        ir
                        Dict.empty
                        annotatedDef

                --_ =
                --    Debug.log "Generated constraints" (cs |> ConstraintSet.toList |> List.length)
            in
            cs

        solution : Result TypeError ( ConstraintSet, SolutionMap )
        solution =
            solve ir constraints

        --_ =
        --    Debug.log "Generated solutions" (solution |> Result.map (Tuple.second >> Solve.toList) |> Result.withDefault [] |> List.length)
    in
    solution
        |> Result.map (applySolutionToAnnotatedDefinition ir annotatedDef)


inferValue : IR -> Value () va -> Result TypeError (TypedValue va)
inferValue ir untypedValue =
    let
        ( annotatedValue, lastVarIndex ) =
            annotateValue 0 untypedValue

        constraints : ConstraintSet
        constraints =
            constrainValue ir
                Dict.empty
                annotatedValue

        solution : Result TypeError ( ConstraintSet, SolutionMap )
        solution =
            solve ir constraints
    in
    solution
        |> Result.map (applySolutionToAnnotatedValue ir annotatedValue)


annotateDefinition : Int -> Value.Definition ta va -> ( Value.Definition ta ( va, Variable ), Int )
annotateDefinition baseIndex def =
    let
        annotatedInputTypes : List ( Name, ( va, Variable ), Type ta )
        annotatedInputTypes =
            def.inputTypes
                |> List.indexedMap
                    (\index ( name, va, tpe ) ->
                        ( name, ( va, MetaType.variableByIndex (baseIndex + index) ), tpe )
                    )

        ( annotatedBody, lastVarIndex ) =
            annotateValue (baseIndex + List.length def.inputTypes) def.body
    in
    ( { inputTypes =
            annotatedInputTypes
      , outputType =
            def.outputType
      , body =
            annotatedBody
      }
    , lastVarIndex
    )


annotateValue : Int -> Value ta va -> ( Value ta ( va, Variable ), Int )
annotateValue baseIndex untypedValue =
    untypedValue
        |> Value.indexedMapValue (\index va -> ( va, MetaType.variableByIndex index )) baseIndex


constrainDefinition : Variable -> IR -> Dict Name Variable -> Value.Definition () ( va, Variable ) -> ConstraintSet
constrainDefinition baseVar ir vars def =
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
            Set.union inputTypeVars outputTypeVars
                |> Set.toList
                |> List.map
                    (\varName ->
                        ( varName, variableByName varName )
                    )
                |> Dict.fromList

        inputConstraints : ConstraintSet
        inputConstraints =
            def.inputTypes
                |> List.map
                    (\( _, ( _, thisTypeVar ), declaredType ) ->
                        equality
                            (metaVar thisTypeVar)
                            (concreteTypeToMetaType thisTypeVar ir varToMeta declaredType)
                    )
                |> ConstraintSet.fromList

        outputConstraints : ConstraintSet
        outputConstraints =
            ConstraintSet.singleton
                (equality
                    (metaTypeVarForValue def.body)
                    (concreteTypeToMetaType baseVar ir varToMeta def.outputType)
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
            constrainValue ir (vars |> Dict.union inputVars) def.body
    in
    ConstraintSet.concat
        [ inputConstraints
        , outputConstraints
        , bodyConstraints
        ]


constrainValue : IR -> Dict Name Variable -> Value () ( va, Variable ) -> ConstraintSet
constrainValue ir vars annotatedValue =
    case annotatedValue of
        Value.Literal ( _, thisTypeVar ) literalValue ->
            constrainLiteral thisTypeVar literalValue

        Value.Constructor ( _, thisTypeVar ) fQName ->
            lookupConstructor thisTypeVar ir fQName
                |> Result.map (equality (metaVar thisTypeVar))
                |> Result.map ConstraintSet.singleton
                |> Result.withDefault ConstraintSet.empty

        Value.Tuple ( _, thisTypeVar ) elems ->
            let
                elemsConstraints : List ConstraintSet
                elemsConstraints =
                    elems
                        |> List.map (constrainValue ir vars)

                tupleConstraint : ConstraintSet
                tupleConstraint =
                    ConstraintSet.singleton
                        (equality
                            (metaVar thisTypeVar)
                            (elems
                                |> List.map metaTypeVarForValue
                                |> metaTuple
                            )
                        )
            in
            ConstraintSet.concat (tupleConstraint :: elemsConstraints)

        Value.List ( _, thisTypeVar ) items ->
            let
                itemType : MetaType
                itemType =
                    metaVar (thisTypeVar |> MetaType.subVariable)

                listConstraint : Constraint
                listConstraint =
                    equality (metaVar thisTypeVar) (MetaType.listType itemType)

                itemConstraints : ConstraintSet
                itemConstraints =
                    items
                        |> List.map
                            (\item ->
                                constrainValue ir vars item
                                    |> ConstraintSet.insert (equality itemType (metaTypeVarForValue item))
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
                        |> Dict.values
                        |> List.map (constrainValue ir vars)
                        |> ConstraintSet.concat

                recordType : MetaType
                recordType =
                    fieldValues
                        |> Dict.map
                            (\_ fieldValue ->
                                metaTypeVarForValue fieldValue
                            )
                        |> metaRecord Nothing

                recordConstraints : ConstraintSet
                recordConstraints =
                    ConstraintSet.singleton
                        (equality (metaVar thisTypeVar) recordType)
            in
            ConstraintSet.concat
                [ fieldConstraints
                , recordConstraints
                ]

        Value.Variable ( _, varUse ) varName ->
            case vars |> Dict.get varName of
                Just varDecl ->
                    ConstraintSet.singleton (equality (metaVar varUse) (metaVar varDecl))

                Nothing ->
                    -- this should never happen if variables were validated earlier
                    ConstraintSet.empty

        Value.Reference ( _, thisTypeVar ) fQName ->
            lookupValue thisTypeVar ir fQName
                |> Result.map (equality (metaVar thisTypeVar))
                |> Result.map ConstraintSet.singleton
                |> Result.withDefault ConstraintSet.empty

        Value.Field ( _, thisTypeVar ) subjectValue fieldName ->
            let
                extendsVar : Variable
                extendsVar =
                    thisTypeVar
                        |> MetaType.subVariable

                fieldType : MetaType
                fieldType =
                    extendsVar
                        |> MetaType.subVariable
                        |> metaVar

                extensibleRecordType : MetaType
                extensibleRecordType =
                    metaRecord (Just extendsVar)
                        (Dict.singleton fieldName fieldType)

                fieldConstraints : ConstraintSet
                fieldConstraints =
                    ConstraintSet.fromList
                        [ equality (metaTypeVarForValue subjectValue) extensibleRecordType
                        , equality (metaVar thisTypeVar) fieldType
                        ]
            in
            ConstraintSet.concat
                [ constrainValue ir vars subjectValue
                , fieldConstraints
                ]

        Value.FieldFunction ( _, thisTypeVar ) fieldName ->
            let
                extendsVar : Variable
                extendsVar =
                    thisTypeVar
                        |> MetaType.subVariable

                fieldType : MetaType
                fieldType =
                    extendsVar
                        |> MetaType.subVariable
                        |> metaVar

                extensibleRecordType : MetaType
                extensibleRecordType =
                    metaRecord (Just extendsVar)
                        (Dict.singleton fieldName fieldType)
            in
            ConstraintSet.singleton
                (equality (metaVar thisTypeVar) (metaFun extensibleRecordType fieldType))

        Value.Apply ( _, thisTypeVar ) funValue argValue ->
            let
                funType : MetaType
                funType =
                    metaFun
                        (metaTypeVarForValue argValue)
                        (metaVar thisTypeVar)

                applyConstraints : ConstraintSet
                applyConstraints =
                    ConstraintSet.singleton
                        (equality (metaTypeVarForValue funValue) funType)
            in
            ConstraintSet.concat
                [ constrainValue ir vars funValue
                , constrainValue ir vars argValue
                , applyConstraints
                ]

        Value.Lambda ( _, thisTypeVar ) argPattern bodyValue ->
            let
                ( argVariables, argConstraints ) =
                    constrainPattern ir argPattern

                lambdaType : MetaType
                lambdaType =
                    metaFun
                        (metaTypeVarForPattern argPattern)
                        (metaTypeVarForValue bodyValue)

                lambdaConstraints : ConstraintSet
                lambdaConstraints =
                    ConstraintSet.singleton
                        (equality (metaVar thisTypeVar) lambdaType)

                bodyConstraints : ConstraintSet
                bodyConstraints =
                    constrainValue ir
                        (Dict.union argVariables vars)
                        bodyValue
            in
            ConstraintSet.concat
                [ lambdaConstraints
                , bodyConstraints
                , argConstraints
                ]

        Value.LetDefinition ( _, thisTypeVar ) defName def inValue ->
            let
                defConstraints : ConstraintSet
                defConstraints =
                    constrainDefinition thisTypeVar ir vars def

                defTypeVar : Variable
                defTypeVar =
                    thisTypeVar |> MetaType.subVariable

                defType : List MetaType -> MetaType -> MetaType
                defType argTypes returnType =
                    case argTypes of
                        [] ->
                            returnType

                        firstArg :: restOfArgs ->
                            metaFun firstArg (defType restOfArgs returnType)

                inConstraints : ConstraintSet
                inConstraints =
                    constrainValue ir
                        (vars |> Dict.insert defName defTypeVar)
                        inValue

                letConstraints : ConstraintSet
                letConstraints =
                    ConstraintSet.fromList
                        [ equality (metaVar thisTypeVar) (metaTypeVarForValue inValue)
                        , equality (metaVar defTypeVar)
                            (defType
                                (def.inputTypes |> List.map (\( _, ( _, argTypeVar ), _ ) -> metaVar argTypeVar))
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
                            metaFun firstArg (defType restOfArgs returnType)

                ( lastDefTypeVar, defDeclsConstraints, defVariables ) =
                    defs
                        |> Dict.toList
                        |> List.foldl
                            (\( defName, def ) ( lastTypeVar, constraintsSoFar, variablesSoFar ) ->
                                let
                                    nextTypeVar : Variable
                                    nextTypeVar =
                                        lastTypeVar |> MetaType.subVariable

                                    letConstraint : ConstraintSet
                                    letConstraint =
                                        ConstraintSet.fromList
                                            [ equality (metaVar nextTypeVar)
                                                (defType
                                                    (def.inputTypes |> List.map (\( _, ( _, argTypeVar ), _ ) -> metaVar argTypeVar))
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
                                        lastTypeVar |> MetaType.subVariable

                                    defConstraints : ConstraintSet
                                    defConstraints =
                                        constrainDefinition lastTypeVar ir vars def
                                in
                                ( nextTypeVar, defConstraints :: constraintsSoFar )
                            )
                            ( lastDefTypeVar, defDeclsConstraints )
                        |> Tuple.second
                        |> ConstraintSet.concat

                inConstraints : ConstraintSet
                inConstraints =
                    constrainValue ir
                        (vars |> Dict.union (defVariables |> Dict.fromList))
                        inValue

                letConstraints : ConstraintSet
                letConstraints =
                    ConstraintSet.fromList
                        [ equality (metaVar thisTypeVar) (metaTypeVarForValue inValue)
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
                    constrainPattern ir bindPattern

                bindValueConstraints : ConstraintSet
                bindValueConstraints =
                    constrainValue ir vars bindValue

                inValueConstraints : ConstraintSet
                inValueConstraints =
                    constrainValue ir (Dict.union bindPatternVariables vars) inValue

                destructureConstraints : ConstraintSet
                destructureConstraints =
                    ConstraintSet.fromList
                        [ equality (metaVar thisTypeVar) (metaTypeVarForValue inValue)
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
                        , equality (metaVar thisTypeVar) (metaTypeVarForValue thenBranch)
                        ]

                childConstraints : List ConstraintSet
                childConstraints =
                    [ constrainValue ir vars condition
                    , constrainValue ir vars thenBranch
                    , constrainValue ir vars elseBranch
                    ]
            in
            ConstraintSet.concat (specificConstraints :: childConstraints)

        Value.PatternMatch ( _, thisTypeVar ) subjectValue cases ->
            let
                thisType : MetaType
                thisType =
                    metaVar thisTypeVar

                subjectType : MetaType
                subjectType =
                    metaTypeVarForValue subjectValue

                subjectConstraints : ConstraintSet
                subjectConstraints =
                    constrainValue ir vars subjectValue

                casesConstraints : List ConstraintSet
                casesConstraints =
                    cases
                        |> List.map
                            (\( casePattern, caseValue ) ->
                                let
                                    ( casePatternVariables, casePatternConstraints ) =
                                        constrainPattern ir casePattern

                                    caseValueConstraints : ConstraintSet
                                    caseValueConstraints =
                                        constrainValue ir (Dict.union casePatternVariables vars) caseValue

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
            ConstraintSet.concat (subjectConstraints :: casesConstraints)

        Value.UpdateRecord ( _, thisTypeVar ) subjectValue fieldValues ->
            let
                extendsVar : Variable
                extendsVar =
                    thisTypeVar
                        |> MetaType.subVariable

                extensibleRecordType : MetaType
                extensibleRecordType =
                    metaRecord (Just extendsVar)
                        (fieldValues
                            |> Dict.map
                                (\_ fieldValue ->
                                    metaTypeVarForValue fieldValue
                                )
                        )

                fieldValueConstraints : ConstraintSet
                fieldValueConstraints =
                    fieldValues
                        |> Dict.toList
                        |> List.map
                            (\( _, fieldValue ) ->
                                constrainValue ir vars fieldValue
                            )
                        |> ConstraintSet.concat

                fieldConstraints : ConstraintSet
                fieldConstraints =
                    ConstraintSet.fromList
                        [ equality (metaTypeVarForValue subjectValue) extensibleRecordType
                        , equality (metaVar thisTypeVar) (metaTypeVarForValue subjectValue)
                        ]
            in
            ConstraintSet.concat
                [ constrainValue ir vars subjectValue
                , fieldValueConstraints
                , fieldConstraints
                ]

        Value.Unit ( _, thisTypeVar ) ->
            ConstraintSet.singleton
                (equality (metaVar thisTypeVar) metaUnit)


{-| Function that extracts variables and generates constraints for a pattern.
-}
constrainPattern : IR -> Pattern ( va, Variable ) -> ( Dict Name Variable, ConstraintSet )
constrainPattern ir pattern =
    case pattern of
        Value.WildcardPattern ( va, thisTypeVar ) ->
            ( Dict.empty
            , ConstraintSet.empty
            )

        Value.AsPattern ( va, thisTypeVar ) nestedPattern alias ->
            let
                ( nestedVariables, nestedConstraints ) =
                    constrainPattern ir nestedPattern

                thisPatternConstraints : ConstraintSet
                thisPatternConstraints =
                    ConstraintSet.singleton
                        (equality (metaVar thisTypeVar) (metaTypeVarForPattern nestedPattern))
            in
            ( nestedVariables |> Dict.insert alias thisTypeVar
            , ConstraintSet.union nestedConstraints thisPatternConstraints
            )

        Value.TuplePattern ( va, thisTypeVar ) elemPatterns ->
            let
                ( elemsVariables, elemsConstraints ) =
                    elemPatterns
                        |> List.map (constrainPattern ir)
                        |> List.unzip

                tupleConstraint : ConstraintSet
                tupleConstraint =
                    ConstraintSet.singleton
                        (equality
                            (metaVar thisTypeVar)
                            (elemPatterns
                                |> List.map metaTypeVarForPattern
                                |> metaTuple
                            )
                        )
            in
            ( List.foldl Dict.union Dict.empty elemsVariables
            , ConstraintSet.concat (tupleConstraint :: elemsConstraints)
            )

        Value.ConstructorPattern ( va, thisTypeVar ) fQName argPatterns ->
            let
                ctorTypeVar : Variable
                ctorTypeVar =
                    thisTypeVar |> MetaType.subVariable

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

                customTypeConstraint : ConstraintSet
                customTypeConstraint =
                    lookupConstructor ctorTypeVar ir fQName
                        |> Result.map
                            (\ctorFunType ->
                                ConstraintSet.fromList
                                    [ equality (metaVar ctorTypeVar) ctorFunType
                                    , equality (metaVar thisTypeVar) (resultType ctorFunType)
                                    ]
                            )
                        |> Result.withDefault ConstraintSet.empty

                ctorFunConstraint : ConstraintSet
                ctorFunConstraint =
                    ConstraintSet.singleton
                        (equality
                            (metaVar ctorTypeVar)
                            (ctorType
                                (argPatterns
                                    |> List.map metaTypeVarForPattern
                                )
                            )
                        )

                ( argVariables, argConstraints ) =
                    argPatterns
                        |> List.map (constrainPattern ir)
                        |> List.unzip
            in
            ( List.foldl Dict.union Dict.empty argVariables
            , ConstraintSet.concat (customTypeConstraint :: ctorFunConstraint :: argConstraints)
            )

        Value.EmptyListPattern ( va, thisTypeVar ) ->
            let
                itemType : MetaType
                itemType =
                    metaVar (thisTypeVar |> MetaType.subVariable)

                listType : MetaType
                listType =
                    MetaType.listType itemType
            in
            ( Dict.empty
            , ConstraintSet.singleton
                (equality (metaVar thisTypeVar) listType)
            )

        Value.HeadTailPattern ( va, thisTypeVar ) headPattern tailPattern ->
            let
                ( headVariables, headConstraints ) =
                    constrainPattern ir headPattern

                ( tailVariables, tailConstraints ) =
                    constrainPattern ir tailPattern

                itemType : MetaType
                itemType =
                    metaTypeVarForPattern headPattern

                listType : MetaType
                listType =
                    MetaType.listType itemType

                thisPatternConstraints : ConstraintSet
                thisPatternConstraints =
                    ConstraintSet.fromList
                        [ equality (metaVar thisTypeVar) listType
                        , equality (metaTypeVarForPattern tailPattern) listType
                        ]
            in
            ( Dict.union headVariables tailVariables
            , ConstraintSet.concat
                [ headConstraints, tailConstraints, thisPatternConstraints ]
            )

        Value.LiteralPattern ( va, thisTypeVar ) literalValue ->
            ( Dict.empty
            , constrainLiteral thisTypeVar literalValue
            )

        Value.UnitPattern ( va, thisTypeVar ) ->
            ( Dict.empty
            , ConstraintSet.singleton
                (equality (metaVar thisTypeVar) metaUnit)
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


solve : IR -> ConstraintSet -> Result TypeError ( ConstraintSet, SolutionMap )
solve refs constraintSet =
    solveHelp refs Solve.emptySolution constraintSet


solveHelp : IR -> SolutionMap -> ConstraintSet -> Result TypeError ( ConstraintSet, SolutionMap )
solveHelp refs solutionsSoFar ((ConstraintSet constraints) as constraintSet) =
    --let
    --    _ =
    --        Debug.log "constraints so far" (constraints |> List.length)
    --
    --    _ =
    --        Debug.log "solutions so far" (solutionsSoFar |> Solve.toList |> List.length)
    --in
    case validateConstraints constraints of
        Ok nonTrivialConstraints ->
            case Solve.findSubstitution refs nonTrivialConstraints of
                Ok maybeNewSolutions ->
                    case maybeNewSolutions of
                        Nothing ->
                            Ok ( ConstraintSet.fromList nonTrivialConstraints, solutionsSoFar )

                        Just newSolutions ->
                            case Solve.mergeSolutions refs newSolutions solutionsSoFar of
                                Ok mergedSolutions ->
                                    let
                                        -- Compare the latest set of solutions to the previous set and keep only the new solutions
                                        newMergedSolutions : SolutionMap
                                        newMergedSolutions =
                                            solutionsSoFar |> Solve.diff mergedSolutions
                                    in
                                    solveHelp refs mergedSolutions (constraintSet |> ConstraintSet.applySubstitutions newMergedSolutions)

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
        |> ListOfResults.liftAllErrors
        |> Result.mapError typeErrors


applySolutionToAnnotatedDefinition : IR -> Value.Definition ta ( va, Variable ) -> ( ConstraintSet, SolutionMap ) -> Value.Definition ta ( va, Type () )
applySolutionToAnnotatedDefinition ir annotatedDef ( residualConstraints, solutionMap ) =
    annotatedDef
        |> Value.mapDefinitionAttributes identity
            (\( va, metaVar ) ->
                ( va
                , solutionMap
                    |> Solve.get metaVar
                    |> Maybe.map (metaTypeToConcreteType solutionMap)
                    |> Maybe.withDefault (metaVar |> MetaType.toName |> Type.Variable ())
                )
            )
        |> (\valDef -> { valDef | body = valDef.body |> fixNumberLiterals ir })


applySolutionToAnnotatedValue : IR -> Value () ( va, Variable ) -> ( ConstraintSet, SolutionMap ) -> TypedValue va
applySolutionToAnnotatedValue ir annotatedValue ( residualConstraints, solutionMap ) =
    annotatedValue
        |> Value.mapValueAttributes identity
            (\( va, metaVar ) ->
                ( va
                , solutionMap
                    |> Solve.get metaVar
                    |> Maybe.map (metaTypeToConcreteType solutionMap)
                    |> Maybe.withDefault (metaVar |> MetaType.toName |> Type.Variable ())
                )
            )
        |> fixNumberLiterals ir


fixNumberLiterals : IR -> Value ta ( va, Type () ) -> Value ta ( va, Type () )
fixNumberLiterals ir typedValue =
    typedValue
        |> Value.rewriteValue
            (\value ->
                case value of
                    Value.Literal ( va, tpe ) (WholeNumberLiteral v) ->
                        if (ir |> IR.resolveType tpe) == floatType () then
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
