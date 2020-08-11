module Morphir.Scala.Backend exposing (..)

import Dict
import List.Extra as ListExtra
import Morphir.File.FileMap exposing (FileMap)
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.SDK.Bool exposing (false, true)
import Morphir.Scala.AST as Scala exposing (ArgDecl, MemberDecl(..), TypeDecl(..))
import Morphir.Scala.PrettyPrinter as PrettyPrinter
import Morphir.SDK.StatefulApp as StatefulApp exposing (StatefulApp)
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
                mapModuleDefinition opt packagePath modulePath moduleImpl
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
        |> Dict.fromList


mapFQNameToTypeRef : FQName -> Scala.Type
mapFQNameToTypeRef (FQName packagePath modulePath localName) =
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
    Scala.TypeRef
        scalaModulePath
        (localName
            |> Name.toTitleCase
        )


mapModuleDefinition : Options -> Package.PackagePath -> Path -> AccessControlled (Module.Definition a) -> List Scala.CompilationUnit
mapModuleDefinition opt currentPackagePath currentModulePath accessControlledModuleDef =
    let
       -- _ = Debug.log "currentPackagePath: " currentPackagePath
        --_ = Debug.log "currentModulePath: " currentModulePath
        --_ = Debug.log "accessControlledModuleDef: " accessControlledModuleDef.value.values |> Dict.toList
        _ = Debug.log "accessControlledModuleDefTypes: " accessControlledModuleDef.value.types |> Dict.toList
        ( scalaPackagePath, moduleName ) =
            case currentModulePath |> List.reverse of
                [] ->
                    ( [], [] )

                lastName :: reverseModulePath ->
                    ( List.append (currentPackagePath |> List.map (Name.toCamelCase >> String.toLower)) (reverseModulePath |> List.reverse |> List.map (Name.toCamelCase >> String.toLower)), lastName )

        typeMembers : List Scala.MemberDecl
        typeMembers =
            accessControlledModuleDef.value.types
                |> Dict.toList
                |> List.concatMap
                    (\( typeName, accessControlledDocumentedTypeDef ) ->
                        case accessControlledDocumentedTypeDef.value.value of
                            Type.TypeAliasDefinition typeParams typeExp ->
                                [ Scala.TypeAlias
                                    { alias =
                                        typeName |> Name.toTitleCase
                                    , typeArgs =
                                        typeParams |> List.map (Name.toTitleCase >> Scala.TypeVar)
                                    , tpe =
                                        mapType typeExp
                                    }
                                ]

                            Type.CustomTypeDefinition typeParams accessControlledCtors ->
                                mapCustomTypeDefinition currentPackagePath currentModulePath typeName typeParams accessControlledCtors
                    )
                |> addClass (MemberTypeDecl (createClass "Deal"))

        _ = Debug.log "typeMembers: " typeMembers

        functionMembers : List Scala.MemberDecl
        functionMembers =
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
                                        [ Scala.Private Nothing ]
                            , name =
                                valueName |> Name.toCamelCase
                            , typeArgs =
                                []
                            , args =
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
                                Just (Scala.Tuple [])
                            }
                        ]
                    )
        _ = functionMembers |> List.tail |> Debug.log "functionMembers: "

        classMembers : List Scala.MemberDecl
        classMembers =
            functionMembers
            |> List.filter isFunction
            |> List.map getArgs
            |> List.filter (\x -> x /= [])
            |> List.concat
            |> List.filter (\x -> x /= [])
            |> List.concat
            |> List.map
                (\{ modifiers, tpe, name, defaultValue } ->
                    case (tpe, defaultValue) of
                        (Scala.TypeApply (Scala.TypeRef _ "Maybe") _, Nothing ) -> MemberTypeDecl (createClass name)
                        _






        argsFunction2: List ( List (List ArgDecl) ) -> List (List ArgDecl)
        argsFunction2 func =
            case func of
                x :: xs -> x
                _ -> []

        isFunction: (Scala.MemberDecl) -> Bool
        isFunction func =
            case func of
                FunctionDecl function -> true
                _ -> false

        getFuncs: List Scala.MemberDecl -> List Scala.MemberDecl
        getFuncs args = List.filter isFunction args

        getFuncs2: List Scala.MemberDecl -> List ( List (List ArgDecl) )
        getFuncs2 args =
             List.map getArgs args

        getFuncs3: List ( List (List ArgDecl) ) -> List ( List (List ArgDecl) )
        getFuncs3 li = li
            |> List.filter (\x -> x /= [])

        getFuncs4 : List ( List (List ArgDecl) ) -> List (List ArgDecl)
        getFuncs4 li = List.concat li

        getFuncs5 : List (List ArgDecl) -> List (List ArgDecl)
        getFuncs5 li = li
            |> List.filter (\x -> x /= [])

        getFuncs6 : List (List ArgDecl) -> List ArgDecl
        getFuncs6 li = List.concat li

        isStateFulApp : List ArgDecl -> Bool
        isStateFulApp app = List.length app == 3

        filterArgs1 : ArgDecl -> Bool
        filterArgs1 { modifiers, tpe, name, defaultValue } =
            case (tpe, defaultValue) of
                (Scala.TypeApply (Scala.TypeRef _ "Maybe") _, Nothing ) -> True
                _ -> False

        filterArgs3 : ArgDecl -> String
        filterArgs3 { modifiers, tpe, name, defaultValue } =
            case (tpe, defaultValue) of
                (Scala.TypeApply (Scala.TypeRef _ "Maybe") _, Nothing ) -> name
                _ -> ""

        isStateFulApp2 : List ArgDecl -> List ArgDecl
        isStateFulApp2 app = List.filter filterArgs1 app

        getFuncs7: List ArgDecl -> List String
        getFuncs7 li = List.concat
            (List.map
                (\{ modifiers, tpe, name, defaultValue } ->
                    case (tpe, defaultValue) of
                    (Scala.TypeApply (Scala.TypeRef _ "Maybe") _, Nothing ) -> [name]
                    _ -> []
                ) li)

        --Ver si alguno de estos elementos cumple con la definicion de StatefulApp

        _= functionMembers |> getFuncs |> Debug.log "functionMembers"
        _= functionMembers |> getFuncs |> getFuncs2 |> Debug.log "functionArgs"
        _= functionMembers |> getFuncs |> getFuncs2 |> List.length |> Debug.log "length functionArgs"
        _= functionMembers |> getFuncs |> getFuncs2 |> argsFunction2 |> Debug.log "argsFunction2"
        _= functionMembers |> getFuncs |> getFuncs2 |> getFuncs3 |> Debug.log "getFuncs3"
        _= functionMembers |> getFuncs |> getFuncs2 |> getFuncs3 |> getFuncs4 |> Debug.log "getFuncs4"
        _= functionMembers |> getFuncs |> getFuncs2 |> getFuncs3 |>
            getFuncs4 |> getFuncs5 |> Debug.log "getFuncs5"
        _= functionMembers |> getFuncs |> getFuncs2 |> getFuncs3 |>
            getFuncs4 |> getFuncs5 |> getFuncs6 |> Debug.log "getFuncs6"
        _= functionMembers |> getFuncs |> getFuncs2 |> getFuncs3 |>
                    getFuncs4 |> getFuncs5 |> getFuncs6 |>
                    isStateFulApp |> Debug.log "getFuncs7"
        _= functionMembers |> getFuncs |> getFuncs2 |> getFuncs3 |>
                            getFuncs4 |> getFuncs5 |> getFuncs6 |>
                            isStateFulApp2 |> Debug.log "isStatefulApp2"
        _= functionMembers |> getFuncs |> getFuncs2 |> getFuncs3 |>
                                    getFuncs4 |> getFuncs5 |> getFuncs6 |>
                                    getFuncs7 |> Debug.log "getFuncs7"


        getArgs: Scala.MemberDecl ->  ( List (List ArgDecl) )
        getArgs args =
            case args of
                MemberTypeDecl _ -> []
                TypeAlias _ -> []
                FunctionDecl function -> function.args

        getStringArgs: Maybe ( List (List ArgDecl) ) -> String
        getStringArgs args =
            case args of
                Nothing -> ""
                _ -> Debug.toString args

        createClass : String -> Scala.TypeDecl
        createClass a = Class
            { modifiers = []
            , name = a
            , typeArgs = []
            , ctorArgs = []
            , extends = []
            }


        _ = Debug.log "createClass" (addClass (MemberTypeDecl (createClass "Deal")) typeMembers)

        addClass : Scala.MemberDecl -> List Scala.MemberDecl -> List Scala.MemberDecl
        addClass t li =
            t :: li


        moduleUnit : Scala.CompilationUnit
        moduleUnit =
            { dirPath = scalaPackagePath
            , fileName = (moduleName |> Name.toTitleCase) ++ ".scala"
            , packageDecl = scalaPackagePath
            , imports = []
            , typeDecls =
                [ Scala.Documented (Just (String.join "" [ "Generated based on ", currentModulePath |> Path.toString Name.toTitleCase "." ])) <|
                    Scala.Object
                        { modifiers =
                            case accessControlledModuleDef.access of
                                Public ->
                                    []

                                Private ->
                                    [ Scala.Private
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
                            []
                        }
                ]
            }
    in
    [ moduleUnit ]


mapCustomTypeDefinition : Package.PackagePath -> Path -> Name -> List Name -> AccessControlled (Type.Constructors a) -> List Scala.MemberDecl
mapCustomTypeDefinition currentPackagePath currentModulePath typeName typeParams accessControlledCtors =
    let
        _ = Debug.log "mapCustomTypeDefinition: "
        _ = Debug.log "accessControlledCtors: " accessControlledCtors
        _ = Debug.log "accessControlledCtors.value: " accessControlledCtors.value
        _ = Debug.log "currentModulePath: " currentModulePath
        _ = Debug.log "currentPackagePath: " currentPackagePath
        _ = Debug.log "typeName: " typeName
        _ = Debug.log "typeParams: " typeParams
        caseClass name args extends =
            Scala.Class
                { modifiers = [ Scala.Case ]
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
                }

        parentTraitRef =
            mapFQNameToTypeRef (FQName currentPackagePath currentModulePath typeName)

        sealedTraitHierarchy =
            List.concat
                [ [ Scala.Trait
                        { modifiers = [ Scala.Sealed ]
                        , name = typeName |> Name.toTitleCase
                        , typeArgs = typeParams |> List.map (Name.toTitleCase >> Scala.TypeVar)
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
                                    [ Scala.TypeApply parentTraitRef (typeParams |> List.map (Name.toTitleCase >> Scala.TypeVar)) ]
                                )
                        )
                ]
    in
    case accessControlledCtors.value of
        [ Type.Constructor ctorName ctorArgs ] ->
            if ctorName == typeName then
                [ Scala.MemberTypeDecl (caseClass ctorName ctorArgs []) ]

            else
                sealedTraitHierarchy |> List.map Scala.MemberTypeDecl

        _ ->
            sealedTraitHierarchy |> List.map Scala.MemberTypeDecl


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
                                , name = field.name |> Name.toCamelCase
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
                                , name = field.name |> Name.toCamelCase
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
