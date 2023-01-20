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


module Morphir.IR.Module exposing
    ( ModuleName, QualifiedModuleName
    , Specification, emptySpecification
    , Definition, emptyDefinition
    , definitionToSpecification, definitionToSpecificationWithPrivate
    , lookupTypeSpecification, lookupValueSpecification, lookupValueDefinition
    , eraseSpecificationAttributes, eraseDefinitionAttributes
    , mapDefinitionAttributes, mapSpecificationAttributes
    , collectTypeReferences, collectValueReferences, collectReferences, dependsOnModules
    )

{-| Modules are used to group types and values together to make them easier to find. A module serves the same purpose as
a package in Java or namespaces in other languages. A module is identified by a module name within the package. Within a
module each type and value is identified using a local name.

@docs ModuleName, QualifiedModuleName


# Specification vs Definition

Modules are available at two different levels of detail. A module specification only contains types that are exposed
publicly and type signatures for values that are exposed publicly. A module definition contains all the details
including implementation and private types and values.

@docs Specification, emptySpecification
@docs Definition, emptyDefinition
@docs definitionToSpecification, definitionToSpecificationWithPrivate


# Lookups

@docs lookupTypeSpecification, lookupValueSpecification, lookupValueDefinition


# Manage attributes

@docs eraseSpecificationAttributes, eraseDefinitionAttributes
@docs mapDefinitionAttributes, mapSpecificationAttributes
@docs collectTypeReferences, collectValueReferences, collectReferences, dependsOnModules

-}

import Dict exposing (Dict)
import Morphir.IR.AccessControlled exposing (AccessControlled, withPrivateAccess, withPublicAccess)
import Morphir.IR.Documented as Documented exposing (Documented)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Path exposing (Path)
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value
import Set exposing (Set)


{-| A module name is a unique identifier for a module within a package. It is represented by a path, which is a list of
names.
-}
type alias ModuleName =
    Path


{-| A qualified module name is a globally unique identifier for a module. It is represented by a tuple of the package
and the module name.
-}
type alias QualifiedModuleName =
    ( Path, Path )


{-| Type that represents a module specification. A module specification only contains types that are exposed
publicly and type signatures for values that are exposed publicly.

A module contains types and values which is represented by two field in this type:

  - types: a dictionary of local name to documented type specification.
  - values: a dictionary of local name to value specification.

-}
type alias Specification ta =
    { types : Dict Name (Documented (Type.Specification ta))
    , values : Dict Name (Documented (Value.Specification ta))
    , doc : Maybe String
    }


{-| Get an empty module specification with no types or values.
-}
emptySpecification : Specification ta
emptySpecification =
    { types = Dict.empty
    , values = Dict.empty
    , doc = Nothing
    }


{-| Type that represents a module definition. A module definition contains all the details
including implementation and private types and values.

A module contains types and values which is represented by two field in this type:

  - types: a dictionary of local name to access controlled, documented type specification.
  - values: a dictionary of local name to access controlled value specification.

Type variables ta and va refer to type annotation and value annotation

-}
type alias Definition ta va =
    { types : Dict Name (AccessControlled (Documented (Type.Definition ta)))
    , values : Dict Name (AccessControlled (Documented (Value.Definition ta va)))
    , doc : Maybe String
    }


{-| Get an empty module definition with no types or values.
-}
emptyDefinition : Definition ta va
emptyDefinition =
    { types = Dict.empty
    , values = Dict.empty
    , doc = Nothing
    }


{-| Look up a type specification by its name in a module specification.
-}
lookupTypeSpecification : Name -> Specification ta -> Maybe (Type.Specification ta)
lookupTypeSpecification localName moduleSpec =
    moduleSpec.types
        |> Dict.get localName
        |> Maybe.map .value


{-| Look up a value specification by its name in a module specification.
-}
lookupValueSpecification : Name -> Specification ta -> Maybe (Value.Specification ta)
lookupValueSpecification localName moduleSpec =
    moduleSpec.values
        |> Dict.get localName
        |> Maybe.map .value


{-| Look up a value definition by its name in a module specification.
-}
lookupValueDefinition : Name -> Definition ta va -> Maybe (Value.Definition ta va)
lookupValueDefinition localName moduleDef =
    moduleDef.values
        |> Dict.get localName
        |> Maybe.map (withPrivateAccess >> .value)


{-| Turn a module definition into a module specification. Only publicly exposed types and values will be included in the
result.
-}
definitionToSpecification : Definition ta va -> Specification ta
definitionToSpecification def =
    { types =
        def.types
            |> Dict.toList
            |> List.filterMap
                (\( path, accessControlledType ) ->
                    accessControlledType
                        |> withPublicAccess
                        |> Maybe.map
                            (\typeDef ->
                                ( path, typeDef |> Documented.map Type.definitionToSpecification )
                            )
                )
            |> Dict.fromList
    , values =
        def.values
            |> Dict.toList
            |> List.filterMap
                (\( path, accessControlledValue ) ->
                    accessControlledValue
                        |> withPublicAccess
                        |> Maybe.map
                            (\valueDef ->
                                ( path, valueDef |> Documented.map Value.definitionToSpecification )
                            )
                )
            |> Dict.fromList
    , doc = def.doc
    }


{-| Turn a module definition into a module specification. Non-exposed types and values will also be included in the
result.
-}
definitionToSpecificationWithPrivate : Definition ta va -> Specification ta
definitionToSpecificationWithPrivate def =
    { types =
        def.types
            |> Dict.toList
            |> List.map
                (\( path, accessControlledType ) ->
                    ( path
                    , accessControlledType
                        |> withPrivateAccess
                        |> Documented.map Type.definitionToSpecificationWithPrivate
                    )
                )
            |> Dict.fromList
    , values =
        def.values
            |> Dict.toList
            |> List.map
                (\( path, accessControlledValue ) ->
                    ( path
                    , accessControlledValue
                        |> withPrivateAccess
                        |> Documented.map Value.definitionToSpecification
                    )
                )
            |> Dict.fromList
    , doc = def.doc
    }


{-| Remove all type attributes from a module specification.
-}
eraseSpecificationAttributes : Specification ta -> Specification ()
eraseSpecificationAttributes spec =
    spec
        |> mapSpecificationAttributes (\_ -> ())


{-| Remove all type attributes from a module definition.
-}
eraseDefinitionAttributes : Definition ta va -> Definition () ()
eraseDefinitionAttributes def =
    def
        |> mapDefinitionAttributes (\_ -> ()) (\_ -> ())


{-| -}
mapSpecificationAttributes : (ta -> tb) -> Specification ta -> Specification tb
mapSpecificationAttributes tf spec =
    Specification
        (spec.types
            |> Dict.map
                (\_ typeSpec ->
                    typeSpec |> Documented.map (Type.mapSpecificationAttributes tf)
                )
        )
        (spec.values
            |> Dict.map
                (\_ valueSpec ->
                    valueSpec |> Documented.map (Value.mapSpecificationAttributes tf)
                )
        )
        spec.doc


{-| -}
mapDefinitionAttributes : (ta -> tb) -> (va -> vb) -> Definition ta va -> Definition tb vb
mapDefinitionAttributes tf vf def =
    Definition
        (def.types
            |> Dict.map
                (\_ typeDef ->
                    AccessControlled typeDef.access
                        (typeDef.value |> Documented.map (Type.mapDefinitionAttributes tf))
                )
        )
        (def.values
            |> Dict.map
                (\_ valueDef ->
                    AccessControlled valueDef.access
                        (valueDef.value |> Documented.map (Value.mapDefinitionAttributes tf vf))
                )
        )
        def.doc


{-| Collect all type references from the module.
-}
collectTypeReferences : Definition ta va -> Set FQName
collectTypeReferences moduleDef =
    let
        typeRefs : Set FQName
        typeRefs =
            moduleDef.types
                |> Dict.values
                |> List.map
                    (\typeDef ->
                        case typeDef.value.value of
                            Type.TypeAliasDefinition _ tpe ->
                                Type.collectReferences tpe

                            Type.CustomTypeDefinition _ ctors ->
                                ctors.value
                                    |> Dict.values
                                    |> List.concatMap
                                        (\ctorArgs ->
                                            ctorArgs
                                                |> List.map (\( _, tpe ) -> Type.collectReferences tpe)
                                        )
                                    |> List.foldl Set.union Set.empty
                    )
                |> List.foldl Set.union Set.empty

        valueRefs : Set FQName
        valueRefs =
            moduleDef.values
                |> Dict.values
                |> List.concatMap
                    (\valueDef ->
                        valueDef.value.value.outputType
                            :: (valueDef.value.value.inputTypes |> List.map (\( _, _, tpe ) -> tpe))
                            |> List.map Type.collectReferences
                    )
                |> List.foldl Set.union Set.empty
    in
    Set.union typeRefs valueRefs


{-| Collect all value references from the module.
-}
collectValueReferences : Definition ta va -> Set FQName
collectValueReferences moduleDef =
    moduleDef.values
        |> Dict.values
        |> List.map
            (\valueDef ->
                Value.collectReferences valueDef.value.value.body
            )
        |> List.foldl Set.union Set.empty


{-| Collect all type and value references from the module.
-}
collectReferences : Definition ta va -> Set FQName
collectReferences moduleDef =
    Set.union
        (collectTypeReferences moduleDef)
        (collectValueReferences moduleDef)


{-| Find all the modules that this module depends on.
-}
dependsOnModules : Definition ta va -> Set QualifiedModuleName
dependsOnModules moduleDef =
    collectReferences moduleDef
        |> Set.map (\( packageName, moduleName, _ ) -> ( packageName, moduleName ))
