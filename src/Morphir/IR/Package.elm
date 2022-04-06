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


module Morphir.IR.Package exposing
    ( Specification, emptySpecification
    , Definition, emptyDefinition
    , lookupModuleSpecification, lookupModuleDefinition, lookupTypeSpecification, lookupValueSpecification, lookupValueDefinition
    , PackageName, definitionToSpecification, definitionToSpecificationWithPrivate, eraseDefinitionAttributes, eraseSpecificationAttributes
    , mapDefinitionAttributes, mapSpecificationAttributes, selectModules, modulesOrderedByDependency
    )

{-| A package is collection of types and values that are versioned together. If this sounds abstract just think of any
of the popular package managers you are familiar with: NPM, NuGet, Maven, pip or Cabal. What they consider a package is
what this represents. A package contains modules which further group types and values.


# Specification vs Definition

Packages are available at two different levels of detail. A package specification only contains types that are exposed
publicly and type signatures for values that are exposed publicly. A package definition contains all the details
including implementation and private types and values.

@docs Specification, emptySpecification

@docs Definition, emptyDefinition


# Lookups

@docs lookupModuleSpecification, lookupModuleDefinition, lookupTypeSpecification, lookupValueSpecification, lookupValueDefinition


# Other utilities

@docs PackageName, definitionToSpecification, definitionToSpecificationWithPrivate, eraseDefinitionAttributes, eraseSpecificationAttributes
@docs mapDefinitionAttributes, mapSpecificationAttributes, selectModules, modulesOrderedByDependency

-}

import Dict exposing (Dict)
import Morphir.Dependency.DAG as DAG exposing (DAG)
import Morphir.IR.AccessControlled exposing (AccessControlled, withPrivateAccess, withPublicAccess)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Path exposing (Path)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value
import Set exposing (Set)


{-| A package name is a globally unique identifier for a package. It is represented by a path, which is a list of names.
-}
type alias PackageName =
    Path


{-| Type that represents a package specification. A package specification only contains types that are exposed publicly
and type signatures for values that are exposed publicly.
-}
type alias Specification ta =
    { modules : Dict ModuleName (Module.Specification ta)
    }


{-| Get an empty package specification with no modules.
-}
emptySpecification : Specification ta
emptySpecification =
    { modules = Dict.empty
    }


{-| Type that represents a package definition. A package definition contains all the details including implementation
and private types and values. The modules field is a dictionary keyed by module name that contains access controlled
module definitions. The `AccessControlled` adds access classifiers to each module to differentiate public and private
modules.
-}
type alias Definition ta va =
    { modules : Dict ModuleName (AccessControlled (Module.Definition ta va))
    }


{-| Get an empty package definition with no modules.
-}
emptyDefinition : Definition ta va
emptyDefinition =
    { modules = Dict.empty
    }


{-| Look up a module specification by its path in a package specification.
-}
lookupModuleSpecification : Path -> Specification ta -> Maybe (Module.Specification ta)
lookupModuleSpecification modulePath packageSpec =
    packageSpec.modules
        |> Dict.get modulePath


{-| Look up a module definition by its path in a package specification.
-}
lookupModuleDefinition : Path -> Definition ta va -> Maybe (Module.Definition ta va)
lookupModuleDefinition modulePath packageDef =
    packageDef.modules
        |> Dict.get modulePath
        |> Maybe.map withPrivateAccess


{-| Look up a type specification by its module path and name in a package specification.
-}
lookupTypeSpecification : Path -> Name -> Specification ta -> Maybe (Type.Specification ta)
lookupTypeSpecification modulePath localName packageSpec =
    packageSpec
        |> lookupModuleSpecification modulePath
        |> Maybe.andThen (Module.lookupTypeSpecification localName)


{-| Look up a value specification by its module path and name in a package specification.
-}
lookupValueSpecification : Path -> Name -> Specification ta -> Maybe (Value.Specification ta)
lookupValueSpecification modulePath localName packageSpec =
    packageSpec
        |> lookupModuleSpecification modulePath
        |> Maybe.andThen (Module.lookupValueSpecification localName)


{-| Look up a value definition by its module path and name in a package specification.
-}
lookupValueDefinition : Path -> Name -> Definition ta va -> Maybe (Value.Definition ta va)
lookupValueDefinition modulePath localName packageDef =
    packageDef
        |> lookupModuleDefinition modulePath
        |> Maybe.andThen (Module.lookupValueDefinition localName)


{-| Turn a package definition into a package specification. Only publicly exposed modules will be included in the
result.
-}
definitionToSpecification : Definition ta va -> Specification ta
definitionToSpecification def =
    { modules =
        def.modules
            |> Dict.toList
            |> List.filterMap
                (\( path, accessControlledModule ) ->
                    accessControlledModule
                        |> withPublicAccess
                        |> Maybe.map
                            (\moduleDef ->
                                ( path, Module.definitionToSpecification moduleDef )
                            )
                )
            |> Dict.fromList
    }


{-| Turn a package definition into a package specification. Non-exposed modules will also be included in the
result.
-}
definitionToSpecificationWithPrivate : Definition ta va -> Specification ta
definitionToSpecificationWithPrivate def =
    { modules =
        def.modules
            |> Dict.toList
            |> List.map
                (\( path, accessControlledModule ) ->
                    ( path
                    , Module.definitionToSpecificationWithPrivate
                        (accessControlledModule
                            |> withPrivateAccess
                        )
                    )
                )
            |> Dict.fromList
    }


{-| Map all type attributes of a package specification.
-}
mapSpecificationAttributes : (ta -> tb) -> Specification ta -> Specification tb
mapSpecificationAttributes tf spec =
    Specification
        (spec.modules
            |> Dict.map
                (\_ moduleSpec ->
                    Module.mapSpecificationAttributes tf moduleSpec
                )
        )


{-| Map all type and value attributes of a package definition.
-}
mapDefinitionAttributes : (ta -> tb) -> (va -> vb) -> Definition ta va -> Definition tb vb
mapDefinitionAttributes tf vf def =
    Definition
        (def.modules
            |> Dict.map
                (\_ moduleDef ->
                    AccessControlled moduleDef.access
                        (Module.mapDefinitionAttributes tf vf moduleDef.value)
                )
        )


{-| Remove all type attributes from a package specification.
-}
eraseSpecificationAttributes : Specification ta -> Specification ()
eraseSpecificationAttributes spec =
    spec
        |> mapSpecificationAttributes (\_ -> ())


{-| Remove all type and value attributes from a package definition.
-}
eraseDefinitionAttributes : Definition ta va -> Definition () ()
eraseDefinitionAttributes def =
    def
        |> mapDefinitionAttributes (\_ -> ()) (\_ -> ())


{-| Filter down the modules in this distribution to the specified modules and their transitive dependencies.
-}
selectModules : Set ModuleName -> PackageName -> Definition ta va -> Definition ta va
selectModules modulesToInclude packageName packageDef =
    let
        findAllDependencies : Set ModuleName -> Set ModuleName
        findAllDependencies current =
            current
                |> Set.toList
                |> List.filterMap
                    (\currentModuleName ->
                        packageDef.modules
                            |> Dict.get currentModuleName
                            |> Maybe.map
                                (\mDef ->
                                    mDef.value
                                        |> Module.dependsOnModules
                                        |> Set.toList
                                        |> List.filterMap
                                            (\( pName, mName ) ->
                                                if pName == packageName then
                                                    Just mName

                                                else
                                                    Nothing
                                            )
                                        |> Set.fromList
                                )
                    )
                |> List.foldl Set.union Set.empty

        expandedModulesToInclude : Set ModuleName
        expandedModulesToInclude =
            Set.union
                (findAllDependencies modulesToInclude)
                modulesToInclude
    in
    if modulesToInclude == expandedModulesToInclude then
        { packageDef
            | modules =
                packageDef.modules
                    |> Dict.toList
                    |> List.filter
                        (\( moduleName, _ ) ->
                            modulesToInclude |> Set.member moduleName
                        )
                    |> Dict.fromList
        }

    else
        selectModules expandedModulesToInclude packageName packageDef


{-| Get the list of modules within this package ordered by dependency. If module B depends on A than module B is
guaranteed to be after A in the list.
-}
modulesOrderedByDependency : PackageName -> Definition () (Type ()) -> Result (DAG.CycleDetected ModuleName) (List ( ModuleName, AccessControlled (Module.Definition () (Type ())) ))
modulesOrderedByDependency packageName packageDef =
    packageDef.modules
        |> Dict.toList
        |> List.foldl
            (\( moduleName, accessControlledModuleDef ) dagResultSoFar ->
                let
                    dependsOnModules : Set ModuleName
                    dependsOnModules =
                        accessControlledModuleDef.value
                            |> Module.dependsOnModules
                            -- Keep only dependencies within the package
                            |> Set.filter (\( dependsOnPackage, _ ) -> dependsOnPackage == packageName)
                            -- Remove the package name
                            |> Set.map Tuple.second
                in
                dagResultSoFar
                    |> Result.andThen (DAG.insertNode moduleName dependsOnModules)
            )
            (Ok DAG.empty)
        |> Result.map
            (\moduleDependencies ->
                moduleDependencies
                    -- Use the dependency graph to order the modules topologically
                    |> DAG.backwardTopologicalOrdering
                    -- Turn the partial ordering represented as a list of lists into a simple list
                    |> List.concat
                    -- Look up the module definition for each module name
                    |> List.filterMap
                        (\moduleName ->
                            packageDef.modules
                                |> Dict.get moduleName
                                |> Maybe.map (Tuple.pair moduleName)
                        )
            )
