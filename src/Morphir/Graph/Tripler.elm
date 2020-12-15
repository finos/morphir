module Morphir.Graph.Tripler exposing
    ( NodeType(..)
    , Object(..)
    , Triple
    , Verb(..)
    , mapDistribution
    , nodeTypeToString
    , verbToString
    )

import Dict
import Morphir.IR.AccessControlled exposing (withPublicAccess)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.FQName as FQName exposing (FQName(..))
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type exposing (Constructor(..), Specification(..), Type(..))
import Morphir.IR.Value as Value exposing (Value(..))
import Set exposing (Set)


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
    | Aliases
    | Contains
    | Uses
    | Calls
    | Produces
    | Parameterizes
    | Unions


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
    let
        typeTriples =
            moduleDef.types
                |> Dict.toList
                |> List.concatMap
                    (\( typeName, accessControlledDocumentedTypeDef ) ->
                        mapTypeDefinition packageName moduleName typeName accessControlledDocumentedTypeDef.value.value
                    )

        valueTriples =
            moduleDef.values
                |> Dict.toList
                |> List.concatMap
                    (\( valueName, accessControlledDocumentedValueDef ) ->
                        mapValueDefinition packageName moduleName valueName accessControlledDocumentedValueDef.value
                    )
    in
    typeTriples ++ valueTriples


mapTypeDefinition : Package.PackageName -> Module.ModuleName -> Name -> Type.Definition ta -> List Triple
mapTypeDefinition packageName moduleName typeName typeDef =
    let
        fqn =
            FQName packageName moduleName typeName

        triples =
            case typeDef of
                Type.TypeAliasDefinition _ (Type.Record _ fields) ->
                    let
                        recordTriple =
                            Triple fqn IsA (Node Record)

                        fieldTriples =
                            fields
                                |> List.map
                                    (\field ->
                                        let
                                            subjectFqn =
                                                FQName packageName (List.append moduleName [ typeName ]) field.name

                                            fieldTriple =
                                                case field.tpe of
                                                    Type.Reference _ typeFqn _ ->
                                                        Triple subjectFqn IsA (FQN typeFqn)

                                                    _ ->
                                                        Triple subjectFqn IsA (Other "Anonymous")
                                        in
                                        [ Triple recordTriple.subject Contains (FQN subjectFqn)
                                        , Triple subjectFqn IsA (Node Field)
                                        , fieldTriple
                                        ]
                                    )
                    in
                    recordTriple :: List.concat fieldTriples

                Type.TypeAliasDefinition _ (Type.Reference _ aliasFQN _) ->
                    [ Triple fqn IsA (Node Type)
                    , Triple fqn Aliases (FQN aliasFQN)
                    ]

                Type.CustomTypeDefinition _ accessControlledCtors ->
                    let
                        typeTriple =
                            Triple fqn IsA (Node Type)

                        childrenTriples =
                            case accessControlledCtors |> withPublicAccess of
                                Just ctors ->
                                    ctors
                                        |> List.map
                                            (\constructor ->
                                                case constructor of
                                                    Type.Constructor _ namesAndTypes ->
                                                        namesAndTypes
                                                            |> List.concatMap
                                                                (\( _, tipe ) ->
                                                                    leafType tipe
                                                                        |> List.map
                                                                            (\leafFqn ->
                                                                                Triple fqn Unions (FQN leafFqn)
                                                                            )
                                                                )
                                            )
                                        |> List.concat

                                Nothing ->
                                    []
                    in
                    typeTriple :: childrenTriples

                _ ->
                    []
    in
    triples


mapValueDefinition : Package.PackageName -> Module.ModuleName -> Name -> Value.Definition ta va -> List Triple
mapValueDefinition packageName moduleName valueName valueDef =
    let
        functionTriple =
            Triple (FQName packageName moduleName valueName) IsA (Node Function)

        subFunctionTriples =
            let
                collectFunctions : Value ta va -> List Triple
                collectFunctions value =
                    case value of
                        Value.Reference _ functionFQN ->
                            Triple functionTriple.subject Calls (FQN functionFQN) :: []

                        Value.Tuple _ values ->
                            values |> List.concatMap collectFunctions

                        Value.List _ values ->
                            values |> List.concatMap collectFunctions

                        Value.Field _ v name ->
                            collectFunctions v

                        Value.Apply _ value1 value2 ->
                            [ value1, value2 ] |> List.concatMap collectFunctions

                        Value.Lambda _ _ v ->
                            collectFunctions v

                        Value.LetDefinition _ _ _ v ->
                            collectFunctions v

                        Value.LetRecursion _ _ v ->
                            collectFunctions v

                        Value.Destructure _ _ value1 value2 ->
                            [ value1, value2 ] |> List.concatMap collectFunctions

                        Value.IfThenElse _ value1 value2 value3 ->
                            [ value1, value2, value3 ] |> List.concatMap collectFunctions

                        Value.PatternMatch _ v tuples ->
                            collectFunctions v ++ (tuples |> List.map (\( tk, tv ) -> tv) |> List.concatMap collectFunctions)

                        Value.UpdateRecord _ v tuples ->
                            collectFunctions v ++ (tuples |> List.map (\( tk, tv ) -> tv) |> List.concatMap collectFunctions)

                        _ ->
                            []
            in
            collectFunctions valueDef.body

        outputTriples =
            case valueDef.outputType of
                Type.Reference _ outputFQN _ ->
                    Triple functionTriple.subject Produces (FQN outputFQN) :: []

                Type.Tuple _ tupleTypes ->
                    tupleTypes
                        |> List.concatMap leafType
                        |> List.map (\leafFQN -> Triple functionTriple.subject Produces (FQN leafFQN))

                Type.Variable _ name ->
                    Triple functionTriple.subject Produces (FQN (FQName packageName moduleName name)) :: []

                _ ->
                    []

        inputTriples =
            valueDef.inputTypes
                |> List.filterMap
                    (\inputType ->
                        case inputType of
                            ( _, _, Type.Reference _ inputFqn _ ) ->
                                Just inputFqn

                            _ ->
                                Nothing
                    )
                |> List.map (\leafFQN -> Triple functionTriple.subject Uses (FQN leafFQN))

        -- temp
    in
    functionTriple :: (subFunctionTriples ++ inputTriples ++ outputTriples)


leafType : Type a -> List FQName
leafType tipe =
    case tipe of
        Type.Reference _ tipeFQN paramTypes ->
            case paramTypes of
                [] ->
                    tipeFQN :: []

                _ ->
                    List.concatMap leafType paramTypes

        _ ->
            []



-- TODO


nodeTypeToString : NodeType -> String
nodeTypeToString node =
    case node of
        Record ->
            "Record"

        Field ->
            "Field"

        Type ->
            "Type"

        Function ->
            "Function"


verbToString : Verb -> String
verbToString verb =
    case verb of
        IsA ->
            "isA"

        Aliases ->
            "aliases"

        Contains ->
            "contains"

        Uses ->
            "uses"

        Calls ->
            "calls"

        Produces ->
            "produces"

        Parameterizes ->
            "parameterizes"

        Unions ->
            "unions"
