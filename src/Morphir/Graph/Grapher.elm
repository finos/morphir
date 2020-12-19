module Morphir.Graph.Grapher exposing
    ( Edge
    , Graph
    , GraphEntry(..)
    , Node(..)
    , Verb(..)
    , graphEntryToComparable
    , mapDistribution
    , nodeType
    , verbToString
    )

import Dict exposing (Dict)
import List.Extra exposing (uniqueBy)
import Morphir.IR.AccessControlled exposing (withPublicAccess)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.FQName as FQName exposing (FQName(..))
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type exposing (Constructor(..), Specification(..), Type(..))
import Morphir.IR.Value as Value exposing (Value(..))


type Node
    = Record FQName
    | Field FQName Name
    | Type FQName
    | Function FQName
    | Unknown


type Verb
    = IsA
    | Aliases
    | Contains
    | Uses
    | Calls
    | Produces
    | Parameterizes
    | Unions


type alias Edge =
    { subject : Node
    , verb : Verb
    , object : Node
    }


type GraphEntry
    = NodeEntry Node
    | EdgeEntry Edge


type alias Graph =
    List GraphEntry


mapDistribution : Distribution -> Graph
mapDistribution distro =
    case distro of
        Distribution.Library packageName _ packageDef ->
            mapPackageDefinition packageName packageDef
                |> uniqueBy graphEntryToComparable


mapPackageDefinition : Package.PackageName -> Package.Definition ta va -> Graph
mapPackageDefinition packageName packageDef =
    packageDef.modules
        |> Dict.toList
        |> List.concatMap
            (\( moduleName, accessControlledModuleDef ) ->
                mapModuleDefinition packageName moduleName accessControlledModuleDef.value
            )


mapModuleDefinition : Package.PackageName -> Module.ModuleName -> Module.Definition ta va -> Graph
mapModuleDefinition packageName moduleName moduleDef =
    let
        typeTriples =
            moduleDef.types
                |> Dict.toList
                |> List.concatMap
                    (\( typeName, accessControlledDocumentedTypeDef ) ->
                        mapTypeDefinition packageName moduleName typeName accessControlledDocumentedTypeDef.value.value
                    )

        typeRegistry =
            typeTriples
                |> List.filterMap asNode
                |> List.map (\node -> ( nodeToKey node, node ))
                |> Dict.fromList

        valueTriples =
            moduleDef.values
                |> Dict.toList
                |> List.concatMap
                    (\( valueName, accessControlledDocumentedValueDef ) ->
                        mapValueDefinition packageName moduleName valueName accessControlledDocumentedValueDef.value typeRegistry
                    )
    in
    typeTriples ++ valueTriples


mapTypeDefinition : Package.PackageName -> Module.ModuleName -> Name -> Type.Definition ta -> Graph
mapTypeDefinition packageName moduleName typeName typeDef =
    let
        fqn =
            FQName packageName moduleName typeName

        triples =
            case typeDef of
                -- This is a definition of a record, so we want to collect that and its fields.
                Type.TypeAliasDefinition _ (Type.Record _ fields) ->
                    let
                        recordNode =
                            Record fqn

                        fieldTriples =
                            fields
                                |> List.map
                                    (\field ->
                                        let
                                            fieldNode =
                                                Field (FQName packageName moduleName typeName) field.name

                                            fieldType =
                                                case field.tpe of
                                                    Type.Reference _ typeFqn _ ->
                                                        Type typeFqn

                                                    _ ->
                                                        Unknown
                                        in
                                        [ NodeEntry fieldNode
                                        , NodeEntry fieldType -- This might result in duplicates, thus the uniqueBy at top
                                        , EdgeEntry (Edge recordNode Contains fieldNode)
                                        , EdgeEntry (Edge fieldNode IsA fieldType)
                                        ]
                                    )
                    in
                    NodeEntry recordNode :: List.concat fieldTriples

                -- This is a type alias, so we want to get that as a type and register the base type as well.
                Type.TypeAliasDefinition _ (Type.Reference _ aliasFQN _) ->
                    let
                        thisNode =
                            Type fqn

                        aliasNode =
                            Type aliasFQN
                    in
                    [ NodeEntry thisNode
                    , NodeEntry aliasNode
                    , EdgeEntry (Edge thisNode Aliases aliasNode)
                    ]

                -- A first class type definition, which is some combination of a union across subtypes.
                Type.CustomTypeDefinition _ accessControlledCtors ->
                    let
                        typeNode =
                            Type fqn

                        leafEntries =
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
                                                                        |> List.concatMap
                                                                            (\leafFqn ->
                                                                                let
                                                                                    leafNode =
                                                                                        Type leafFqn
                                                                                in
                                                                                [ NodeEntry leafNode
                                                                                , EdgeEntry (Edge typeNode Unions leafNode)
                                                                                ]
                                                                            )
                                                                )
                                            )
                                        |> List.concat

                                Nothing ->
                                    []
                    in
                    NodeEntry typeNode :: leafEntries

                _ ->
                    []
    in
    triples


mapValueDefinition : Package.PackageName -> Module.ModuleName -> Name -> Value.Definition ta va -> Dict String Node -> Graph
mapValueDefinition packageName moduleName valueName valueDef nodeRegistry =
    let
        lookupNode : String -> Maybe Node
        lookupNode key =
            nodeRegistry
                |> Dict.get key

        makeRefEdge : Node -> Verb -> String -> Node -> List GraphEntry
        makeRefEdge subject verb key default =
            let
                node =
                    lookupNode key
            in
            node
                |> Maybe.map (\object -> [ EdgeEntry (Edge subject verb object) ])
                |> Maybe.withDefault
                    [ NodeEntry default
                    , EdgeEntry (Edge subject verb default)
                    ]

        functionFqn =
            FQName packageName moduleName valueName

        functionNode =
            Function functionFqn

        -- Find out what input parameters this function uses
        inputTriples =
            valueDef.inputTypes
                |> List.concatMap
                    (\inputType ->
                        case inputType of
                            ( _, _, Type.Reference _ inputFqn children ) ->
                                collectReferenceNodes inputFqn children

                            _ ->
                                []
                    )
                |> List.concatMap
                    (\leafNode -> makeRefEdge functionNode Uses (nodeToKey leafNode) leafNode)

        -- This looks for function calls through the tree
        subFunctionTriples =
            let
                -- Looking for function call graph from this function
                collectFunctions : Value ta va -> Graph
                collectFunctions value =
                    case value of
                        -- Reference means we've found a function call
                        Value.Reference _ calledFQN ->
                            makeRefEdge functionNode Calls (referenceToKey calledFQN) (Function calledFQN)

                        --
                        -- The rest is calling back recursively on subtrees to collect all function calls throughout
                        --
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

        -- Capture what type(s) this function produces
        outputTriples =
            case valueDef.outputType of
                -- Returns a single type reference
                Type.Reference _ outputFQN _ ->
                    makeRefEdge functionNode Produces (referenceToKey outputFQN) (Type outputFQN)

                -- If returning a tuple, look inside of it
                Type.Tuple _ tupleTypes ->
                    tupleTypes
                        |> List.concatMap leafType
                        |> List.concatMap
                            (\leafFQN -> makeRefEdge functionNode Produces (referenceToKey leafFQN) (Type leafFQN))

                _ ->
                    []
    in
    NodeEntry functionNode :: (subFunctionTriples ++ inputTriples ++ outputTriples)


collectReferenceNodes : FQName -> List (Type ta) -> List Node
collectReferenceNodes referenceFQN children =
    case children of
        [] ->
            Type referenceFQN :: []

        _ ->
            children
                |> List.concatMap
                    (\child ->
                        case child of
                            Type.Reference _ childFQN grandChildren ->
                                collectReferenceNodes childFQN grandChildren

                            _ ->
                                []
                    )


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


asNode : GraphEntry -> Maybe Node
asNode entry =
    case entry of
        NodeEntry node ->
            Just node

        _ ->
            Nothing


asEdge : GraphEntry -> Maybe Edge
asEdge entry =
    case entry of
        EdgeEntry edge ->
            Just edge

        _ ->
            Nothing


nodeType : Node -> String
nodeType node =
    case node of
        Record _ ->
            "Record"

        Field _ _ ->
            "Field"

        Type _ ->
            "Type"

        Function _ ->
            "Function"

        Unknown ->
            "Unknown"


nodeFQN : Node -> FQName
nodeFQN node =
    case node of
        Record fqn ->
            fqn

        Field fqn _ ->
            fqn

        Type fqn ->
            fqn

        Function fqn ->
            fqn

        Unknown ->
            FQName [] [] [ "Unknown" ]


nodeToKey : Node -> String
nodeToKey node =
    case node of
        Field fqn name ->
            fieldToKey fqn name

        _ ->
            referenceToKey (nodeFQN node)


referenceToKey : FQName -> String
referenceToKey =
    fqnToString


fieldToKey : FQName -> Name -> String
fieldToKey fqn name =
    fqnToString fqn ++ "#" ++ Name.toSnakeCase name


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


fqnToString : FQName -> String
fqnToString fqn =
    String.join "."
        [ Path.toString Name.toSnakeCase "." (FQName.getPackagePath fqn)
        , Path.toString Name.toSnakeCase "." (FQName.getModulePath fqn)
        , Name.toSnakeCase (FQName.getLocalName fqn)
        ]


graphEntryToComparable : GraphEntry -> String
graphEntryToComparable entry =
    let
        edgeToString : Edge -> String
        edgeToString edge =
            nodeId edge.subject ++ " " ++ verbToString edge.verb ++ " " ++ nodeId edge.object

        nodeId : Node -> String
        nodeId node =
            nodeType node
                ++ ":"
                ++ (case node of
                        Record fqn ->
                            fqnToString fqn

                        Field fqn name ->
                            fqnToString fqn ++ "#" ++ Name.toSnakeCase name

                        Type fqn ->
                            fqnToString fqn

                        Function fqn ->
                            fqnToString fqn

                        Unknown ->
                            "unknown"
                   )
    in
    case entry of
        NodeEntry node ->
            "NodeEntry: " ++ nodeId node

        EdgeEntry edge ->
            "EdgeEntry: " ++ edgeToString edge
