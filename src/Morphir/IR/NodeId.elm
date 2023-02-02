module Morphir.IR.NodeId exposing (..)

import Dict
import List.Extra
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Name as Name exposing (Name)
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


type NodePathStep
    = ChildByName Name
    | ChildByIndex Int
    | ChildByPart String


type NodeID
    = TypeID FQName NodePath
    | ValueID FQName NodePath
    | ModuleID (Path, Path)


type Error
    = InvalidPath String
    | InvalidNodeID String


nodeIdFromString : String -> Result Error NodeID
nodeIdFromString str =
    let
        returnError =
            Err <| InvalidNodeID ("Invalid NodeID: " ++ str)

        mapToTypeOrValue : String -> String -> String -> String -> String -> Result Error NodeID
        mapToTypeOrValue typeOrValue packageName moduleName localName nodePath =
            case typeOrValue of
                "values" ->
                    Ok (ValueID (FQName.fqn packageName moduleName localName) (nodePathFromString nodePath))

                "types" ->
                    Ok (TypeID (FQName.fqn packageName moduleName localName) (nodePathFromString nodePath))

                _ ->
                    returnError
    in
    case String.split ":" str of
        [ nodeKind, packageName, moduleName, localName ] ->
            if String.contains "#" localName then
                case String.split "#" localName of
                    [ defName, path ] ->
                        mapToTypeOrValue nodeKind packageName moduleName defName path

                    _ ->
                        returnError

            else
                mapToTypeOrValue nodeKind packageName moduleName localName ""

        [ _, packageName, moduleName ] ->
            Ok (ModuleID ( [ packageName |> Name.fromString ], [ moduleName |> Name.fromString ]))

        _ ->
            returnError


nodeIdToString : NodeID -> String
nodeIdToString nodeId =
    let
        mapToTypeOrValue typeOrValue packageName moduleName localName nodePath =
            if List.isEmpty nodePath then
                String.join ":"
                    [ typeOrValue
                    , Path.toString Name.toTitleCase "." packageName
                    , Path.toString Name.toTitleCase "." moduleName
                    , Name.toCamelCase localName
                    ]
            else
                (String.join ":"
                    [ typeOrValue
                    , Path.toString Name.toTitleCase "." packageName
                    , Path.toString Name.toTitleCase "." moduleName
                    , Name.toCamelCase localName
                    ])
                    ++ nodePathToString nodePath

    in
    case nodeId of
        TypeID (packageName, moduleName, localName) nodePath ->
            mapToTypeOrValue "types" packageName moduleName localName nodePath

        ValueID (packageName, moduleName, localName) nodePath ->
            mapToTypeOrValue "values" packageName moduleName localName nodePath

        ModuleID ( packageName, moduleName) ->
            String.join ":"
                [ Path.toString Name.toTitleCase "." packageName
                , Path.toString Name.toTitleCase "." moduleName
                ]


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


returnInvalidPathError : NodePath -> Result Error value
returnInvalidPathError pathSoFar =
    case nodePathToString pathSoFar of
        "" ->
            Err <| InvalidPath ("Path is invalid")
        _ ->
            Err <| InvalidPath ("Path is invalid after " ++ nodePathToString pathSoFar)


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

getValueAttributeByPath : NodePath -> Value attr attr -> Result Error attr
getValueAttributeByPath path value =
    let
        getValueAttributeByPathRec : NodePath -> NodePath -> Value attr attr -> Result Error attr
        getValueAttributeByPathRec remainingPath pathSoFar val =
            let
                getValueFromList : List NodePathStep -> List (Value attr attr) -> Result Error attr
                getValueFromList nonEmptyPath list =
                    getFromList nonEmptyPath pathSoFar getValueAttributeByPathRec list

                getFromDefinition def nodePath =
                    let
                        getFromInputTypes xs =
                            case xs of
                                ChildByIndex n :: ys ->
                                    case ys of
                                        [ChildByIndex 0] ->
                                            def.inputTypes 
                                            |> List.Extra.getAt n
                                            |> Maybe.map (\(name, va, typea) -> Ok va)
                                            |> Maybe.withDefault (returnInvalidPathError [])

                                        ChildByIndex 1 :: zs ->
                                            def.inputTypes 
                                            |> List.Extra.getAt n
                                            |> Maybe.map (\(name, va, typea) -> getTypeAttributeByPath zs typea)
                                            |> Maybe.withDefault (returnInvalidPathError [])

                                        _ ->
                                            returnInvalidPathError []

                                _ ->
                                    returnInvalidPathError nodePath
                    in
                    case nodePath of
                        ((ChildByIndex 0) as curr) :: xs ->
                            getFromInputTypes xs

                        ((ChildByName ["inputTypes"]) as curr) :: xs ->
                            getFromInputTypes xs

                        ((ChildByIndex 1) as curr) :: xs ->
                            getTypeAttributeByPath xs def.outputType

                        ((ChildByName ["outputType"]) as curr) :: xs ->
                            getTypeAttributeByPath xs def.outputType

                        ((ChildByIndex 2) as curr) :: xs ->
                            getValueAttributeByPathRec xs (List.append [ curr ] pathSoFar) def.body

                        ((ChildByName ["body"]) as curr) :: xs ->
                            getValueAttributeByPathRec xs (List.append [ curr ] pathSoFar) def.body

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
                                        |> Maybe.map (getValueAttributeByPathRec xs (List.append [ curr ] pathSoFar))
                                        |> Maybe.withDefault (returnInvalidPathError pathSoFar)

                                _ ->
                                    returnInvalidPathError pathSoFar

                        Value.Field _ v _ ->
                            case nonEmptyPath of
                                ((ChildByIndex 0) as curr) :: xs ->
                                    getValueAttributeByPathRec xs (List.append [ curr ] pathSoFar) v
                                _ ->
                                    returnInvalidPathError pathSoFar

                        Value.Apply _ x y ->
                            case nonEmptyPath of
                                ((ChildByIndex 0) as curr) :: xs ->
                                    getValueAttributeByPathRec xs (List.append [ curr ] pathSoFar) x

                                ((ChildByIndex 1) as curr) :: xs ->
                                    getValueAttributeByPathRec xs (List.append [ curr ] pathSoFar) y

                                _ ->
                                    returnInvalidPathError pathSoFar

                        Value.IfThenElse _ cond thenBranch elseBranch ->
                            case nonEmptyPath of
                                ((ChildByIndex 0) as curr) :: xs ->
                                    getValueAttributeByPathRec xs (List.append [ curr ] pathSoFar) cond

                                ((ChildByIndex 1) as curr) :: xs ->
                                    getValueAttributeByPathRec xs (List.append [ curr ] pathSoFar) thenBranch

                                ((ChildByIndex 2) as curr) :: xs ->
                                    getValueAttributeByPathRec xs (List.append [ curr ] pathSoFar) elseBranch

                                _ ->
                                    returnInvalidPathError pathSoFar

                        Value.Lambda _ pattern lambdaVal ->
                            case nonEmptyPath of
                                ((ChildByIndex 0) as curr) :: xs ->
                                    pattern |> Value.patternAttribute |> Ok

                                ((ChildByIndex 1) as curr) :: xs ->
                                    getValueAttributeByPathRec xs (List.append [ curr ] pathSoFar) lambdaVal

                                _ ->
                                    returnInvalidPathError pathSoFar

                        Value.LetDefinition _ _ def v ->
                            case nonEmptyPath of
                                ((ChildByIndex 0) as curr) :: xs ->
                                    getFromDefinition def xs

                                ((ChildByIndex 1) as curr) :: xs ->
                                    getValueAttributeByPathRec xs (List.append [ curr ] pathSoFar) v

                                _ ->
                                    returnInvalidPathError pathSoFar

                        Value.LetRecursion _ definitionDict v ->
                            case nonEmptyPath of
                                (ChildByIndex 0) :: ChildByName n :: xs ->
                                    definitionDict
                                    |> Dict.get n
                                    |> Maybe.map (\maybeDef -> getFromDefinition maybeDef xs)
                                    |> Maybe.withDefault (returnInvalidPathError pathSoFar)

                                ((ChildByIndex 1) as curr) :: xs ->
                                    getValueAttributeByPathRec xs (List.append [ curr ] pathSoFar) v

                                _ ->
                                    returnInvalidPathError pathSoFar

                        Value.Destructure _ pattern v1 v2 ->
                            case nonEmptyPath of
                                ((ChildByIndex 0) as curr) :: xs ->
                                    pattern |> Value.patternAttribute |> Ok

                                ((ChildByIndex 1) as curr) :: xs ->
                                    getValueAttributeByPathRec xs (List.append [ curr ] pathSoFar) v1

                                ((ChildByIndex 2) as curr) :: xs ->
                                    getValueAttributeByPathRec xs (List.append [ curr ] pathSoFar) v2

                                _ ->
                                    returnInvalidPathError pathSoFar

                        Value.PatternMatch _ v patternList ->
                            case nonEmptyPath of
                                ((ChildByIndex 0) as curr) :: xs ->
                                    getValueAttributeByPathRec xs (List.append [ curr ] pathSoFar) v

                                ChildByIndex 1 :: xs ->
                                    case xs of
                                        ((ChildByIndex n) as curr2) :: ys ->
                                            List.Extra.getAt n patternList
                                            |> Maybe.map (\maybeTuple ->
                                                case ys of
                                                    ChildByIndex 1 :: _ ->
                                                        maybeTuple |> Tuple.first |> Value.patternAttribute |> Ok
                                                    ChildByIndex 2 :: zs ->
                                                        getValueAttributeByPathRec zs (List.append [ curr2, ChildByIndex 2 ] pathSoFar) (Tuple.second maybeTuple)
                                                    _ ->
                                                        returnInvalidPathError (List.append [ ChildByIndex 1, curr2 ] pathSoFar)
                                                    )
                                            |> Maybe.withDefault (returnInvalidPathError pathSoFar)
                                        _ ->
                                            returnInvalidPathError (List.append [ ChildByIndex 1 ] pathSoFar)

                                _ ->
                                    returnInvalidPathError pathSoFar


                        _ ->
                            returnInvalidPathError pathSoFar
    in
    getValueAttributeByPathRec path [] value