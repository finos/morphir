module Morphir.Scala.Feature.Core exposing (..)

import Dict
import List
import List.Extra as ListExtra
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Pattern(..), Value(..))
import Morphir.Scala.AST as Scala exposing (Annotated, MemberDecl(..))
import Morphir.Scala.Common exposing (mapValueName)
import Morphir.Scala.WellKnownTypes exposing (anyVal)
import Set exposing (Set)


{-| Map a Morphir fully-qualified name to a Scala package path and name.
-}
mapFQNameToPathAndName : FQName -> ( Scala.Path, Name )
mapFQNameToPathAndName ( packagePath, modulePath, localName ) =
    let
        scalaModulePath =
            case modulePath |> List.reverse of
                [] ->
                    []

                lastName :: reverseModulePath ->
                    List.concat
                        [ packagePath
                            |> List.map (Name.toCamelCase >> String.toLower)
                        , reverseModulePath
                            |> List.reverse
                            |> List.map (Name.toCamelCase >> String.toLower)
                        , [ lastName
                                |> Name.toTitleCase
                          ]
                        ]
    in
    ( scalaModulePath
    , localName
    )


{-| Map Fully Qualified name Type Ref
-}
mapFQNameToTypeRef : FQName -> Scala.Type
mapFQNameToTypeRef fQName =
    let
        ( path, name ) =
            mapFQNameToPathAndName fQName
    in
    Scala.TypeRef path (name |> Name.toTitleCase)


{-| Map a module level type declaration in Morphir to a Scala member declaration.
-}
mapTypeMember : Package.PackageName -> Path -> AccessControlled (Module.Definition ta (Type ())) -> ( Name, AccessControlled (Documented (Type.Definition ta)) ) -> List (Scala.Annotated Scala.MemberDecl)
mapTypeMember currentPackagePath currentModulePath accessControlledModuleDef ( typeName, accessControlledDocumentedTypeDef ) =
    case accessControlledDocumentedTypeDef.value.value of
        Type.TypeAliasDefinition typeParams (Type.Record _ fields) ->
            [ Scala.withoutAnnotation
                (Scala.MemberTypeDecl
                    (Scala.Class
                        { modifiers = [ Scala.Final, Scala.Case ]
                        , name = typeName |> Name.toTitleCase
                        , typeArgs = typeParams |> List.map (Name.toTitleCase >> Scala.TypeVar)
                        , ctorArgs =
                            fields
                                |> List.map
                                    (\field ->
                                        { modifiers = []
                                        , tpe = mapType field.tpe
                                        , name = field.name |> Name.toCamelCase
                                        , defaultValue = Nothing
                                        }
                                    )
                                |> List.singleton
                        , extends = []
                        , members = []
                        , body = []
                        }
                    )
                )
            ]

        Type.TypeAliasDefinition typeParams typeExp ->
            [ Scala.withoutAnnotation
                (Scala.TypeAlias
                    { alias =
                        typeName |> Name.toTitleCase
                    , typeArgs =
                        typeParams |> List.map (Name.toTitleCase >> Scala.TypeVar)
                    , tpe =
                        mapType typeExp
                    }
                )
            ]

        Type.CustomTypeDefinition typeParams accessControlledCtors ->
            mapCustomTypeDefinition
                currentPackagePath
                currentModulePath
                accessControlledModuleDef.value
                typeName
                typeParams
                accessControlledCtors


mapModuleDefinition : Package.PackageName -> Path -> AccessControlled (Module.Definition ta (Type ())) -> List Scala.CompilationUnit
mapModuleDefinition currentPackagePath currentModulePath accessControlledModuleDef =
    let
        ( scalaPackagePath, moduleName ) =
            case currentModulePath |> List.reverse of
                [] ->
                    ( [], [] )

                lastName :: reverseModulePath ->
                    ( List.append (currentPackagePath |> List.map (Name.toCamelCase >> String.toLower)) (reverseModulePath |> List.reverse |> List.map (Name.toCamelCase >> String.toLower)), lastName )

        typeMembers : List (Scala.Annotated Scala.MemberDecl)
        typeMembers =
            accessControlledModuleDef.value.types
                |> Dict.toList
                |> List.concatMap
                    (\types ->
                        mapTypeMember currentPackagePath currentModulePath accessControlledModuleDef types
                    )

        functionMembers : List (Scala.Annotated Scala.MemberDecl)
        functionMembers =
            let
                gatherTypeNames tpe acc =
                    Type.collectVariables tpe |> Set.map Name.toTitleCase |> Set.union acc

                gatherAllTypeNames inputTypes =
                    inputTypes
                        |> List.foldl gatherTypeNames Set.empty
                        |> Set.toList
                        |> List.map Scala.TypeVar
            in
            accessControlledModuleDef.value.values
                |> Dict.toList
                |> List.concatMap
                    (\( valueName, accessControlledValueDef ) ->
                        [ Scala.FunctionDecl
                            { modifiers =
                                case accessControlledValueDef.access of
                                    Public ->
                                        []

                                    Private ->
                                        []
                            , name =
                                mapValueName valueName
                            , typeArgs =
                                accessControlledValueDef.value.value.inputTypes
                                    |> List.map (\( _, _, tpe ) -> tpe)
                                    |> (::) accessControlledValueDef.value.value.outputType
                                    |> gatherAllTypeNames
                            , args =
                                if List.isEmpty accessControlledValueDef.value.value.inputTypes then
                                    []

                                else
                                    accessControlledValueDef.value.value.inputTypes
                                        |> List.map
                                            (\( argName, a, argType ) ->
                                                [ { modifiers = []
                                                  , tpe = mapType argType
                                                  , name = mapValueName argName
                                                  , defaultValue = Nothing
                                                  }
                                                ]
                                            )
                            , returnType =
                                Just (mapType accessControlledValueDef.value.value.outputType)
                            , body =
                                Just (mapFunctionBody accessControlledValueDef.value.value)
                            }
                        ]
                    )
                |> List.map Scala.withoutAnnotation

        moduleUnit : Scala.CompilationUnit
        moduleUnit =
            { dirPath = scalaPackagePath
            , fileName = (moduleName |> Name.toTitleCase) ++ ".scala"
            , packageDecl = scalaPackagePath
            , imports = []
            , typeDecls =
                [ Scala.Documented (Just (String.join "" [ "Generated based on ", currentModulePath |> Path.toString Name.toTitleCase "." ]))
                    (Scala.Annotated []
                        (Scala.Object
                            { modifiers =
                                case accessControlledModuleDef.access of
                                    Public ->
                                        []

                                    Private ->
                                        []
                            , name =
                                moduleName |> Name.toTitleCase
                            , members =
                                List.append typeMembers functionMembers
                            , extends =
                                []
                            , body = Nothing
                            }
                        )
                    )
                ]
            }
    in
    [ moduleUnit ]


mapCustomTypeDefinition : Package.PackageName -> Path -> Module.Definition ta (Type ()) -> Name -> List Name -> AccessControlled (Type.Constructors a) -> List (Scala.Annotated Scala.MemberDecl)
mapCustomTypeDefinition currentPackagePath currentModulePath moduleDef typeName typeParams accessControlledCtors =
    let
        caseClass name args extends =
            if List.isEmpty args then
                Scala.Object
                    { modifiers = [ Scala.Case ]
                    , name = name |> Name.toTitleCase
                    , extends = extends
                    , members = []
                    , body = Nothing
                    }

            else
                Scala.Class
                    { modifiers = [ Scala.Final, Scala.Case ]
                    , name = name |> Name.toTitleCase
                    , typeArgs = typeParams |> List.map (Name.toTitleCase >> Scala.TypeVar)
                    , ctorArgs =
                        args
                            |> List.map
                                (\( argName, argType ) ->
                                    { modifiers = []
                                    , tpe = mapType argType
                                    , name = argName |> Name.toCamelCase
                                    , defaultValue = Nothing
                                    }
                                )
                            |> List.singleton
                    , extends = extends
                    , members = []
                    , body = []
                    }

        parentTraitRef : Scala.Type
        parentTraitRef =
            mapFQNameToTypeRef ( currentPackagePath, currentModulePath, typeName )

        ( parentPackagePath, parentTraitName ) =
            let
                ( thePath, theName ) =
                    mapFQNameToPathAndName ( currentPackagePath, currentModulePath, typeName )
            in
            ( thePath, theName |> Name.toTitleCase )

        companionObjectVal : Name -> Scala.MemberDecl
        companionObjectVal name =
            let
                companionTypeRef =
                    Scala.TypeOfValue (parentPackagePath ++ [ parentTraitName, name |> Name.toTitleCase ])
            in
            Scala.ValueDecl
                { modifiers = []
                , pattern = Scala.NamedMatch (name |> Name.toTitleCase)
                , valueType = Just companionTypeRef
                , value = Scala.Ref (parentPackagePath ++ [ parentTraitName ]) (name |> Name.toTitleCase)
                }

        sealedTraitHierarchy : List Scala.TypeDecl
        sealedTraitHierarchy =
            [ Scala.Trait
                { modifiers = [ Scala.Sealed ]
                , name = typeName |> Name.toTitleCase
                , typeArgs = typeParams |> List.map (Name.toTitleCase >> Scala.TypeVar)
                , extends = []
                , members = []
                }
            , Scala.Object
                { modifiers = []
                , name = typeName |> Name.toTitleCase
                , extends = []
                , members =
                    accessControlledCtors.value
                        |> Dict.toList
                        |> List.map
                            (\( ctorName, ctorArgs ) ->
                                Scala.withAnnotation []
                                    (caseClass
                                        ctorName
                                        ctorArgs
                                        (if List.isEmpty typeParams then
                                            [ parentTraitRef ]

                                         else
                                            [ Scala.TypeApply parentTraitRef (typeParams |> List.map (Name.toTitleCase >> Scala.TypeVar)) ]
                                        )
                                        |> Scala.MemberTypeDecl
                                    )
                            )
                , body = Nothing
                }
            ]

        companionHelpers =
            accessControlledCtors.value
                |> Dict.toList
                |> List.map
                    (\( ctorName, _ ) ->
                        Scala.withoutAnnotation (companionObjectVal ctorName)
                    )
    in
    case accessControlledCtors.value |> Dict.toList of
        [ ( ctorName, ctorArgs ) ] ->
            if ctorName == typeName then
                if List.length ctorArgs == 1 then
                    -- In this case we should encode this as a value type
                    [ Scala.withoutAnnotation
                        (Scala.MemberTypeDecl
                            (caseClass ctorName ctorArgs [ anyVal ])
                        )
                    ]

                else if List.length ctorArgs == 0 then
                    -- This handles constructors with no arguments. We explicitly create a type alias to represent the type
                    [ Scala.withoutAnnotation
                        (Scala.TypeAlias
                            { alias = typeName |> Name.toTitleCase
                            , typeArgs = []
                            , tpe = Scala.TypeOfValue [ typeName |> Name.toTitleCase ]
                            }
                        )
                    , Scala.withoutAnnotation
                        (Scala.MemberTypeDecl
                            (caseClass ctorName ctorArgs [])
                        )
                    ]

                else
                    [ Scala.withoutAnnotation
                        (Scala.MemberTypeDecl
                            (caseClass ctorName ctorArgs [])
                        )
                    ]

            else
                List.concat
                    [ sealedTraitHierarchy
                        |> List.map (Scala.MemberTypeDecl >> Scala.withoutAnnotation)
                    , companionHelpers
                    ]

        _ ->
            List.concat
                [ sealedTraitHierarchy
                    |> List.map (Scala.MemberTypeDecl >> Scala.withoutAnnotation)
                , companionHelpers
                ]


{-| Map a Morphir type to a Scala type.
-}
mapType : Type a -> Scala.Type
mapType tpe =
    case tpe of
        Type.Variable a name ->
            Scala.TypeVar (name |> Name.toTitleCase)

        Type.Reference a fQName argTypes ->
            let
                typeRef =
                    mapFQNameToTypeRef fQName
            in
            if List.isEmpty argTypes then
                typeRef

            else
                Scala.TypeApply typeRef (argTypes |> List.map mapType)

        Type.Tuple a elemTypes ->
            Scala.TupleType (elemTypes |> List.map mapType)

        Type.Record a fields ->
            Scala.StructuralType
                (fields
                    |> List.map
                        (\field ->
                            Scala.FunctionDecl
                                { modifiers = []
                                , name = mapValueName field.name
                                , typeArgs = []
                                , args = []
                                , returnType = Just (mapType field.tpe)
                                , body = Nothing
                                }
                        )
                )

        Type.ExtensibleRecord a argName fields ->
            Scala.StructuralType
                (fields
                    |> List.map
                        (\field ->
                            Scala.FunctionDecl
                                { modifiers = []
                                , name = mapValueName field.name
                                , typeArgs = []
                                , args = []
                                , returnType = Just (mapType field.tpe)
                                , body = Nothing
                                }
                        )
                )

        Type.Function a argType returnType ->
            Scala.FunctionType (mapType argType) (mapType returnType)

        Type.Unit a ->
            Scala.TypeRef [ "scala" ] "Unit"


{-| Generate Scala for a Morphir function body.
-}
mapFunctionBody : Value.Definition ta (Type ()) -> Scala.Value
mapFunctionBody valueDef =
    mapValue
        (valueDef.inputTypes
            |> List.map (\( name, _, _ ) -> name)
            |> Set.fromList
        )
        valueDef.body


{-| Generate Scala for a value.
-}
mapValue : Set Name -> Value ta (Type ()) -> Scala.Value
mapValue inScopeVars value =
    case value of
        Literal tpe literal ->
            let
                wrap : List String -> String -> Scala.Lit -> Scala.Value
                wrap modulePath moduleName lit =
                    Scala.Apply
                        (Scala.Ref modulePath moduleName)
                        [ Scala.ArgValue Nothing (Scala.Literal lit) ]
            in
            case literal of
                BoolLiteral v ->
                    Scala.Literal (Scala.BooleanLit v)

                CharLiteral v ->
                    wrap [ "morphir", "sdk", "Char" ] "from" (Scala.CharacterLit v)

                StringLiteral v ->
                    Scala.Literal (Scala.StringLit v)

                WholeNumberLiteral v ->
                    wrap [ "morphir", "sdk", "Basics" ] "Int" (Scala.IntegerLit v)

                FloatLiteral v ->
                    wrap [ "morphir", "sdk", "Basics" ] "Float" (Scala.FloatLit v)

                DecimalLiteral _ ->
                    Debug.todo "branch 'DecimalLiteral _' not implemented"


        Constructor constructorType fQName ->
            Scala.TypeAscripted
                (curryConstructorArgs inScopeVars constructorType fQName [])
                (mapType constructorType)

        Tuple a elemValues ->
            Scala.Tuple
                (elemValues |> List.map (mapValue inScopeVars))

        List a itemValues ->
            Scala.Apply
                (Scala.Ref [ "morphir", "sdk" ] "List")
                (itemValues
                    |> List.map (mapValue inScopeVars)
                    |> List.map (Scala.ArgValue Nothing)
                )

        Record tpe fieldValues ->
            case tpe of
                Type.Reference _ fQName typeArgs ->
                    let
                        ( path, name ) =
                            mapFQNameToPathAndName fQName
                    in
                    Scala.Apply (Scala.Ref path (name |> Name.toTitleCase))
                        (fieldValues
                            |> Dict.toList
                            |> List.map
                                (\( fieldName, fieldValue ) ->
                                    Scala.ArgValue (Just (mapValueName fieldName)) (mapValue inScopeVars fieldValue)
                                )
                        )

                _ ->
                    Scala.StructuralValue
                        (fieldValues
                            |> Dict.toList
                            |> List.map
                                (\( fieldName, fieldValue ) ->
                                    ( mapValueName fieldName, mapValue inScopeVars fieldValue )
                                )
                        )

        Variable a name ->
            Scala.Variable (mapValueName name)

        Reference a fQName ->
            let
                ( path, name ) =
                    mapFQNameToPathAndName fQName
            in
            Scala.Ref path (mapValueName name)

        Field a subjectValue fieldName ->
            Scala.Select (mapValue inScopeVars subjectValue) (mapValueName fieldName)

        FieldFunction tpe fieldName ->
            case tpe of
                Type.Function _ inputType _ ->
                    Scala.Lambda
                        [ ( "x", Just (mapType inputType) ) ]
                        (Scala.Select (Scala.Variable "x") (mapValueName fieldName))

                _ ->
                    Scala.Select Scala.Wildcard (mapValueName fieldName)

        Apply applyType applyFun applyArg ->
            let
                ( bottomFun, args ) =
                    Value.uncurryApply applyFun applyArg
            in
            case bottomFun of
                Constructor constructorType fQName ->
                    curryConstructorArgs inScopeVars constructorType fQName args

                _ ->
                    Scala.Apply
                        (mapValue inScopeVars applyFun)
                        [ Scala.ArgValue Nothing (mapValue inScopeVars applyArg)
                        ]

        Lambda lambdaType argPattern bodyValue ->
            let
                newInScopeVars : Set Name
                newInScopeVars =
                    Set.union
                        (Value.collectPatternVariables argPattern)
                        inScopeVars
            in
            case argPattern of
                AsPattern tpe (WildcardPattern _) alias ->
                    Scala.Lambda
                        [ ( mapValueName alias, Just (mapType tpe) ) ]
                        (mapValue newInScopeVars bodyValue)

                _ ->
                    Scala.TypeAscripted (Scala.MatchCases [ ( mapPattern argPattern, mapValue newInScopeVars bodyValue ) ]) (mapType lambdaType)

        LetDefinition _ _ _ _ ->
            let
                flattenLetDef : Value ta (Type ()) -> ( List ( Name, Value.Definition ta (Type ()) ), Value ta (Type ()) )
                flattenLetDef v =
                    case v of
                        LetDefinition a dName d inV ->
                            let
                                ( nestedDefs, nestedInValue ) =
                                    flattenLetDef inV
                            in
                            ( ( dName, d ) :: nestedDefs, nestedInValue )

                        _ ->
                            ( [], v )

                ( defs, finalInValue ) =
                    flattenLetDef value

                newInScopeVars : Set Name
                newInScopeVars =
                    Set.union
                        (defs |> List.map Tuple.first |> Set.fromList)
                        inScopeVars
            in
            Scala.Block
                (defs
                    |> List.map
                        (\( defName, def ) ->
                            if List.isEmpty def.inputTypes then
                                Scala.ValueDecl
                                    { modifiers = []
                                    , pattern = Scala.NamedMatch (mapValueName defName)
                                    , valueType = Just (mapType def.outputType)
                                    , value = mapValue newInScopeVars def.body
                                    }

                            else
                                Scala.FunctionDecl
                                    { modifiers = []
                                    , name = mapValueName defName
                                    , typeArgs = []
                                    , args =
                                        def.inputTypes
                                            |> List.map
                                                (\( argName, _, argType ) ->
                                                    [ { modifiers = []
                                                      , tpe = mapType argType
                                                      , name = argName |> Name.toCamelCase
                                                      , defaultValue = Nothing
                                                      }
                                                    ]
                                                )
                                    , returnType =
                                        Just (mapType def.outputType)
                                    , body =
                                        Just (mapValue newInScopeVars def.body)
                                    }
                        )
                )
                (mapValue newInScopeVars finalInValue)

        LetRecursion a defs inValue ->
            let
                newInScopeVars : Set Name
                newInScopeVars =
                    Set.union
                        (defs |> Dict.keys |> Set.fromList)
                        inScopeVars
            in
            Scala.Block
                (defs
                    |> Dict.toList
                    |> List.map
                        (\( defName, def ) ->
                            Scala.FunctionDecl
                                { modifiers = []
                                , name = mapValueName defName
                                , typeArgs = []
                                , args =
                                    if List.isEmpty def.inputTypes then
                                        []

                                    else
                                         def.inputTypes
                                            |> List.map
                                                (\( argName, _, argType ) ->
                                                    [{ modifiers = []
                                                    , tpe = mapType argType
                                                    , name = argName |> Name.toCamelCase
                                                    , defaultValue = Nothing
                                                    }]
                                                )

                                , returnType =
                                    Just (mapType def.outputType)
                                , body =
                                    Just (mapValue newInScopeVars def.body)
                                }
                        )
                )
                (mapValue newInScopeVars inValue)

        Destructure _ bindPattern bindValue inValue ->
            let
                newInScopeVars : Set Name
                newInScopeVars =
                    Set.union
                        (Value.collectPatternVariables bindPattern)
                        inScopeVars
            in
            Scala.Block
                [ Scala.ValueDecl
                    { modifiers = []
                    , pattern = mapPattern bindPattern
                    , valueType = Nothing
                    , value = mapValue newInScopeVars bindValue
                    }
                ]
                (mapValue newInScopeVars inValue)

        IfThenElse a condValue thenValue elseValue ->
            Scala.IfElse (mapValue inScopeVars condValue) (mapValue inScopeVars thenValue) (mapValue inScopeVars elseValue)

        PatternMatch a onValue cases ->
            Scala.Match (mapValue inScopeVars onValue)
                (cases
                    |> List.map
                        (\( casePattern, caseValue ) ->
                            let
                                newInScopeVars : Set Name
                                newInScopeVars =
                                    Set.union
                                        (Value.collectPatternVariables casePattern)
                                        inScopeVars
                            in
                            ( mapPattern casePattern, mapValue newInScopeVars caseValue )
                        )
                    |> Scala.MatchCases
                )

        UpdateRecord a subjectValue fieldUpdates ->
            Scala.Apply
                (Scala.Select (mapValue inScopeVars subjectValue) "copy")
                (fieldUpdates
                    |> Dict.map
                        (\fieldName fieldValue ->
                            Scala.ArgValue
                                (Just (mapValueName fieldName))
                                (mapValue inScopeVars fieldValue)
                        )
                    |> Dict.values
                )

        Unit a ->
            Scala.Unit


mapPattern : Pattern a -> Scala.Pattern
mapPattern pattern =
    case pattern of
        WildcardPattern a ->
            Scala.WildcardMatch

        AsPattern a (WildcardPattern _) alias ->
            Scala.NamedMatch (alias |> Name.toCamelCase)

        AsPattern a aliasedPattern alias ->
            Scala.AliasedMatch (alias |> Name.toCamelCase) (mapPattern aliasedPattern)

        TuplePattern a itemPatterns ->
            Scala.TupleMatch (itemPatterns |> List.map mapPattern)

        ConstructorPattern a fQName argPatterns ->
            let
                ( path, name ) =
                    mapFQNameToPathAndName fQName
            in
            Scala.UnapplyMatch path
                (name |> Name.toTitleCase)
                (argPatterns
                    |> List.map mapPattern
                )

        EmptyListPattern a ->
            Scala.EmptyListMatch

        HeadTailPattern a headPattern tailPattern ->
            Scala.HeadTailMatch
                (mapPattern headPattern)
                (mapPattern tailPattern)

        LiteralPattern a literal ->
            let
                map l =
                    case l of
                        BoolLiteral v ->
                            Scala.BooleanLit v

                        CharLiteral v ->
                            Scala.CharacterLit v

                        StringLiteral v ->
                            Scala.StringLit v

                        WholeNumberLiteral v ->
                            Scala.IntegerLit v

                        FloatLiteral v ->
                            Scala.FloatLit v

                        DecimalLiteral v ->
                            Scala.DecimalLit v
                        
            in
            Scala.LiteralMatch (map literal)

        UnitPattern a ->
            Scala.WildcardMatch


{-| Map IR value to Scala Value
-}
uniqueVarName : Set Name -> Int -> String
uniqueVarName varNamesInUse hint =
    let
        varsInUse =
            varNamesInUse
                |> Set.map mapValueName

        firstCandidate =
            "a" ++ String.fromInt hint

        findUnused h i =
            let
                candidate =
                    "a" ++ String.fromInt h ++ String.fromInt i
            in
            if varsInUse |> Set.member candidate then
                findUnused h (i + 1)

            else
                candidate
    in
    if varsInUse |> Set.member firstCandidate then
        findUnused 0 hint

    else
        firstCandidate


curryConstructorArgs : Set Name -> Type () -> FQName -> List (Value a (Type ())) -> Scala.Value
curryConstructorArgs inScopeVars constructorType constructorFQName constructorArgs =
    let
        -- Get the argument types from a curried function type
        extractArgTypes : Type () -> ( List (Type ()), Type () )
        extractArgTypes tpe =
            case tpe of
                Type.Function _ argType returnType ->
                    let
                        ( argTypes, finalReturnType ) =
                            extractArgTypes returnType
                    in
                    ( argType :: argTypes, finalReturnType )

                _ ->
                    ( [], tpe )

        -- Get the argument types of the constructor
        ( constructorArgTypes, constructorReturnType ) =
            extractArgTypes constructorType

        -- Collect the arguments that were not specified
        unspecifiedArgs : List ( String, Type () )
        unspecifiedArgs =
            constructorArgTypes
                |> List.drop (List.length constructorArgs)
                |> List.indexedMap
                    (\index argType ->
                        ( uniqueVarName inScopeVars index, argType )
                    )

        -- Wrap the constructor into as many lambdas as many unspecified arguments there are
        curryUnspecifiedArgs : List ( String, Type () ) -> Scala.Value -> List Scala.ArgValue -> Scala.Value
        curryUnspecifiedArgs argsToCurry scalaConstructorValue scalaArgumentsSpecified =
            case argsToCurry of
                ( firstArgName, firstArgType ) :: restOfArgs ->
                    Scala.Lambda [ ( firstArgName, Just (mapType firstArgType) ) ]
                        (curryUnspecifiedArgs restOfArgs scalaConstructorValue (scalaArgumentsSpecified ++ [ Scala.ArgValue Nothing (Scala.Variable firstArgName) ]))

                [] ->
                    Scala.TypeAscripted
                        (Scala.Apply scalaConstructorValue scalaArgumentsSpecified)
                        (mapType constructorReturnType)

        ( path, name ) =
            mapFQNameToPathAndName constructorFQName
    in
    case ( constructorArgTypes, unspecifiedArgs ) of
        ( [], _ ) ->
            Scala.Ref path (name |> Name.toTitleCase)

        ( [ _ ], [ _ ] ) ->
            Scala.Ref path (name |> Name.toTitleCase)

        _ ->
            curryUnspecifiedArgs
                unspecifiedArgs
                (Scala.Ref path (name |> Name.toTitleCase))
                (constructorArgs
                    |> List.map
                        (\arg ->
                            Scala.ArgValue Nothing (mapValue inScopeVars arg)
                        )
                )
