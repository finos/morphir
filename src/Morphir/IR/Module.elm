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
    ( ModuleName
    , Specification, emptySpecification
    , Definition
    , definitionToSpecification
    , lookupTypeSpecification, lookupValueSpecification
    , eraseSpecificationAttributes, eraseDefinitionAttributes
    , mapDefinitionAttributes, mapSpecificationAttributes
    )

{-| Modules are used to group types and values together to make them easier to find. A module serves the same purpose as
a package in Java or namespaces in other languages. A module is identified by a module name within the package. Within a
module each type and value is identified using a local name.

@docs ModuleName


# Specification vs Definition

Modules are available at two different levels of detail. A module specification only contains types that are exposed
publicly and type signatures for values that are exposed publicly. A module definition contains all the details
including implementation and private types and values.

@docs Specification, emptySpecification
@docs Definition, emptyDefinition
@docs definitionToSpecification


# Lookups

@docs lookupTypeSpecification, lookupValueSpecification


# Manage attributes

@docs eraseSpecificationAttributes, eraseDefinitionAttributes
@docs mapDefinitionAttributes, mapSpecificationAttributes

-}

import Dict exposing (Dict)
import Morphir.IR.AccessControlled exposing (AccessControlled, withPublicAccess)
import Morphir.IR.Documented as Documented exposing (Documented)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Path exposing (Path)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)


{-| A module name is a unique identifier for a module within a package. It is represented by a path, which is a list of
names.
-}
type alias ModuleName =
    Path


{-| Type that represents a module specification. A module specification only contains types that are exposed
publicly and type signatures for values that are exposed publicly.

A module contains types and values which is represented by two field in this type:

  - types: a dictionary of local name to documented type specification.
  - values: a dictionary of local name to value specification.

-}
type alias Specification ta =
    { types : Dict Name (Documented (Type.Specification ta))
    , values : Dict Name (Value.Specification ta)
    }


{-| Get an empty module specification with no types or values.
-}
emptySpecification : Specification ta
emptySpecification =
    { types = Dict.empty
    , values = Dict.empty
    }


{-| Type that represents a module definition. A module definition contains all the details
including implementation and private types and values.

A module contains types and values which is represented by two field in this type:

  - types: a dictionary of local name to access controlled, documented type specification.
  - values: a dictionary of local name to access controlled value specification.

-}
type alias Definition ta va =
    { types : Dict Name (AccessControlled (Documented (Type.Definition ta)))
    , values : Dict Name (AccessControlled (Value.Definition ta va))
    }


{-| Get an empty module definition with no types or values.
-}
emptyDefinition : Definition ta va
emptyDefinition =
    { types = Dict.empty
    , values = Dict.empty
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
                                ( path, Value.definitionToSpecification valueDef )
                            )
                )
            |> Dict.fromList
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
                    Value.mapSpecificationAttributes tf valueSpec
                )
        )


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
                        (Value.mapDefinitionAttributes tf vf valueDef.value)
                )
        )
