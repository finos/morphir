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
    ( Specification, Definition
    , ModulePath, definitionToSpecification, eraseSpecificationAttributes, mapDefinitionAttributes, mapSpecificationAttributes
    )

{-| Modules are groups of types and values that belong together.

@docs Specification, Definition
@docs ModulePath, definitionToSpecification, eraseSpecificationAttributes, mapDefinitionAttributes, mapSpecificationAttributes

-}

import Dict exposing (Dict)
import Morphir.IR.AccessControlled exposing (AccessControlled, withPublicAccess)
import Morphir.IR.Documented as Documented exposing (Documented)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Path exposing (Path)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)


{-| -}
type alias ModulePath =
    Path


{-| Type that represents a module specification.
-}
type alias Specification ta va =
    { types : Dict Name (Documented (Type.Specification ta))
    , values : Dict Name (Value.Specification va)
    }


{-| -}
emptySpecification : Specification ta va
emptySpecification =
    { types = Dict.empty
    , values = Dict.empty
    }


{-| Type that represents a module definition. It includes types and values.
-}
type alias Definition ta va =
    { types : Dict Name (AccessControlled (Documented (Type.Definition ta)))
    , values : Dict Name (AccessControlled (Value.Definition va))
    }


{-| -}
definitionToSpecification : Definition ta va -> Specification ta va
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


{-| -}
eraseSpecificationAttributes : Specification ta tv -> Specification () ()
eraseSpecificationAttributes spec =
    spec
        |> mapSpecificationAttributes (\_ -> ()) (\_ -> ())


{-| -}
mapSpecificationAttributes : (ta -> tb) -> (va -> vb) -> Specification ta va -> Specification tb vb
mapSpecificationAttributes tf vf spec =
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
                    Value.mapSpecificationAttributes vf valueSpec
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
                        (Value.mapDefinitionAttributes vf valueDef.value)
                )
        )
