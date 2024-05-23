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


module SlateX.DevBot.Scala.SlateXToScala.Modules exposing (..)


import Set
import Dict
import SlateX.AST.Path exposing (Path)
import SlateX.AST.Package exposing (Package)
import SlateX.AST.Module as M
import SlateX.AST.Type as T
import SlateX.AST.Value.Annotated as A
import SlateX.DevBot.Scala.AST as S
import SlateX.Mapping.Naming as Naming
import SlateX.DevBot.Scala.SlateXToScala.Values as Values
import SlateX.DevBot.Scala.SlateXToScala.Types as Types
import SlateX.DevBot.Scala.ReservedWords as ReservedWords
import SlateX.AST.Inferencer as TypeInferencer


mapImplementation : Package -> Path -> M.Implementation -> List S.CompilationUnit
mapImplementation package modulePath impl =
    let
        ( packagePath, moduleName ) =
            case modulePath |> List.reverse of
                [] ->
                    ( [], [] )

                lastName :: reverseModulePath ->
                    ( reverseModulePath |> List.reverse, lastName )


        recordTypeAliasUnits =
            impl.typeAliases
                |> Dict.toList
                |> List.map
                    (\( typeName, typeDecl ) ->
                        { dirPath = modulePath |> List.map (Naming.toCamelCase >> String.toLower)
                        , fileName = (typeName |> Naming.toTitleCase) ++ ".scala"
                        , packageDecl = modulePath |> List.map (Naming.toCamelCase >> String.toLower)
                        , imports = []
                        , typeDecls = Types.mapRecordTypeAlias typeName typeDecl
                        }
                    )

        typeAliasUnit =
            { dirPath = modulePath |> List.map (Naming.toCamelCase >> String.toLower)
            , fileName = "package.scala"
            , packageDecl = packagePath |> List.map (Naming.toCamelCase >> String.toLower)
            , imports = []
            , typeDecls =
                [ S.Object
                    { modifiers = [ S.Package ]
                    , name = moduleName |> Naming.toCamelCase |> String.toLower
                    , members =
                        impl.typeAliases 
                            |> Dict.toList
                            |> List.filterMap 
                                (\( typeName, typeDecl ) ->
                                    case typeDecl.exp of
                                        -- Do not generate type alias for record types because they will be represented by case classes
                                        T.Record _ ->
                                            Nothing

                                        -- Do not generate type alias for native types
                                        T.Constructor ( [ [ "slate", "x" ], [ "core" ], [ "native" ] ], [ "native" ] ) _  ->
                                            Nothing

                                        _ ->
                                            Just
                                                (S.TypeAlias
                                                    { alias = typeName |> Naming.toTitleCase
                                                    , typeArgs = typeDecl.params |> List.map (T.Variable >> Types.mapExp)
                                                    , tpe = Types.mapExp typeDecl.exp
                                                    }  
                                                )    
                                )     
                    , extends = []               
                    }
                ]
            }

        unionTypeUnits =
            impl.unionTypes
                |> Dict.toList
                |> List.map
                    (\( typeName, typeDecl ) ->
                        { dirPath = 
                            modulePath |> List.map (Naming.toCamelCase >> String.toLower)
                        , fileName = 
                            (typeName |> Naming.toTitleCase) ++ ".scala"
                        , packageDecl = 
                            modulePath |> List.map (Naming.toCamelCase >> String.toLower)
                        , imports =
                            []
                        , typeDecls =
                            Types.mapUnionType modulePath typeName typeDecl
                        }
                    )

        valueUnit =
            { dirPath = packagePath |> List.map (Naming.toCamelCase >> String.toLower)
            , fileName = (moduleName |> Naming.toTitleCase) ++ ".scala"
            , packageDecl = packagePath |> List.map (Naming.toCamelCase >> String.toLower)
            , imports = []
            , typeDecls =
                [ S.Object
                    { modifiers = []
                    , name = moduleName |> Naming.toTitleCase
                    , members =
                        impl.values 
                            |> Dict.toList
                            |> List.map 
                                (\( name, value ) ->
                                    let
                                        scalaName =
                                            name |> Naming.toCamelCase

                                        normalizedName =
                                            if ReservedWords.reservedValueNames |> Set.member scalaName then
                                                "_" ++ scalaName
                                            else
                                                scalaName

                                        ( scalaValue, scalaReturnType ) =
                                            case impl.valueTypes |> Dict.get name of
                                                Just valueType ->
                                                    let
                                                        valueWithTypeOrError =
                                                            TypeInferencer.checkPackage package valueType value
                                                    in    
                                                    ( valueWithTypeOrError |> Values.mapExp, valueType |> Types.mapExp |> Just )

                                                Nothing ->    
                                                    let
                                                        valueWithTypeOrError =
                                                            TypeInferencer.inferPackage package value

                                                        maybeValueType =
                                                            valueWithTypeOrError
                                                                |> A.annotation
                                                                |> Result.toMaybe
                                                    in    
                                                    ( valueWithTypeOrError |> Values.mapExp, maybeValueType |> Maybe.map Types.mapExp )
                                    in
                                    S.FunctionDecl
                                        { modifiers = []
                                        , name = normalizedName
                                        , typeArgs =
                                            let
                                                extractedTypeArgNames =
                                                    impl.valueTypes
                                                        |> Dict.get name        
                                                        |> Maybe.map List.singleton
                                                        |> Maybe.withDefault []
                                                        |> Types.extractTypeArgNames
                                            in
                                            extractedTypeArgNames 
                                                |> List.map (T.Variable >> Types.mapExp)
                                        , args = []
                                        , returnType =
                                            impl.valueTypes
                                                |> Dict.get name
                                                |> Maybe.map Types.mapExp 
                                        , body =
                                            Just scalaValue
                                        }
                                )     
                    , extends = []               
                    }
                ]
            }
    in
    recordTypeAliasUnits ++ [ typeAliasUnit ] ++ unionTypeUnits ++ [ valueUnit ]
        |> List.map removeEmptyTypedecls
        |> List.filter (not << List.isEmpty << .typeDecls)


removeEmptyTypedecls : S.CompilationUnit -> S.CompilationUnit
removeEmptyTypedecls cu =
    { cu
        | typeDecls =
            cu.typeDecls
                |> List.filter typeDeclNotEmpty
    }


typeDeclNotEmpty : S.TypeDecl -> Bool
typeDeclNotEmpty typeDecl =
    case typeDecl of
        S.Trait decl ->
            True

        S.Class decl ->
            True

        S.Object decl ->
            -- If this is a case object it can be empty
            (decl.modifiers |> List.member S.Case)
            -- If it's not check if it has any members
            || not (List.isEmpty decl.members)
