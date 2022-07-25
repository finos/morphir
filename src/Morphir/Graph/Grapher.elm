module Morphir.Graph.Grapher exposing
    ( Node(..), Verb(..), Edge, GraphEntry(..), Graph
    , mapDistribution, mapPackageDefinition, mapModuleTypes, mapModuleValues, mapTypeDefinition, mapValueDefinition
    , graphEntryToComparable, nodeType, verbToString, nodeFQN, asEnum, edgeFromTuple, edgeToTuple, fqnToString
    )

{-| The Grapher module analyses a distribution to build a graph for dependency and lineage tracking purposes.
The goal is to understand data flow and to automate contribution to the types of products that are commonly used in
enterprises. The result of processing is a [Graph](#Graph), which is a collection of [Nodes](#Node) and [Edges](#Edge).


# Types

@docs Node, Verb, Edge, GraphEntry, Graph


# Processing

@docs mapDistribution, mapPackageDefinition, mapModuleTypes, mapModuleValues, mapTypeDefinition, mapValueDefinition


# Utilities

@docs graphEntryToComparable, nodeType, verbToString, nodeFQN, asEnum, edgeFromTuple, edgeToTuple, fqnToString

-}

import Dict exposing (Dict)
import List.Extra exposing (uniqueBy)
import Morphir.IR.AccessControlled exposing (Access(..), withPublicAccess)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value exposing (Value(..))


{-| Node defines a node in the graph. We capture specific node types for this purpose.
The types of constructs that we're interested in tracking are:

  - **Record** - Represents collection of fields. Corresponds to [Morphir.IR.Type.Record](/src/Morphir/IR/Type/Record)
  - **Field** - Represents a field within a Record.
  - **Type** - Represents a Type or Type Alias, which we want to track aliases through their hierarchies.
  - **Function** - Represents a Function.
  - **Enum** - Represents a restricted set of single name values.
  - **Function** - Represents a type that defines a strong unit of measure.
  - **Unknown** - Questionable practice, but it's useful to identify relationships we might want to track in the future.

-}
type Node
    = Record FQName
    | Field FQName Name
    | Type FQName
    | Function FQName
    | Enum FQName
    | UnitOfMeasure FQName
    | Unknown String


{-| Verb defines the possible relationships that we're interested in tracking. These are used to define the relationships
in the edges of our graph.

  - **IsA** - Denotes an implementation of a [Type](#Node) by fields, function parameters, and the such.
  - **Aliases** - Denotes a type alias, for which we want to track the full hierarchy.
  - **Contains** - Denotes [Fields](#Field) contained in a [Record](#Node)
  - **Uses** - Denotes use of a type by a [Function](#Node).
  - **Calls** - Denotes a [Function](#Node) call within another Function.
  - **Produces** - Denotes the output of a [Function](#Node).
  - **Parameterizes** - Denotes type variable usage.
  - **Unions** - Denotes the [Types](#Node) utilized in a union type.

-}
type Verb
    = IsA
    | Aliases
    | Contains
    | Uses
    | Calls
    | Produces
    | Parameterizes
    | Measures
    | Unions
    | Enumerates


{-| Defines an edge in the graph as a triple of the subject node, the relationship, and the object node.
-}
type alias Edge =
    { subject : Node
    , verb : Verb
    , object : Node
    }


{-| Defines the possible graph entries of [Node](#Node) and [Edge](#Edge).
-}
type GraphEntry
    = NodeEntry Node
    | EdgeEntry Edge


{-| Defines a graph as a collection of nodes and edges.
-}
type alias Graph =
    List GraphEntry


{-| Process this distribution into a Graph of its packages.
-}
mapDistribution : Distribution -> Graph
mapDistribution distro =
    case distro of
        Distribution.Library packageName _ packageDef ->
            mapPackageDefinition packageName packageDef
                |> uniqueBy graphEntryToComparable


{-| Process this package into a Graph of its modules. We take two passes to the IR. The first collects all of the
types and the second processes the functions and their relationships to those types.
-}
mapPackageDefinition : Package.PackageName -> Package.Definition ta va -> Graph
mapPackageDefinition packageName packageDef =
    let
        types =
            packageDef.modules
                |> Dict.toList
                |> List.concatMap
                    (\( moduleName, accessControlledModuleDef ) ->
                        mapModuleTypes packageName moduleName accessControlledModuleDef.value
                    )

        typeRegistry =
            types
                |> List.filterMap asNode
                |> List.map (\node -> ( nodeToKey node, node ))
                |> Dict.fromList

        values =
            packageDef.modules
                |> Dict.toList
                |> List.concatMap
                    (\( moduleName, accessControlledModuleDef ) ->
                        mapModuleValues packageName moduleName accessControlledModuleDef.value typeRegistry
                    )
    in
    values ++ types


{-| Process this module to collect the types used and produced by it.
-}
mapModuleTypes : Package.PackageName -> Module.ModuleName -> Module.Definition ta va -> Graph
mapModuleTypes packageName moduleName moduleDef =
    moduleDef.types
        |> Dict.toList
        |> List.concatMap
            (\( typeName, accessControlledDocumentedTypeDef ) ->
                mapTypeDefinition packageName moduleName typeName accessControlledDocumentedTypeDef.value.value
            )


{-| Process this module to collect the functions and relationships to types.
-}
mapModuleValues : Package.PackageName -> Module.ModuleName -> Module.Definition ta va -> Dict String Node -> Graph
mapModuleValues packageName moduleName moduleDef typeRegistry =
    moduleDef.values
        |> Dict.toList
        |> List.concatMap
            (\( valueName, accessControlledDocumentedValueDef ) ->
                mapValueDefinition packageName moduleName valueName accessControlledDocumentedValueDef.value.value typeRegistry
            )


{-| Process a type since there are a lot of variations.
-}
mapTypeDefinition : Package.PackageName -> Module.ModuleName -> Name -> Type.Definition ta -> Graph
mapTypeDefinition packageName moduleName typeName typeDef =
    let
        fqn =
            ( packageName, moduleName, typeName )

        edges =
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
                                                Field ( packageName, moduleName, typeName ) field.name

                                            fieldType =
                                                case field.tpe of
                                                    -- Catches Maybes
                                                    Type.Reference _ typeFqn [ Type.Reference _ child _ ] ->
                                                        Type child

                                                    Type.Reference _ typeFqn _ ->
                                                        Type typeFqn

                                                    _ ->
                                                        Unknown "Alias"
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

                        -- An enum, which represents a set of simple names
                        enums =
                            asEnum typeDef
                                |> List.map
                                    (\name ->
                                        EdgeEntry (Edge typeNode Enumerates (Enum ( FQName.getPackagePath fqn, FQName.getModulePath fqn, name )))
                                    )

                        -- A unit of measure type, which represents the declaration of a strong base type as opposed to a weaker alias.
                        unitOfMeasures =
                            asUnitOfMeasure typeDef
                                |> Maybe.map
                                    (\measureFqn ->
                                        EdgeEntry (Edge typeNode Measures (UnitOfMeasure measureFqn))
                                    )
                                |> Maybe.map (\x -> [ NodeEntry (UnitOfMeasure fqn), x ])
                                |> Maybe.withDefault []

                        unions =
                            if not (isUnitOfMeasure typeDef) then
                                case accessControlledCtors |> withPublicAccess of
                                    Just ctors ->
                                        ctors
                                            |> Dict.toList
                                            |> List.map
                                                (\( _, namesAndTypes ) ->
                                                    -- If this is a simple enum, extract the values
                                                    -- Otherwise, it's a complex union
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

                            else
                                []
                    in
                    NodeEntry typeNode :: (unions ++ enums ++ unitOfMeasures)

                _ ->
                    []
    in
    edges


isEnum : Dict a (List b) -> Bool
isEnum constructors =
    constructors
        |> Dict.toList
        |> List.all
            (\( _, args ) ->
                List.isEmpty args
            )


{-| -}
asEnum : Type.Definition ta -> List Name
asEnum typeDef =
    case typeDef of
        Type.CustomTypeDefinition _ accessControlledCtors ->
            case accessControlledCtors |> withPublicAccess of
                Just constructors ->
                    if isEnum constructors then
                        constructors
                            |> Dict.keys

                    else
                        []

                _ ->
                    []

        _ ->
            []


isUnitOfMeasure : Type.Definition ta -> Bool
isUnitOfMeasure typeDef =
    case typeDef of
        Type.CustomTypeDefinition _ accessControlledCtors ->
            let
                values =
                    accessControlledCtors
                        |> withPublicAccess
                        |> Maybe.map Dict.values
                        |> Maybe.withDefault []
            in
            case values of
                [ [ ( _, Type.Reference _ _ _ ) ] ] ->
                    True

                _ ->
                    False

        _ ->
            False


asUnitOfMeasure : Type.Definition ta -> Maybe FQName
asUnitOfMeasure typeDef =
    case typeDef of
        Type.CustomTypeDefinition _ accessControlledCtors ->
            let
                values =
                    accessControlledCtors
                        |> withPublicAccess
                        |> Maybe.map Dict.values
                        |> Maybe.withDefault []
            in
            case values of
                [ [ ( _, Type.Reference _ fqn _ ) ] ] ->
                    Just fqn

                _ ->
                    Nothing

        _ ->
            Nothing


{-| Process [Functions](#Type) specifically and ignore the rest.
-}
mapValueDefinition : Package.PackageName -> Module.ModuleName -> Name -> Value.Definition ta va -> Dict String Node -> Graph
mapValueDefinition packageName moduleName valueName valueDef nodeRegistry =
    let
        lookupNode : String -> Maybe Node
        lookupNode key =
            nodeRegistry
                |> Dict.get key

        makeRefEdge : Node -> Verb -> FQName -> Node -> List GraphEntry
        makeRefEdge subject verb key default =
            let
                node =
                    lookupNode (fqnToString key)
            in
            node
                |> Maybe.map (\object -> [ EdgeEntry (Edge subject verb object) ])
                |> Maybe.withDefault
                    [ NodeEntry default
                    , EdgeEntry (Edge subject verb default)
                    ]

        functionFqn =
            ( packageName, moduleName, valueName )

        functionNode =
            Function functionFqn

        -- Traverse the list of input parameters to find out what types this function uses
        inputTriples =
            valueDef.inputTypes
                |> List.concatMap
                    (\inputType ->
                        case inputType of
                            ( _, _, Type.Reference _ inputFqn children ) ->
                                collectReferences inputFqn children

                            _ ->
                                []
                    )
                |> List.concatMap
                    (\fqn -> makeRefEdge functionNode Uses fqn (Type fqn))

        -- This looks for function calls through the tree
        subFunctionTriples =
            let
                -- Looking for function call graph from this function
                collectFunctions : Value ta va -> Graph
                collectFunctions value =
                    case value of
                        -- Reference means we've found a function call
                        Value.Reference _ calledFQN ->
                            makeRefEdge functionNode Calls calledFQN (Function calledFQN)

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
                            collectFunctions v ++ (tuples |> List.map Tuple.second |> List.concatMap collectFunctions)

                        Value.UpdateRecord _ v dict ->
                            collectFunctions v ++ (Dict.values dict |> List.concatMap collectFunctions)

                        _ ->
                            []
            in
            collectFunctions valueDef.body

        -- Capture what type(s) this function produces
        outputTriples =
            case valueDef.outputType of
                -- Returns a single type reference
                Type.Reference _ outputFQN _ ->
                    makeRefEdge functionNode Produces outputFQN (Type outputFQN)

                -- If returning a tuple, look inside of it
                Type.Tuple _ tupleTypes ->
                    tupleTypes
                        |> List.concatMap leafType
                        |> List.concatMap
                            (\leafFQN -> makeRefEdge functionNode Produces leafFQN (Type leafFQN))

                _ ->
                    []
    in
    NodeEntry functionNode :: (subFunctionTriples ++ inputTriples ++ outputTriples)


{-| Process a [Reference](/src/Morphir/IR/Type). We're basically differentiating straight references versus union types,
for which we want to drill in deeper.
-}
collectReferences : FQName -> List (Type ta) -> List FQName
collectReferences referenceFQN children =
    case children of
        [] ->
            referenceFQN :: []

        _ ->
            children
                |> List.concatMap
                    (\child ->
                        case child of
                            Type.Reference _ childFQN grandChildren ->
                                collectReferences childFQN grandChildren

                            _ ->
                                []
                    )


{-| Process a [Reference](/src/Morphir/IR/Type). We're basically differentiating straight references versus union types,
for which we want to drill in deeper.
-}
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


{-| Utility to filter out just the [Nodes](#Node) from a [Graph](#Graph).
-}
asNode : GraphEntry -> Maybe Node
asNode entry =
    case entry of
        NodeEntry node ->
            Just node

        _ ->
            Nothing


{-| Utility to filter out just the [Edges](#Edge) from a [Graph](#Graph).
-}
asEdge : GraphEntry -> Maybe Edge
asEdge entry =
    case entry of
        EdgeEntry edge ->
            Just edge

        _ ->
            Nothing


{-| Utility to extract the [Node](#Node) type as a String.
-}
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

        Enum _ ->
            "Enum"

        UnitOfMeasure _ ->
            "Unit"

        Unknown _ ->
            "Unknown"


{-| Utility to extract the [Fully Qualified Name](/src/Morphir/IR/FQName) from a [Node](#Node). This is required
because a Field contains both an FQN and field name.
-}
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

        Enum fqn ->
            fqn

        UnitOfMeasure fqn ->
            fqn

        Unknown s ->
            ( [], [], [ s ] )


{-| Utility for dealing with comparable.
-}
nodeToKey : Node -> String
nodeToKey node =
    case node of
        Field fqn name ->
            fieldToKey fqn name

        _ ->
            referenceToKey (nodeFQN node)


{-| Converte Edge record to tuple
-}
edgeToTuple : Edge -> ( Node, Verb, Node )
edgeToTuple edge =
    ( edge.subject, edge.verb, edge.object )


{-| Converte Edge record to tuple
-}
edgeFromTuple : ( Node, Verb, Node ) -> Edge
edgeFromTuple tuple =
    let
        ( subject, verb, object ) =
            tuple
    in
    Edge subject verb object


{-| Utility for dealing with comparable.
-}
referenceToKey : FQName -> String
referenceToKey =
    fqnToString


{-| Utility for dealing with comparable.
-}
fieldToKey : FQName -> Name -> String
fieldToKey fqn name =
    fqnToString fqn ++ "#" ++ Name.toSnakeCase name


{-| Utility for dealing with comparable.
-}
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

        Enumerates ->
            "enumerates"

        Measures ->
            "measures"


{-| Utility for dealing with comparable.
-}
fqnToString : FQName -> String
fqnToString fqn =
    String.join "."
        [ Path.toString Name.toSnakeCase "." (FQName.getPackagePath fqn)
        , Path.toString Name.toSnakeCase "." (FQName.getModulePath fqn)
        , Name.toSnakeCase (FQName.getLocalName fqn)
        ]


{-| Utility for dealing with comparable.
-}
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

                        Enum fqn ->
                            fqnToString fqn

                        UnitOfMeasure fqn ->
                            fqnToString fqn

                        Unknown s ->
                            "unknown:" ++ s
                   )
    in
    case entry of
        NodeEntry node ->
            "NodeEntry: " ++ nodeId node

        EdgeEntry edge ->
            "EdgeEntry: " ++ edgeToString edge
