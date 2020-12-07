module Morphir.Graph.Tripler exposing (Triple, Object(..), mapDistribution)

import Dict
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type exposing (Type(..))


type Object
    = Other String
    | FQN FQName
    -- | PathOf Path.Path

type alias Triple =
    { subject : FQName
    , verb : String
    , object : Object
    }


mapDistribution : Distribution -> List Triple
mapDistribution distro =
    case distro of
        Distribution.Library packagePath _ packageDef ->
            mapPackageDefinition packagePath packageDef


mapPackageDefinition : Package.PackageName -> Package.Definition ta va -> List Triple
mapPackageDefinition packagePath packageDef =
    packageDef.modules
        |> Dict.toList
        |> List.concatMap
            (\( moduleName, accessControlledModuleDef ) ->
                mapModuleDefinition moduleName accessControlledModuleDef.value
            )


mapModuleDefinition : Module.ModuleName -> Module.Definition ta va -> List Triple
mapModuleDefinition moduleName moduleDef =
    moduleDef.types
        |> Dict.toList
        |> List.concatMap
            (\( typeName, accessControlledDocumentedTypeDef ) ->
                mapTypeDefinition moduleName typeName accessControlledDocumentedTypeDef.value.value
            )


mapTypeDefinition : Module.ModuleName -> Name -> Type.Definition ta -> List Triple
mapTypeDefinition moduleName typeName typeDef =
    case typeDef of
        Type.TypeAliasDefinition _ (Type.Record _ fields) ->
            fields
                |> List.map
                    (\field ->
                        let
                            subjectFqn = (FQName (Path.fromList [typeName]) moduleName field.name)
                        in
                            case field.tpe of 
                                Reference _ fqn _->
                                    Triple
                                        subjectFqn
                                        "isA"
                                        (FQN fqn)
                                _ ->
                                    Triple
                                        subjectFqn
                                        "isA"
                                        (Other "Anonymous")
                    )

        _ ->
            []
