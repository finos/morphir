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


module Morphir.SDK.Annotations exposing (..)

import Morphir.IR.AccessControlled exposing (AccessControlled)
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.Path exposing (Path)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.Scala.AST as Scala
import Morphir.Scala.AST as SpringBoot



type Annotations =
    JACKSON


mapCustomTypeDefinition: Maybe Annotations -> Package.PackagePath -> Path -> Name -> List Name -> AccessControlled (Type.Constructors a) -> List Scala.MemberDecl
mapCustomTypeDefinition annot currentPackagePath currentModulePath typeName typeParams accessControlledCtors =
      let
          caseClass name args extends =
              if List.isEmpty args then
                  Scala.Object
                      { modifiers = [ Scala.Case ]
                      , name = name |> Name.toTitleCase
                      , extends = extends
                      , members = []
                      }

              else
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
                      , members =[]
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

mapFQNameToTypeRef : FQName -> Scala.Type
mapFQNameToTypeRef fQName =
    let
        ( path, name ) =
            mapFQNameToPathAndName fQName
    in
    Scala.TypeRef path (name |> Name.toTitleCase)

mapFQNameToPathAndName : FQName -> ( Scala.Path, Name )
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
