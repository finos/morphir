module Morphir.Graph.Tripler exposing (Triple, Object(..), NodeType(..), Verb(..), mapDistribution)

import Dict
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.FQName as FQName exposing (FQName(..))
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type exposing (Type(..))


type NodeType
    = Record
    | Field
    | Type
    | Function


type Object
    = Other String
    | FQN FQName
    | Node NodeType
    -- | PathOf Path.Path


type Verb
    = IsA
    | Contains


type alias Triple =
    { subject : FQName
    , verb : Verb
    , object : Object
    }


mapDistribution : Distribution -> List Triple
mapDistribution distro =
    case distro of
        Distribution.Library packageName _ packageDef ->
            mapPackageDefinition packageName packageDef


mapPackageDefinition : Package.PackageName -> Package.Definition ta va -> List Triple
mapPackageDefinition packageName packageDef =
    packageDef.modules
        |> Dict.toList
        |> List.concatMap
            (\( moduleName, accessControlledModuleDef ) ->
                mapModuleDefinition packageName moduleName accessControlledModuleDef.value
            )


mapModuleDefinition : Package.PackageName -> Module.ModuleName -> Module.Definition ta va -> List Triple
mapModuleDefinition packageName moduleName moduleDef =
    moduleDef.types
        |> Dict.toList
        |> List.concatMap
            (\( typeName, accessControlledDocumentedTypeDef ) ->
                mapTypeDefinition packageName moduleName typeName accessControlledDocumentedTypeDef.value.value
            )


mapTypeDefinition : Package.PackageName -> Module.ModuleName -> Name -> Type.Definition ta -> List Triple
mapTypeDefinition packageName moduleName typeName typeDef =
    let
        recordFqn =
            FQName packageName moduleName typeName

        recordTriple =
            Triple recordFqn IsA (Node Record)

        recordTypeTriple =
            Triple recordFqn IsA (Node Type)

        fieldTriples =
            case typeDef of
                Type.TypeAliasDefinition _ (Type.Record _ fields) ->
                      fields
                        |> List.map
                            (\field ->
                                let
                                    subjectFqn =
                                        (FQName packageName (List.append moduleName [typeName]) field.name)

                                    fieldTriple =
                                        case field.tpe of
                                            Reference _ typeFqn _->
                                                Triple subjectFqn IsA (FQN typeFqn)
                                            _ ->
                                                Triple subjectFqn IsA (Other "Anonymous")

                                in
                                    [ Triple subjectFqn IsA (Other "Field")
                                    , Triple recordTriple.subject Contains (FQN subjectFqn)
                                    , fieldTriple
                                    ]
                            )

                _ ->
                    []
    in
        recordTriple :: recordTypeTriple :: (List.concat fieldTriples)
