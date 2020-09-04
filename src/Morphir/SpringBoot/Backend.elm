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


module Morphir.SpringBoot.Backend exposing (..)

import Dict exposing (Dict)
import List.Extra as ListExtra
import Maybe.Extra as MaybeExtra exposing (..)
import Morphir.File.FileMap exposing (FileMap)
import Morphir.IR.AccessControlled as AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Module as Module exposing (Specification)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Type as Type exposing (Definition(..), Type)
import Morphir.IR.Value as Value exposing (Pattern(..), Value(..))
import Morphir.SpringBoot.PrettyPrinter as PrettyPrinter
import Morphir.SpringBoot.AST as SpringBoot exposing (ArgDecl)
import Set exposing (Set)



type alias Options =
    {}


mapDistribution : Options -> Package.Distribution -> FileMap
mapDistribution opt distro =
    case distro of
        Package.Library packagePath packageDef ->
            mapPackageDefinition opt packagePath packageDef


mapPackageDefinition : Options -> Package.PackagePath -> Package.Definition a -> FileMap
mapPackageDefinition opt packagePath packageDef =
    packageDef.modules
        |> Dict.toList
        |> List.concatMap
            (\( modulePath, moduleImpl ) ->
                (mapMainAppDefinition opt packagePath modulePath moduleImpl
                    |> List.map
                        (\compilationUnit ->
                            let
                                fileContent =
                                    compilationUnit
                                        |> PrettyPrinter.mapCompilationUnit (PrettyPrinter.Options 2 80)
                            in
                            ( ( compilationUnit.dirPath, compilationUnit.fileName ), fileContent )
                        )
                )
                |> List.append
                    (mapModuleDefinition opt packagePath modulePath moduleImpl
                        |> List.map
                            (\compilationUnit ->
                                let
                                    fileContent =
                                        compilationUnit
                                            |> PrettyPrinter.mapCompilationUnit (PrettyPrinter.Options 2 80)
                                in
                                    ( ( compilationUnit.dirPath, compilationUnit.fileName ), fileContent )
                            )
                    )
                |> List.append
                    (mapStatefulAppDefinition opt packagePath modulePath moduleImpl
                        |> List.map
                            (\compilationUnit ->
                                let
                                    fileContent =
                                        compilationUnit
                                            |> PrettyPrinter.mapCompilationUnit (PrettyPrinter.Options 2 80)
                                in
                                    ( ( compilationUnit.dirPath, compilationUnit.fileName ), fileContent )
                            )
                    )
            )
        |> Dict.fromList

mapFQNameToPathAndName : FQName -> ( SpringBoot.Path, Name )
mapFQNameToPathAndName (FQName packagePath modulePath localName) =
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


mapFQNameToTypeRef : FQName -> SpringBoot.Type
mapFQNameToTypeRef fQName =
    let
        ( path, name ) =
            mapFQNameToPathAndName fQName
    in
    SpringBoot.TypeRef path (name |> Name.toTitleCase)

mapMainAppDefinition : Options -> Package.PackagePath -> Path -> AccessControlled (Module.Definition a) -> List SpringBoot.CompilationUnit
mapMainAppDefinition opt currentPackagePath currentModulePath accessControlledModuleDef =
    let
        ( scalaPackagePath, moduleName ) =
            case currentModulePath |> List.reverse of
                [] ->
                    ( [], [] )

                lastName :: reverseModulePath ->
                    ( List.append (currentPackagePath |> List.map (Name.toCamelCase >> String.toLower)) (reverseModulePath |> List.reverse |> List.map (Name.toCamelCase >> String.toLower)), lastName )

        mainUnit : SpringBoot.CompilationUnit
        mainUnit =
            { dirPath = scalaPackagePath
            , fileName = (moduleName |> Name.toTitleCase) ++ ".scala"
            , packageDecl = scalaPackagePath
            , imports = []
            , typeDecls =
                [
                 (SpringBoot.Documented Nothing (SpringBoot.Annotated (Just ["@org.springframework.boot.autoconfigure.SpringBootApplication"])
                    <|
                        (SpringBoot.Class
                            { modifiers = []
                            , name = moduleName |> Name.toTitleCase
                              , typeArgs = []
                              , ctorArgs = []
                              , extends = [ ]
                              , members = []
                              }
                        )
                    )),
                 (SpringBoot.Documented (Just (String.join "" [ "Generated based on ", currentModulePath |> Path.toString Name.toTitleCase "." ]))
                    (SpringBoot.Annotated (Nothing)
                         <|
                         (SpringBoot.Object
                             { modifiers =
                                 []
                             , name =
                                 moduleName |> Name.toTitleCase
                             , members =
                                 []
                             , extends =
                                 [SpringBoot.TypeVar "App"]
                             , body =
                                 Just (SpringBoot.Ref ["org.springframework.boot.SpringApplication"] ("run(classOf[" ++ (moduleName |> Name.toTitleCase) ++ "], args:_*)"))
                             }
                         )
                    )
                 )
                ]
            }
    in
    [ mainUnit ]


mapStatefulAppDefinition : Options -> Package.PackagePath -> Path -> AccessControlled (Module.Definition a) -> List SpringBoot.CompilationUnit
mapStatefulAppDefinition opt currentPackagePath currentModulePath accessControlledModuleDef =
    let
        functionName: Name
        functionName =
            case accessControlledModuleDef.access of
                Public ->
                    case accessControlledModuleDef.value of
                        { types, values } ->
                            case (Dict.get (Name.fromString "app") values) of
                                Just acsCtrlValueDef ->
                                    case acsCtrlValueDef.access of
                                        Public ->
                                            case acsCtrlValueDef.value.body of
                                                Value.Apply _ (Constructor _ _) (Value.Reference _ (FQName _ _ name)) ->
                                                    name
                                                _ -> []
                                        _ -> []
                                _ -> []
                _ -> []
        _ = Debug.log "functionName" functionName

        statefulAppDefinition :  List (SpringBoot.Documented (SpringBoot.Annotated SpringBoot.MemberDecl))
        statefulAppDefinition =
            accessControlledModuleDef.value.values
                |> Dict.toList
                    |> List.concatMap
                        (\( valueName, accessControlledValueDef ) ->
                            case (accessControlledValueDef.value.inputTypes, accessControlledValueDef.value.outputType) of
                                ((keyVariable :: stateVariable :: commandVariable :: []) , Type.Tuple _ (keyType :: stateType :: eventType :: []) ) ->
                                    [(SpringBoot.Documented (Nothing)
                                       (SpringBoot.Annotated (Just ["@org.springframework.web.bind.annotation.RequestMapping(value = Array(\"/" ++ (valueName |> Name.toCamelCase) ++ "\"), method = Array(org.springframework.web.bind.annotation.RequestMethod.GET))"])
                                       <|
                                        (SpringBoot.FunctionDecl
                                            { modifiers = []
                                            , name =
                                                (valueName |> Name.toCamelCase)
                                            , typeArgs =
                                                []
                                            , args =
                                                if List.isEmpty accessControlledValueDef.value.inputTypes then
                                                    []
                                                else
                                                    [ accessControlledValueDef.value.inputTypes
                                                        |> List.map
                                                            (\( argName, a, argType ) ->
                                                                { modifiers = []
                                                                , tpe = mapType argType
                                                                , name = argName |> Name.toCamelCase
                                                                , defaultValue = Nothing
                                                                }
                                                            )
                                                    ]
                                            , returnType =
                                                Just (mapType accessControlledValueDef.value.outputType)
                                            , body =
                                                Nothing
                                               -- Just (mapValue accessControlledValueDef.value.body)
                                            }
                                         )
                                        )
                                        )]
                                _ ->
                                    []

                        )

        typeMembers : List (SpringBoot.MemberDecl)
        typeMembers =
            accessControlledModuleDef.value.types
                |> Dict.toList
                |> List.concatMap
                    (\( typeName, accessControlledDocumentedTypeDef ) ->
                        case accessControlledDocumentedTypeDef.value.value of
                            Type.TypeAliasDefinition typeParams (Type.Record _ fields) ->
                                [
                                    SpringBoot.MemberTypeDecl
                                    (SpringBoot.Class
                                        { modifiers = [ SpringBoot.Case ]
                                        , name = typeName |> Name.toTitleCase
                                        , typeArgs = typeParams |> List.map (Name.toTitleCase >> SpringBoot.TypeVar)
                                        , ctorArgs =
                                            fields
                                                |> List.map
                                                    (\field ->
                                                        { modifiers = []
                                                        , tpe = mapType field.tpe
                                                        , name = ""
                                                        , defaultValue = Nothing
                                                        }
                                                    )
                                                |> List.singleton
                                        , extends = []
                                        , members = []
                                        }
                                    )
                                ]

                            Type.TypeAliasDefinition typeParams typeExp ->
                                [
                                    SpringBoot.TypeAlias
                                    { alias =
                                        typeName |> Name.toTitleCase
                                    , typeArgs =
                                        typeParams |> List.map (Name.toTitleCase >> SpringBoot.TypeVar)
                                    , tpe =
                                        mapType typeExp
                                    }
                                ]

                            Type.CustomTypeDefinition typeParams accessControlledCtors ->
                                    mapCustomTypeDefinition currentPackagePath currentModulePath typeName typeParams accessControlledCtors
                    )

        ( scalaPackagePath, moduleName ) =
                    case currentModulePath |> List.reverse of
                        [] ->
                            ( [], [] )

                        lastName :: reverseModulePath ->
                            ( List.append (currentPackagePath |> List.map (Name.toCamelCase >> String.toLower)) (reverseModulePath |> List.reverse |> List.map (Name.toCamelCase >> String.toLower)), lastName )

        moduleUnit : SpringBoot.CompilationUnit
        moduleUnit =
            { dirPath = scalaPackagePath
            , fileName = "Controller" ++ (moduleName |> Name.toTitleCase) ++ ".scala"
            , packageDecl = scalaPackagePath
            , imports = []
            , typeDecls =
                [
                 (SpringBoot.Documented (Just (String.join "" [ "Generated based on ", currentModulePath |> Path.toString Name.toTitleCase "." ]))
                    (SpringBoot.Annotated (Just ["@org.springframework.web.bind.annotation.RestController"])
                         <|
                         (SpringBoot.Class
                             { modifiers =
                                         []
                             , name =
                                 (moduleName |> Name.toTitleCase) ++ "Controller"
                             , typeArgs =
                                 []
                             , ctorArgs =
                                 []
                             , extends =
                                 []
                             , members =
                                 typeMembers
                                  |> List.map
                                    (\( typed ) ->
                                        (SpringBoot.Documented (Nothing)
                                           (SpringBoot.Annotated (Nothing)
                                            <| typed
                                            )
                                        )
                                    )
                                  |> List.append statefulAppDefinition
                             }
                         )
                    )
                 )
                ]
            }
    in
    [ moduleUnit ]


mapModuleDefinition : Options -> Package.PackagePath -> Path -> AccessControlled (Module.Definition a) -> List SpringBoot.CompilationUnit
mapModuleDefinition opt currentPackagePath currentModulePath accessControlledModuleDef =
    let
        _ = Debug.log "accessControlledModuleDef" accessControlledModuleDef.value.types
        ( scalaPackagePath, moduleName ) =
            case currentModulePath |> List.reverse of
                [] ->
                    ( [], [] )

                lastName :: reverseModulePath ->
                    ( List.append (currentPackagePath |> List.map (Name.toCamelCase >> String.toLower)) (reverseModulePath |> List.reverse |> List.map (Name.toCamelCase >> String.toLower)), lastName )

        typeMembers : List SpringBoot.MemberDecl
        typeMembers =
            accessControlledModuleDef.value.types
                |> Dict.toList
                |> List.concatMap
                    (\( typeName, accessControlledDocumentedTypeDef ) ->
                        case accessControlledDocumentedTypeDef.value.value of
                            Type.TypeAliasDefinition typeParams (Type.Record _ fields) ->
                                [ SpringBoot.MemberTypeDecl
                                    (SpringBoot.Class
                                        { modifiers = [ SpringBoot.Case ]
                                        , name = typeName |> Name.toTitleCase
                                        , typeArgs = typeParams |> List.map (Name.toTitleCase >> SpringBoot.TypeVar)
                                        , ctorArgs =
                                            fields
                                                |> List.map
                                                    (\field ->
                                                        { modifiers = []
                                                        , tpe = mapType field.tpe
                                                        , name = ""
                                                        , defaultValue = Nothing
                                                        }
                                                    )
                                                |> List.singleton
                                        , extends = []
                                        , members = []
                                        }
                                    )
                                ]

                            Type.TypeAliasDefinition typeParams typeExp ->
                                [ SpringBoot.TypeAlias
                                    { alias =
                                        typeName |> Name.toTitleCase
                                    , typeArgs =
                                        typeParams |> List.map (Name.toTitleCase >> SpringBoot.TypeVar)
                                    , tpe =
                                        mapType typeExp
                                    }
                                ]

                            Type.CustomTypeDefinition typeParams accessControlledCtors ->
                                mapCustomTypeDefinition currentPackagePath currentModulePath typeName typeParams accessControlledCtors
                    )

        functionMembers : List SpringBoot.MemberDecl
        functionMembers =
            accessControlledModuleDef.value.values
                |> Dict.toList
                |> List.concatMap
                    (\( valueName, accessControlledValueDef ) ->
                        [ SpringBoot.FunctionDecl
                            { modifiers =
                                case accessControlledValueDef.access of
                                    Public ->
                                        []

                                    Private ->
                                        [ SpringBoot.Private Nothing ]
                            , name =
                                valueName |> Name.toCamelCase
                            , typeArgs =
                                []
                            , args =
                                if List.isEmpty accessControlledValueDef.value.inputTypes then
                                    []

                                else
                                    [ accessControlledValueDef.value.inputTypes
                                        |> List.map
                                            (\( argName, a, argType ) ->
                                                { modifiers = []
                                                , tpe = mapType argType
                                                , name = argName |> Name.toCamelCase
                                                , defaultValue = Nothing
                                                }
                                            )
                                    ]
                            , returnType =
                                Just (mapType accessControlledValueDef.value.outputType)
                            , body =
                                Just (mapValue accessControlledValueDef.value.body)
                            }
                        ]
                    )

        moduleUnit : SpringBoot.CompilationUnit
        moduleUnit =
            { dirPath = scalaPackagePath
            , fileName = "Modules" ++ (moduleName |> Name.toTitleCase) ++ ".scala"
            , packageDecl = scalaPackagePath
            , imports = []
            , typeDecls =
                [
                 (SpringBoot.Documented (Just (String.join "" [ "Generated based on ", currentModulePath |> Path.toString Name.toTitleCase "." ]))
                    (SpringBoot.Annotated (Nothing)
                         <|
                         (SpringBoot.Object
                             { modifiers =
                                 case accessControlledModuleDef.access of
                                     Public ->
                                         []

                                     Private ->
                                         [ SpringBoot.Private
                                             (currentPackagePath
                                                 |> ListExtra.last
                                                 |> Maybe.map (Name.toCamelCase >> String.toLower)
                                             )
                                         ]
                             , name =
                                 moduleName |> Name.toTitleCase
                             , members =
                                 List.append typeMembers functionMembers
                             , extends =
                                 [SpringBoot.TypeVar "App"]
                             , body =
                                 Just (SpringBoot.Ref ["org.springframework.boot.SpringApplication"] ("run(classOf[" ++ (moduleName |> Name.toTitleCase) ++ "], args:_*)"))
                             }
                         )
                    )
                 )
                ]
            }
    in
    [ moduleUnit ]


mapCustomTypeDefinition : Package.PackagePath -> Path -> Name -> List Name -> AccessControlled (Type.Constructors a) -> List SpringBoot.MemberDecl
mapCustomTypeDefinition currentPackagePath currentModulePath typeName typeParams accessControlledCtors =
    let
        caseClass name args extends =
            SpringBoot.Class
                { modifiers = [ SpringBoot.Case ]
                , name = name |> Name.toTitleCase
                , typeArgs = typeParams |> List.map (Name.toTitleCase >> SpringBoot.TypeVar)
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
                }

        parentTraitRef =
            mapFQNameToTypeRef (FQName currentPackagePath currentModulePath typeName)

        sealedTraitHierarchy =
            List.concat
                [ [ SpringBoot.Trait
                        { modifiers = [ SpringBoot.Sealed ]
                        , name = typeName |> Name.toTitleCase
                        , typeArgs = typeParams |> List.map (Name.toTitleCase >> SpringBoot.TypeVar)
                        , extends = []
                        , members = []
                        }
                  ]
                , accessControlledCtors.value
                    |> List.map
                        (\(Type.Constructor ctorName ctorArgs) ->
                            caseClass ctorName
                                ctorArgs
                                (if List.isEmpty typeParams then
                                    [ parentTraitRef ]

                                 else
                                    [ SpringBoot.TypeApply parentTraitRef (typeParams |> List.map (Name.toTitleCase >> SpringBoot.TypeVar)) ]
                                )
                        )
                ]
    in
    case accessControlledCtors.value of
        [ Type.Constructor ctorName ctorArgs ] ->
            if ctorName == typeName then
                [ SpringBoot.MemberTypeDecl (caseClass ctorName ctorArgs []) ]

            else
                sealedTraitHierarchy |> List.map SpringBoot.MemberTypeDecl

        _ ->
            sealedTraitHierarchy |> List.map SpringBoot.MemberTypeDecl


mapType : Type a -> SpringBoot.Type
mapType tpe =
    case tpe of
        Type.Variable a name ->
            SpringBoot.TypeVar (name |> Name.toTitleCase)

        Type.Reference a fQName argTypes ->
            let
                typeRef =
                    mapFQNameToTypeRef fQName
            in
            if List.isEmpty argTypes then
                typeRef

            else
                SpringBoot.TypeApply typeRef (argTypes |> List.map mapType)

        Type.Tuple a elemTypes ->
            SpringBoot.TupleType (elemTypes |> List.map mapType)

        Type.Record a fields ->
            SpringBoot.StructuralType
                (fields
                    |> List.map
                        (\field ->
                            SpringBoot.FunctionDecl
                                { modifiers = []
                                , name = field.name |> Name.toCamelCase
                                , typeArgs = []
                                , args = []
                                , returnType = Just (mapType field.tpe)
                                , body = Nothing
                                }
                        )
                )

        Type.ExtensibleRecord a argName fields ->
            SpringBoot.StructuralType
                (fields
                    |> List.map
                        (\field ->
                            SpringBoot.FunctionDecl
                                { modifiers = []
                                , name = field.name |> Name.toCamelCase
                                , typeArgs = []
                                , args = []
                                , returnType = Just (mapType field.tpe)
                                , body = Nothing
                                }
                        )
                )

        Type.Function a argType returnType ->
            SpringBoot.FunctionType (mapType argType) (mapType returnType)

        Type.Unit a ->
            SpringBoot.TypeRef [ "scala" ] "Unit"


mapValue : Value a -> SpringBoot.Value
mapValue value =
    case value of
        Literal a literal ->
            let
                wrap : String -> SpringBoot.Lit -> SpringBoot.Value
                wrap moduleName lit =
                    SpringBoot.Apply
                        (SpringBoot.Ref [ "morphir", "sdk" ] moduleName)
                        [ SpringBoot.ArgValue Nothing (SpringBoot.Literal lit) ]
            in
            case literal of
                BoolLiteral v ->
                    wrap "Bool" (SpringBoot.BooleanLit v)

                CharLiteral v ->
                    wrap "Char" (SpringBoot.CharacterLit v)

                StringLiteral v ->
                    wrap "String" (SpringBoot.StringLit v)

                IntLiteral v ->
                    wrap "Int" (SpringBoot.IntegerLit v)

                FloatLiteral v ->
                    wrap "Float" (SpringBoot.FloatLit v)

        Constructor a fQName ->
            let
                ( path, name ) =
                    mapFQNameToPathAndName fQName
            in
            SpringBoot.Ref path
                (name |> Name.toTitleCase)

        Tuple a elemValues ->
            SpringBoot.Tuple
                (elemValues |> List.map mapValue)

        List a itemValues ->
            SpringBoot.Apply
                (SpringBoot.Ref [ "morphir", "sdk" ] "List")
                (itemValues
                    |> List.map mapValue
                    |> List.map (SpringBoot.ArgValue Nothing)
                )

        Record a fieldValues ->
            SpringBoot.StructuralValue
                (fieldValues
                    |> List.map
                        (\( fieldName, fieldValue ) ->
                            ( fieldName |> Name.toCamelCase, mapValue fieldValue )
                        )
                )

        Variable a name ->
            SpringBoot.Variable (name |> Name.toCamelCase)

        Reference a fQName ->
            let
                ( path, name ) =
                    mapFQNameToPathAndName fQName
            in
            SpringBoot.Ref path (name |> Name.toCamelCase)

        Field a subjectValue fieldName ->
            SpringBoot.Select (mapValue subjectValue) (fieldName |> Name.toCamelCase)

        FieldFunction a fieldName ->
            SpringBoot.Select SpringBoot.Wildcard (fieldName |> Name.toCamelCase)

        Apply a fun arg ->
            let
                ( bottomFun, args ) =
                    Value.uncurryApply fun arg
            in
            SpringBoot.Apply (mapValue bottomFun)
                (args
                    |> List.map
                        (\argValue ->
                            SpringBoot.ArgValue Nothing (mapValue argValue)
                        )
                )

        Lambda a argPattern bodyValue ->
            case argPattern of
                AsPattern _ (WildcardPattern _) alias ->
                    SpringBoot.Lambda [ alias |> Name.toCamelCase ] (mapValue bodyValue)

                _ ->
                    SpringBoot.MatchCases [ ( mapPattern argPattern, mapValue bodyValue ) ]

        LetDefinition a defName def inValue ->
            SpringBoot.Block
                [ SpringBoot.FunctionDecl
                    { modifiers = []
                    , name = defName |> Name.toCamelCase
                    , typeArgs = []
                    , args =
                        if List.isEmpty def.inputTypes then
                            []

                        else
                            [ def.inputTypes
                                |> List.map
                                    (\( argName, _, argType ) ->
                                        { modifiers = []
                                        , tpe = mapType argType
                                        , name = argName |> Name.toCamelCase
                                        , defaultValue = Nothing
                                        }
                                    )
                            ]
                    , returnType =
                        Just (mapType def.outputType)
                    , body =
                        Just (mapValue def.body)
                    }
                ]
                (mapValue inValue)

        LetRecursion a defs inValue ->
            SpringBoot.Block
                (defs
                    |> Dict.toList
                    |> List.map
                        (\( defName, def ) ->
                            SpringBoot.FunctionDecl
                                { modifiers = []
                                , name = defName |> Name.toCamelCase
                                , typeArgs = []
                                , args =
                                    if List.isEmpty def.inputTypes then
                                        []

                                    else
                                        [ def.inputTypes
                                            |> List.map
                                                (\( argName, _, argType ) ->
                                                    { modifiers = []
                                                    , tpe = mapType argType
                                                    , name = argName |> Name.toCamelCase
                                                    , defaultValue = Nothing
                                                    }
                                                )
                                        ]
                                , returnType =
                                    Just (mapType def.outputType)
                                , body =
                                    Just (mapValue def.body)
                                }
                        )
                )
                (mapValue inValue)

        Destructure a bindPattern bindValue inValue ->
            SpringBoot.Block
                [ SpringBoot.ValueDecl
                    { modifiers = []
                    , pattern = mapPattern bindPattern
                    , value = mapValue bindValue
                    }
                ]
                (mapValue inValue)

        IfThenElse a condValue thenValue elseValue ->
            SpringBoot.IfElse (mapValue condValue) (mapValue thenValue) (mapValue elseValue)

        PatternMatch a onValue cases ->
            SpringBoot.Match (mapValue onValue)
                (cases
                    |> List.map
                        (\( casePattern, caseValue ) ->
                            ( mapPattern casePattern, mapValue caseValue )
                        )
                    |> SpringBoot.MatchCases
                )

        UpdateRecord a subjectValue fieldUpdates ->
            SpringBoot.Apply
                (SpringBoot.Select (mapValue subjectValue) "copy")
                (fieldUpdates
                    |> List.map
                        (\( fieldName, fieldValue ) ->
                            SpringBoot.ArgValue
                                (Just (fieldName |> Name.toCamelCase))
                                (mapValue fieldValue)
                        )
                )

        Unit a ->
            SpringBoot.Unit


mapPattern : Pattern a -> SpringBoot.Pattern
mapPattern pattern =
    case pattern of
        WildcardPattern a ->
            SpringBoot.WildcardMatch

        AsPattern a (WildcardPattern _) alias ->
            SpringBoot.NamedMatch (alias |> Name.toCamelCase)

        AsPattern a aliasedPattern alias ->
            SpringBoot.AliasedMatch (alias |> Name.toCamelCase) (mapPattern aliasedPattern)

        TuplePattern a itemPatterns ->
            SpringBoot.TupleMatch (itemPatterns |> List.map mapPattern)

        ConstructorPattern a fQName argPatterns ->
            let
                ( path, name ) =
                    mapFQNameToPathAndName fQName
            in
            SpringBoot.UnapplyMatch path
                (name |> Name.toTitleCase)
                (argPatterns
                    |> List.map mapPattern
                )

        EmptyListPattern a ->
            SpringBoot.EmptyListMatch

        HeadTailPattern a headPattern tailPattern ->
            SpringBoot.HeadTailMatch
                (mapPattern headPattern)
                (mapPattern tailPattern)

        LiteralPattern a literal ->
            let
                map l =
                    case l of
                        BoolLiteral v ->
                            SpringBoot.BooleanLit v

                        CharLiteral v ->
                            SpringBoot.CharacterLit v

                        StringLiteral v ->
                            SpringBoot.StringLit v

                        IntLiteral v ->
                            SpringBoot.IntegerLit v

                        FloatLiteral v ->
                            SpringBoot.FloatLit v
            in
            SpringBoot.LiteralMatch (map literal)

        UnitPattern a ->
            SpringBoot.WildcardMatch


reservedValueNames : Set String
reservedValueNames =
    Set.fromList
        -- we cannot use any method names in java.lamg.Object because values are represented as functions/values in a Scala object
        [ "clone"
        , "equals"
        , "finalize"
        , "getClass"
        , "hashCode"
        , "notify"
        , "notifyAll"
        , "toString"
        , "wait"
        ]
