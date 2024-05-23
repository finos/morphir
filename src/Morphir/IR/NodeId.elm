module Morphir.IR.NodeId exposing
    ( NodeID(..), NodePath, NodePathStep(..)
    , nodeIdFromString, nodeIdToString, nodePathFromString, nodePathToString, getAttribute
    , mapPatternAttributesWithNodePath, mapTypeAttributeWithNodePath, mapValueAttributesWithNodePath
    , getTypeAttributeByPath, getValueAttributeByPath
    , Error(..)
    )

{-| A data type that represents a node in the IR

@docs NodeID, NodePath, NodePathStep
@docs nodeIdFromString, nodeIdToString, nodePathFromString, nodePathToString, getAttribute
@docs mapPatternAttributesWithNodePath, mapTypeAttributeWithNodePath, mapValueAttributesWithNodePath
@docs getTypeAttributeByPath, getValueAttributeByPath
@docs Error

-}

import Dict exposing (Dict)
import List.Extra
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package exposing (lookupValueDefinition)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Type as Type exposing (Field, Type(..))
import Morphir.IR.Value as Value exposing (Value(..))


{-| Represents a path in the IR. This is a recursive structure made up of the following
building blocks:

  - **ChildByName** traverses to a child node by name. It takes one argument
      - the name of the edge to follow (this will usually be a field name)
  - **ChildByIndex** traverses to a child node by index. It takes one argument
      - the index of the child node (the list of children will be determined by the type of the node that we are currently on)

The path should be constructed in a reverse order: the node at the top will be the last step in the path

Example usage:

    type alias Foo =
        { field1 : Bool
        , field2 :
            { field1 : Int
            , field2 : ( String, Float )
            }
        }

    NodePath.fromList [] -- Refers to type "Foo" itself

    NodePath.fromList [ ChildByName "field1" ] -- Refers to Bool

    NodePath.fromList [ ChildByName "field2", ChildByName "field1" ] -- Refers to Int

    NodePath.fromList [ ChildByName "field2", ChildByName "field2", ChildByIndex 1 ] -- Refers to Float

-}
type alias NodePath =
    List NodePathStep


{-| Represents a path to a child node
-}
type NodePathStep
    = ChildByName Name
    | ChildByIndex Int


{-| Represents a node in the IR. Could be a Type, Value or Module
-}
type NodeID
    = TypeID FQName NodePath
    | ValueID FQName NodePath
    | ModuleID ( Path, Path )


{-| Represents an error that might occur during node operations
-}
type Error
    = InvalidPath String
    | InvalidNodeID String


{-| Try to parse a string into NodeID.
Return an Error if it's not a valid NodeID.
-}
nodeIdFromString : String -> Result Error NodeID
nodeIdFromString str =
    let
        returnError : Result Error value
        returnError =
            Err <| InvalidNodeID ("Invalid NodeID: " ++ str)

        mapToTypeOrValue : String -> String -> String -> String -> Result Error NodeID
        mapToTypeOrValue packageName moduleName defNameWithSuffix nodePath =
            let
                getDefname : String -> String
                getDefname suffix =
                    String.dropRight (String.length suffix) defNameWithSuffix
            in
            if String.endsWith ".value" defNameWithSuffix then
                Ok (ValueID (FQName.fqn packageName moduleName (getDefname ".value")) (nodePathFromString nodePath))

            else
                Ok (TypeID (FQName.fqn packageName moduleName (getDefname ".type")) (nodePathFromString nodePath))
    in
    case String.split ":" str of
        [ packageName, moduleName ] ->
            Ok (ModuleID ( packageName |> Path.fromString, moduleName |> Path.fromString ))

        [ packageName, moduleName, localName ] ->
            if String.contains "#" localName then
                case String.split "#" localName of
                    [ defName, path ] ->
                        mapToTypeOrValue packageName moduleName defName path

                    _ ->
                        returnError

            else
                mapToTypeOrValue packageName moduleName localName ""

        _ ->
            returnError


{-| Convert a NodeID to String.
-}
nodeIdToString : NodeID -> String
nodeIdToString nodeId =
    let
        mapToTypeOrValue : Path -> Path -> Name -> String -> List NodePathStep -> String
        mapToTypeOrValue packageName moduleName localName suffix nodePath =
            let
                constructNodeIdString : String
                constructNodeIdString =
                    String.join ":"
                        [ Path.toString Name.toTitleCase "." packageName
                        , Path.toString Name.toTitleCase "." moduleName
                        , Name.toCamelCase localName ++ suffix
                        ]
            in
            if List.isEmpty nodePath then
                constructNodeIdString

            else
                constructNodeIdString ++ nodePathToString nodePath
    in
    case nodeId of
        TypeID ( packageName, moduleName, localName ) nodePath ->
            mapToTypeOrValue packageName moduleName localName ".type" nodePath

        ValueID ( packageName, moduleName, localName ) nodePath ->
            mapToTypeOrValue packageName moduleName localName ".value" nodePath

        ModuleID ( packageName, moduleName ) ->
            String.join ":"
                [ Path.toString Name.toTitleCase "." packageName
                , Path.toString Name.toTitleCase "." moduleName
                ]


{-| Convert a NodePath to String.
-}
nodePathToString : NodePath -> String
nodePathToString nodePath =
    if List.isEmpty nodePath then
        ""

    else
        "#"
            ++ (nodePath
                    |> List.map
                        (\pathStep ->
                            case pathStep of
                                ChildByName name ->
                                    Name.toCamelCase name

                                ChildByIndex index ->
                                    String.fromInt index
                        )
                    |> String.join ":"
               )


{-| Parse a String into a NodePath.
-}
nodePathFromString : String -> NodePath
nodePathFromString string =
    if String.isEmpty string then
        []

    else
        string
            |> String.split ":"
            |> List.map
                (\stepString ->
                    case String.toInt stepString of
                        Just index ->
                            ChildByIndex index

                        Nothing ->
                            ChildByName (Name.fromString stepString)
                )


{-| Utility function to return an error if the path is invalid.
-}
returnInvalidPathError : NodePath -> Result Error value
returnInvalidPathError pathSoFar =
    case nodePathToString pathSoFar of
        "" ->
            Err <| InvalidPath "Path is invalid"

        _ ->
            Err <| InvalidPath ("Path is invalid after " ++ nodePathToString pathSoFar)


{-| Get attribute from a list of types or values by index.
Return error if the NodePath is invalid.
-}
getFromList : List NodePathStep -> List NodePathStep -> (NodePath -> NodePath -> a -> Result Error attr) -> List a -> Result Error attr
getFromList nonEmptyPath pathSoFar recursiveFunction list =
    case nonEmptyPath of
        ((ChildByIndex n) as current) :: xs ->
            list
                |> List.Extra.getAt n
                |> Maybe.map (recursiveFunction xs (List.append [ current ] pathSoFar))
                |> Maybe.withDefault (returnInvalidPathError pathSoFar)

        _ ->
            returnInvalidPathError pathSoFar


{-| Get attribute from a module, type or value by NodeID.
Return error, if the NodeID is invalid.
-}
getAttribute : Package.Definition attr attr -> NodeID -> Result Error attr
getAttribute packageDef nodeId =
    let
        invalidNodeId : NodeID -> Result Error value
        invalidNodeId ni =
            Err <| InvalidNodeID (nodeIdToString ni)
    in
    case nodeId of
        ModuleID ( _, _ ) ->
            Debug.todo "not implemented for modules yet"

        TypeID ( _, modulePath, localName ) nodePath ->
            case Dict.get modulePath packageDef.modules of
                Nothing ->
                    invalidNodeId nodeId

                Just accessControlledModuleDef ->
                    case Dict.get localName accessControlledModuleDef.value.types of
                        Nothing ->
                            invalidNodeId nodeId

                        Just typeDef ->
                            case typeDef.value.value of
                                Type.TypeAliasDefinition _ a ->
                                    getTypeAttributeByPath nodePath a

                                Type.CustomTypeDefinition _ accessControlledCtors ->
                                    case accessControlledCtors.value |> Dict.toList of
                                        [ ( ctorName, [ ( _, baseType ) ] ) ] ->
                                            if ctorName == localName then
                                                getTypeAttributeByPath nodePath baseType

                                            else
                                                invalidNodeId nodeId

                                        _ ->
                                            invalidNodeId nodeId

        ValueID ( _, modulePath, localName ) nodePath ->
            case lookupValueDefinition modulePath localName packageDef |> Maybe.map .body of
                Just v ->
                    getValueAttributeByPath nodePath v

                Nothing ->
                    Err <| InvalidNodeID (nodeIdToString nodeId)


{-| Given a map function, a NodePath, and a type, recursively map the type's attributes using the provided map function.
-}
mapTypeAttributeWithNodePathRec : (NodePath -> attr -> attr2) -> NodePath -> Type attr -> Type attr2
mapTypeAttributeWithNodePathRec mf pathToMe t =
    let
        mapList : List (Type attr) -> List (Type attr2)
        mapList =
            List.indexedMap
                (\i el -> mapTypeAttributeWithNodePathRec mf (pathToMe ++ [ ChildByIndex i ]) el)

        mapFieldList : List (Field attr) -> List (Field attr2)
        mapFieldList =
            List.map
                (\el -> { name = el.name, tpe = mapTypeAttributeWithNodePathRec mf (pathToMe ++ [ ChildByName el.name ]) el.tpe })

        mapAttribute : attr -> attr2
        mapAttribute a =
            mf pathToMe a
    in
    case t of
        Type.Variable a name ->
            Type.Variable (mapAttribute a) name

        Type.Reference a fqn argList ->
            Type.Reference (mapAttribute a)
                fqn
                (argList |> mapList)

        Type.Tuple a tupleElems ->
            Type.Tuple (mapAttribute a)
                (tupleElems |> mapList)

        Type.Record a fieldList ->
            Type.Record (mapAttribute a)
                (fieldList |> mapFieldList)

        Type.ExtensibleRecord a name fieldList ->
            Type.ExtensibleRecord (mapAttribute a)
                name
                (fieldList |> mapFieldList)

        Type.Function a input output ->
            Type.Function (mapAttribute a)
                (mapTypeAttributeWithNodePathRec mf (pathToMe ++ [ ChildByIndex 0 ]) input)
                (mapTypeAttributeWithNodePathRec mf (pathToMe ++ [ ChildByIndex 1 ]) output)

        Type.Unit a ->
            Type.Unit (mapAttribute a)


{-| Applies the given map function to the attributes of every node of the given type.
-}
mapTypeAttributeWithNodePath : (NodePath -> attr -> attr2) -> Type attr -> Type attr2
mapTypeAttributeWithNodePath mapFunc tpe =
    mapTypeAttributeWithNodePathRec mapFunc [] tpe


{-| Applies the given map function to the attributes of every node of the given value.
-}
mapValueAttributesWithNodePath : (NodePath -> attr -> attr2) -> Value attr attr -> Value attr2 attr2
mapValueAttributesWithNodePath mapFunc value =
    let
        mapValueAttributesWithNodePathRec : (NodePath -> attr -> attr2) -> NodePath -> Value attr attr -> Value attr2 attr2
        mapValueAttributesWithNodePathRec mf pathToMe v =
            let
                mapAttribute : attr -> attr2
                mapAttribute a =
                    mf pathToMe a

                leafNodeMap : Value attr attr -> Value attr2 attr2
                leafNodeMap leafnode =
                    Value.mapValueAttributes mapAttribute mapAttribute leafnode

                mapList : List (Value attr attr) -> List (Value attr2 attr2)
                mapList =
                    List.indexedMap
                        (\i el -> mapValueAttributesWithNodePathRec mf (pathToMe ++ [ ChildByIndex i ]) el)

                mapDict : NodePath -> Dict Name (Value attr attr) -> Dict Name (Value attr2 attr2)
                mapDict path dict =
                    dict
                        |> Dict.toList
                        |> List.map
                            (\el -> el |> Tuple.mapSecond (mapValueAttributesWithNodePathRec mf (path ++ [ ChildByName (Tuple.first el) ])))
                        |> Dict.fromList

                mapDefinition : NodePath -> Value.Definition attr attr -> Value.Definition attr2 attr2
                mapDefinition path def =
                    let
                        mapType : Int -> Type attr -> Type attr2
                        mapType n t =
                            mapTypeAttributeWithNodePathRec mf (path ++ [ ChildByName [ "inputTypes" ], ChildByIndex n, ChildByIndex 1 ]) t
                    in
                    Value.Definition
                        (def.inputTypes
                            |> List.indexedMap
                                (\i ( name, a, inputType ) -> ( name, mf (path ++ [ ChildByName [ "inputTypes" ], ChildByIndex i, ChildByIndex 0 ]) a, mapType i inputType ))
                        )
                        (def.outputType |> mapTypeAttributeWithNodePathRec mf (path ++ [ ChildByName [ "outputType" ] ]))
                        (def.body |> mapValueAttributesWithNodePathRec mf (path ++ [ ChildByName [ "body" ] ]))
            in
            case v of
                Value.Unit _ ->
                    leafNodeMap v

                Value.Literal _ _ ->
                    leafNodeMap v

                Value.Constructor a fqn ->
                    Value.Constructor (mapAttribute a) fqn

                Value.Tuple a tupleList ->
                    Value.Tuple (mapAttribute a) (mapList tupleList)

                Value.List a list ->
                    Value.List (mapAttribute a) (mapList list)

                Value.Record a recordDict ->
                    Value.Record (mapAttribute a)
                        (mapDict pathToMe recordDict)

                Value.Variable _ _ ->
                    leafNodeMap v

                Value.Reference _ _ ->
                    leafNodeMap v

                Value.Field a val name ->
                    Value.Field
                        (mapAttribute a)
                        (mapValueAttributesWithNodePathRec mf (pathToMe ++ [ ChildByIndex 0 ]) val)
                        name

                Value.FieldFunction _ _ ->
                    leafNodeMap v

                Value.Apply a input output ->
                    Value.Apply
                        (mapAttribute a)
                        (mapValueAttributesWithNodePathRec mf (pathToMe ++ [ ChildByIndex 0 ]) input)
                        (mapValueAttributesWithNodePathRec mf (pathToMe ++ [ ChildByIndex 1 ]) output)

                Value.Lambda a pattern lambdaVal ->
                    Value.Lambda
                        (mapAttribute a)
                        (mapPatternAttributesWithNodePathRec mf (pathToMe ++ [ ChildByIndex 0 ]) pattern)
                        (mapValueAttributesWithNodePathRec mf (pathToMe ++ [ ChildByIndex 1 ]) lambdaVal)

                Value.LetDefinition a name def val ->
                    Value.LetDefinition
                        (mapAttribute a)
                        name
                        (mapDefinition (pathToMe ++ [ ChildByIndex 0 ]) def)
                        (mapValueAttributesWithNodePathRec mf (pathToMe ++ [ ChildByIndex 1 ]) val)

                Value.LetRecursion a definitionDict val ->
                    Value.LetRecursion
                        (mapAttribute a)
                        (Dict.map (\name definition -> mapDefinition (pathToMe ++ [ ChildByName name ]) definition) definitionDict)
                        (mapValueAttributesWithNodePathRec mf (pathToMe ++ [ ChildByIndex 1 ]) val)

                Value.Destructure a pattern v1 v2 ->
                    Value.Destructure
                        (mapAttribute a)
                        (mapPatternAttributesWithNodePathRec mf (pathToMe ++ [ ChildByIndex 0 ]) pattern)
                        (mapValueAttributesWithNodePathRec mf (pathToMe ++ [ ChildByIndex 1 ]) v1)
                        (mapValueAttributesWithNodePathRec mf (pathToMe ++ [ ChildByIndex 2 ]) v2)

                Value.IfThenElse a condition thenBranch elseBranch ->
                    Value.IfThenElse
                        (mapAttribute a)
                        (mapValueAttributesWithNodePathRec mf (pathToMe ++ [ ChildByIndex 0 ]) condition)
                        (mapValueAttributesWithNodePathRec mf (pathToMe ++ [ ChildByIndex 1 ]) thenBranch)
                        (mapValueAttributesWithNodePathRec mf (pathToMe ++ [ ChildByIndex 2 ]) elseBranch)

                Value.PatternMatch a val patternList ->
                    Value.PatternMatch
                        (mapAttribute a)
                        (mapValueAttributesWithNodePathRec mf (pathToMe ++ [ ChildByIndex 0 ]) val)
                        (patternList
                            |> List.indexedMap
                                (\i pv ->
                                    Tuple.pair (mapPatternAttributesWithNodePathRec mf (pathToMe ++ [ ChildByIndex 1, ChildByIndex i, ChildByIndex 0 ]) (Tuple.first pv))
                                        (mapValueAttributesWithNodePathRec mf (pathToMe ++ [ ChildByIndex 1, ChildByIndex i, ChildByIndex 1 ]) (Tuple.second pv))
                                )
                        )

                Value.UpdateRecord a rec updateDict ->
                    Value.UpdateRecord
                        (mapAttribute a)
                        (mapValueAttributesWithNodePathRec mf (pathToMe ++ [ ChildByIndex 0 ]) rec)
                        (mapDict (pathToMe ++ [ ChildByIndex 1 ]) updateDict)
    in
    mapValueAttributesWithNodePathRec mapFunc [] value


{-| Applies the given map function to the attributes of every node of the given pattern.
-}
mapPatternAttributesWithNodePath : (NodePath -> attr -> attr2) -> Value.Pattern attr -> Value.Pattern attr2
mapPatternAttributesWithNodePath mapFunc pattern =
    mapPatternAttributesWithNodePathRec mapFunc [] pattern


{-| Given a map function, a NodePath, and a pattern, recursively map the pattern's attributes using the provided map function.
-}
mapPatternAttributesWithNodePathRec : (NodePath -> attr -> attr2) -> NodePath -> Value.Pattern attr -> Value.Pattern attr2
mapPatternAttributesWithNodePathRec mapFunc pathToMe pattern =
    let
        mapList : List (Value.Pattern attr) -> List (Value.Pattern attr2)
        mapList patternList =
            patternList |> List.indexedMap (\i p -> mapPatternAttributesWithNodePathRec mapFunc (pathToMe ++ [ ChildByIndex i ]) p)
    in
    case pattern of
        Value.UnitPattern a ->
            Value.UnitPattern (mapFunc pathToMe a)

        Value.WildcardPattern a ->
            Value.WildcardPattern (mapFunc pathToMe a)

        Value.AsPattern a p name ->
            Value.AsPattern (mapFunc pathToMe a)
                (mapPatternAttributesWithNodePathRec mapFunc (pathToMe ++ [ ChildByIndex 0 ]) p)
                name

        Value.TuplePattern a tupleList ->
            Value.TuplePattern
                (mapFunc pathToMe a)
                (mapList tupleList)

        Value.ConstructorPattern a fqn argList ->
            Value.ConstructorPattern
                (mapFunc pathToMe a)
                fqn
                (mapList argList)

        Value.EmptyListPattern a ->
            Value.EmptyListPattern
                (mapFunc pathToMe a)

        Value.HeadTailPattern a head tail ->
            Value.HeadTailPattern
                (mapFunc pathToMe a)
                (mapPatternAttributesWithNodePathRec mapFunc (pathToMe ++ [ ChildByIndex 0 ]) head)
                (mapPatternAttributesWithNodePathRec mapFunc (pathToMe ++ [ ChildByIndex 1 ]) tail)

        Value.LiteralPattern a literal ->
            Value.LiteralPattern
                (mapFunc pathToMe a)
                literal


{-| Get type attribute by NodePath.
Return an Error if the NodePath is invalid.
-}
getTypeAttributeByPath : NodePath -> Type attr -> Result Error attr
getTypeAttributeByPath path tpea =
    let
        getTypeAttributeByPathRec : NodePath -> NodePath -> Type attr -> Result Error attr
        getTypeAttributeByPathRec remainingPath pathSoFar tpe =
            let
                addToValidpath : NodePathStep -> NodePath
                addToValidpath current =
                    List.append [ current ] pathSoFar

                getFromFieldList : List NodePathStep -> List (Field attr) -> Result Error attr
                getFromFieldList nonEmptyPath fieldList =
                    let
                        findFirst : Name -> List (Field attr) -> Maybe (Field attr)
                        findFirst name =
                            List.Extra.find (\field -> field.name == name)
                    in
                    case nonEmptyPath of
                        ((ChildByName n) as current) :: xs ->
                            fieldList
                                |> findFirst n
                                |> Maybe.map (.tpe >> getTypeAttributeByPathRec xs (addToValidpath current))
                                |> Maybe.withDefault (returnInvalidPathError pathSoFar)

                        _ ->
                            getFromList nonEmptyPath pathSoFar getTypeAttributeByPathRec (List.map .tpe fieldList)
            in
            case remainingPath of
                [] ->
                    tpe |> Type.typeAttributes |> Ok

                nonEmptyPath ->
                    case tpe of
                        Type.Tuple _ tupleList ->
                            getFromList nonEmptyPath pathSoFar getTypeAttributeByPathRec tupleList

                        Type.Record _ fieldList ->
                            getFromFieldList nonEmptyPath fieldList

                        Type.Reference _ _ tpeList ->
                            getFromList nonEmptyPath pathSoFar getTypeAttributeByPathRec tpeList

                        Type.ExtensibleRecord _ _ fieldList ->
                            getFromFieldList nonEmptyPath fieldList

                        Type.Function _ input output ->
                            case nonEmptyPath of
                                ((ChildByIndex 0) as current) :: xs ->
                                    getTypeAttributeByPathRec xs (addToValidpath current) input

                                ((ChildByIndex 1) as current) :: xs ->
                                    getTypeAttributeByPathRec xs (addToValidpath current) output

                                _ ->
                                    returnInvalidPathError pathSoFar

                        _ ->
                            returnInvalidPathError pathSoFar
    in
    getTypeAttributeByPathRec path [] tpea


{-| Get value attribute by NodePath.
Return an Error if the NodePath is invalid.
-}
getValueAttributeByPath : NodePath -> Value attr attr -> Result Error attr
getValueAttributeByPath path value =
    let
        getValueAttributeByPathRec : NodePath -> NodePath -> Value attr attr -> Result Error attr
        getValueAttributeByPathRec remainingPath pathSoFar val =
            let
                getValueFromList : List NodePathStep -> List (Value attr attr) -> Result Error attr
                getValueFromList nonEmptyPath list =
                    getFromList nonEmptyPath pathSoFar getValueAttributeByPathRec list

                getFromDefinition : Value.Definition attr attr -> NodePath -> Result Error attr
                getFromDefinition def nodePath =
                    let
                        getFromInputTypes xs =
                            case xs of
                                (ChildByIndex n) :: ys ->
                                    case ys of
                                        [ ChildByIndex 0 ] ->
                                            def.inputTypes
                                                |> List.Extra.getAt n
                                                |> Maybe.map (\( name, va, typea ) -> Ok va)
                                                |> Maybe.withDefault (returnInvalidPathError [])

                                        (ChildByIndex 1) :: zs ->
                                            def.inputTypes
                                                |> List.Extra.getAt n
                                                |> Maybe.map (\( name, va, typea ) -> getTypeAttributeByPath zs typea)
                                                |> Maybe.withDefault (returnInvalidPathError [])

                                        _ ->
                                            returnInvalidPathError []

                                _ ->
                                    returnInvalidPathError nodePath
                    in
                    case nodePath of
                        ((ChildByIndex 0) as curr) :: xs ->
                            getFromInputTypes xs

                        ((ChildByName [ "inputTypes" ]) as curr) :: xs ->
                            getFromInputTypes xs

                        ((ChildByIndex 1) as curr) :: xs ->
                            getTypeAttributeByPath xs def.outputType

                        ((ChildByName [ "outputType" ]) as curr) :: xs ->
                            getTypeAttributeByPath xs def.outputType

                        ((ChildByIndex 2) as curr) :: xs ->
                            getValueAttributeByPathRec xs (pathSoFar ++ [ curr ]) def.body

                        ((ChildByName [ "body" ]) as curr) :: xs ->
                            getValueAttributeByPathRec xs (pathSoFar ++ [ curr ]) def.body

                        _ ->
                            returnInvalidPathError nodePath
            in
            case remainingPath of
                [] ->
                    val |> Value.valueAttribute |> Ok

                nonEmptyPath ->
                    case val of
                        Value.Tuple _ list ->
                            getValueFromList nonEmptyPath list

                        Value.List _ list ->
                            getValueFromList nonEmptyPath list

                        Value.Record _ fieldDict ->
                            case nonEmptyPath of
                                ((ChildByName n) as curr) :: xs ->
                                    Dict.get n fieldDict
                                        |> Maybe.map (getValueAttributeByPathRec xs (pathSoFar ++ [ curr ]))
                                        |> Maybe.withDefault (returnInvalidPathError pathSoFar)

                                _ ->
                                    returnInvalidPathError pathSoFar

                        Value.Field _ v _ ->
                            case nonEmptyPath of
                                ((ChildByIndex 0) as curr) :: xs ->
                                    getValueAttributeByPathRec xs (pathSoFar ++ [ curr ]) v

                                _ ->
                                    returnInvalidPathError pathSoFar

                        Value.Apply _ x y ->
                            case nonEmptyPath of
                                ((ChildByIndex 0) as curr) :: xs ->
                                    getValueAttributeByPathRec xs (pathSoFar ++ [ curr ]) x

                                ((ChildByIndex 1) as curr) :: xs ->
                                    getValueAttributeByPathRec xs (pathSoFar ++ [ curr ]) y

                                _ ->
                                    returnInvalidPathError pathSoFar

                        Value.IfThenElse _ cond thenBranch elseBranch ->
                            case nonEmptyPath of
                                ((ChildByIndex 0) as curr) :: xs ->
                                    getValueAttributeByPathRec xs (pathSoFar ++ [ curr ]) cond

                                ((ChildByIndex 1) as curr) :: xs ->
                                    getValueAttributeByPathRec xs (pathSoFar ++ [ curr ]) thenBranch

                                ((ChildByIndex 2) as curr) :: xs ->
                                    getValueAttributeByPathRec xs (pathSoFar ++ [ curr ]) elseBranch

                                _ ->
                                    returnInvalidPathError pathSoFar

                        Value.Lambda _ pattern lambdaVal ->
                            case nonEmptyPath of
                                ((ChildByIndex 0) as curr) :: xs ->
                                    pattern |> Value.patternAttribute |> Ok

                                ((ChildByIndex 1) as curr) :: xs ->
                                    getValueAttributeByPathRec xs (pathSoFar ++ [ curr ]) lambdaVal

                                _ ->
                                    returnInvalidPathError pathSoFar

                        Value.LetDefinition _ _ def v ->
                            case nonEmptyPath of
                                ((ChildByIndex 0) as curr) :: xs ->
                                    getFromDefinition def xs

                                ((ChildByIndex 1) as curr) :: xs ->
                                    getValueAttributeByPathRec xs (pathSoFar ++ [ curr ]) v

                                _ ->
                                    returnInvalidPathError pathSoFar

                        Value.LetRecursion _ definitionDict v ->
                            case nonEmptyPath of
                                (ChildByIndex 0) :: (ChildByName n) :: xs ->
                                    definitionDict
                                        |> Dict.get n
                                        |> Maybe.map (\maybeDef -> getFromDefinition maybeDef xs)
                                        |> Maybe.withDefault (returnInvalidPathError pathSoFar)

                                ((ChildByIndex 1) as curr) :: xs ->
                                    getValueAttributeByPathRec xs (pathSoFar ++ [ curr ]) v

                                _ ->
                                    returnInvalidPathError pathSoFar

                        Value.Destructure _ pattern v1 v2 ->
                            case nonEmptyPath of
                                ((ChildByIndex 0) as curr) :: xs ->
                                    pattern |> Value.patternAttribute |> Ok

                                ((ChildByIndex 1) as curr) :: xs ->
                                    getValueAttributeByPathRec xs (pathSoFar ++ [ curr ]) v1

                                ((ChildByIndex 2) as curr) :: xs ->
                                    getValueAttributeByPathRec xs (pathSoFar ++ [ curr ]) v2

                                _ ->
                                    returnInvalidPathError pathSoFar

                        Value.PatternMatch _ v patternList ->
                            case nonEmptyPath of
                                ((ChildByIndex 0) as curr) :: xs ->
                                    getValueAttributeByPathRec xs (pathSoFar ++ [ curr ]) v

                                (ChildByIndex 1) :: xs ->
                                    case xs of
                                        ((ChildByIndex n) as curr2) :: ys ->
                                            List.Extra.getAt n patternList
                                                |> Maybe.map
                                                    (\maybeTuple ->
                                                        case ys of
                                                            (ChildByIndex 0) :: _ ->
                                                                maybeTuple |> Tuple.first |> Value.patternAttribute |> Ok

                                                            (ChildByIndex 1) :: zs ->
                                                                getValueAttributeByPathRec zs (List.append [ curr2, ChildByIndex 1 ] pathSoFar) (Tuple.second maybeTuple)

                                                            _ ->
                                                                returnInvalidPathError (List.append [ ChildByIndex 1, curr2 ] pathSoFar)
                                                    )
                                                |> Maybe.withDefault (returnInvalidPathError pathSoFar)

                                        _ ->
                                            returnInvalidPathError (List.append [ ChildByIndex 1 ] pathSoFar)

                                _ ->
                                    returnInvalidPathError pathSoFar

                        Value.UpdateRecord _ recordToUpdate updateDict ->
                            case nonEmptyPath of
                                ((ChildByIndex 0) as curr) :: xs ->
                                    getValueAttributeByPathRec xs (pathSoFar ++ [ curr ]) recordToUpdate

                                (ChildByIndex 1) :: xs ->
                                    case xs of
                                        ((ChildByName m) as curr) :: ys ->
                                            Dict.get m updateDict
                                                |> Maybe.map (getValueAttributeByPathRec ys (List.append [ ChildByIndex 1, curr ] pathSoFar))
                                                |> Maybe.withDefault (returnInvalidPathError pathSoFar)

                                        _ ->
                                            returnInvalidPathError (pathSoFar ++ [ ChildByIndex 1 ])

                                _ ->
                                    returnInvalidPathError pathSoFar

                        _ ->
                            returnInvalidPathError pathSoFar
    in
    getValueAttributeByPathRec path [] value
