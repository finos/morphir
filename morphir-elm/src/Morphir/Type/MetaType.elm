module Morphir.Type.MetaType exposing (MetaType(..), Variable, boolType, charType, uuidType, contains, floatType, intType, listType, metaAlias, metaClosedRecord, metaFun, metaOpenRecord, metaRecord, metaRef, metaTuple, metaUnit, metaVar, removeAliases, stringType, substituteVariable, substituteVariables, toString, variableByIndex, variableGreaterThan, variables, wrapInAliases)

import Dict exposing (Dict)
import Morphir.IR.FQName as FQName exposing (FQName, fqn)
import Morphir.IR.Name as Name exposing (Name)
import Set exposing (Set)


type MetaType
    = MetaVar Variable
    | MetaRef (Set Variable) FQName (List MetaType) (Maybe MetaType)
    | MetaTuple (Set Variable) (List MetaType)
    | MetaRecord (Set Variable) Variable Bool (Dict Name MetaType)
    | MetaFun (Set Variable) MetaType MetaType
    | MetaUnit


metaVar : Variable -> MetaType
metaVar =
    MetaVar


metaRef : FQName -> List MetaType -> MetaType
metaRef fQName args =
    let
        vars =
            args |> List.map variables |> List.foldl Set.union Set.empty
    in
    MetaRef vars fQName args Nothing


metaTuple : List MetaType -> MetaType
metaTuple elems =
    let
        vars =
            elems |> List.map variables |> List.foldl Set.union Set.empty
    in
    MetaTuple vars elems


metaRecord : Variable -> Bool -> Dict Name MetaType -> MetaType
metaRecord var isOpen fields =
    let
        vars =
            fields
                |> Dict.toList
                |> List.map (Tuple.second >> variables)
                |> List.foldl Set.union Set.empty
                |> Set.insert var
    in
    MetaRecord vars var isOpen fields


metaOpenRecord : Variable -> Dict Name MetaType -> MetaType
metaOpenRecord var fields =
    metaRecord var True fields


metaClosedRecord : Variable -> Dict Name MetaType -> MetaType
metaClosedRecord var fields =
    metaRecord var False fields


metaFun : MetaType -> MetaType -> MetaType
metaFun arg body =
    let
        vars =
            Set.union (variables arg) (variables body)
    in
    MetaFun vars arg body


metaUnit : MetaType
metaUnit =
    MetaUnit


metaAlias : FQName -> List MetaType -> MetaType -> MetaType
metaAlias fQName args tpe =
    let
        vars : Set Variable
        vars =
            args
                |> List.map variables
                |> List.foldl Set.union Set.empty
                |> Set.union (variables tpe)
    in
    case tpe of
        MetaRef _ nestedFQName nestedArgs _ ->
            if fQName == nestedFQName && nestedArgs == args then
                tpe

            else
                MetaRef vars fQName args (Just tpe)

        _ ->
            MetaRef vars fQName args (Just tpe)


wrapInAliases : List ( FQName, List MetaType ) -> MetaType -> MetaType
wrapInAliases aliases tpe =
    case aliases of
        [] ->
            tpe

        ( alias, aliasArgs ) :: restOfAliases ->
            metaAlias alias aliasArgs (wrapInAliases restOfAliases tpe)


toString : MetaType -> String
toString metaType =
    case metaType of
        MetaVar var ->
            "t" ++ (var |> String.fromInt)

        MetaRef _ fQName args maybeAliasedType ->
            let
                refString =
                    if List.isEmpty args then
                        FQName.toString fQName

                    else
                        String.join " " [ FQName.toString fQName, args |> List.map (\arg -> String.concat [ "(", toString arg, ")" ]) |> String.join " " ]
            in
            case maybeAliasedType of
                Just aliasedType ->
                    String.concat [ refString, " = ", toString aliasedType ]

                Nothing ->
                    refString

        MetaTuple _ metaTypes ->
            String.concat [ "( ", metaTypes |> List.map toString |> String.join ", ", " )" ]

        MetaRecord _ var isOpen fields ->
            let
                prefix =
                    "t"
                        ++ (var |> String.fromInt)
                        ++ (if isOpen then
                                " <= "

                            else
                                " = "
                           )

                fieldStrings =
                    fields
                        |> Dict.toList
                        |> List.map
                            (\( fieldName, fieldType ) ->
                                String.concat [ Name.toCamelCase fieldName, " : ", toString fieldType ]
                            )
            in
            String.concat [ "{ ", prefix, fieldStrings |> String.join ", ", " }" ]

        MetaFun _ argType returnType ->
            String.concat [ toString argType, " -> ", toString returnType ]

        MetaUnit ->
            "()"


type alias Variable =
    Int


variableByIndex : Int -> Variable
variableByIndex i =
    i


variableGreaterThan : Variable -> Variable -> Bool
variableGreaterThan var1 var2 =
    var1 < var2


variables : MetaType -> Set Variable
variables metaType =
    case metaType of
        MetaVar variable ->
            Set.singleton variable

        MetaRef vars _ _ _ ->
            vars

        MetaTuple vars _ ->
            vars

        MetaRecord vars _ _ _ ->
            vars

        MetaFun vars _ _ ->
            vars

        MetaUnit ->
            Set.empty


substituteVariable : Variable -> MetaType -> MetaType -> MetaType
substituteVariable var replacement original =
    if variables original |> Set.member var then
        case original of
            MetaVar thisVar ->
                if thisVar == var then
                    replacement

                else
                    original

            MetaTuple _ metaElems ->
                metaTuple
                    (metaElems
                        |> List.map (substituteVariable var replacement)
                    )

            MetaRecord _ recordVar isOpen metaFields ->
                if recordVar == var then
                    case replacement of
                        MetaVar replacementVar ->
                            metaRecord replacementVar
                                isOpen
                                (metaFields
                                    |> Dict.map
                                        (\_ fieldType ->
                                            substituteVariable var replacement fieldType
                                        )
                                )

                        _ ->
                            replacement

                else
                    metaRecord recordVar
                        isOpen
                        (metaFields
                            |> Dict.map
                                (\_ fieldType ->
                                    substituteVariable var replacement fieldType
                                )
                        )

            MetaFun _ metaFunc metaArg ->
                metaFun
                    (substituteVariable var replacement metaFunc)
                    (substituteVariable var replacement metaArg)

            MetaRef _ fQName args maybeAliasedType ->
                case maybeAliasedType of
                    Just aliasedType ->
                        metaAlias fQName
                            (args
                                |> List.map (substituteVariable var replacement)
                            )
                            (substituteVariable var replacement aliasedType)

                    Nothing ->
                        metaRef fQName
                            (args
                                |> List.map (substituteVariable var replacement)
                            )

            MetaUnit ->
                original

    else
        original


substituteVariables : Dict Variable MetaType -> MetaType -> MetaType
substituteVariables replacements original =
    if Set.isEmpty (Set.intersect (replacements |> Dict.keys |> Set.fromList) (variables original)) then
        original

    else
        case original of
            MetaVar thisVar ->
                case Dict.get thisVar replacements of
                    Just replacement ->
                        replacement

                    Nothing ->
                        original

            MetaTuple _ metaElems ->
                metaTuple
                    (metaElems
                        |> List.map (substituteVariables replacements)
                    )

            MetaRecord _ recordVar isOpen metaFields ->
                case Dict.get recordVar replacements of
                    Just replacement ->
                        case replacement of
                            MetaVar replacementVar ->
                                metaRecord replacementVar
                                    isOpen
                                    (metaFields
                                        |> Dict.map
                                            (\_ fieldType ->
                                                substituteVariables replacements fieldType
                                            )
                                    )

                            _ ->
                                replacement

                    Nothing ->
                        metaRecord recordVar
                            isOpen
                            (metaFields
                                |> Dict.map
                                    (\_ fieldType ->
                                        substituteVariables replacements fieldType
                                    )
                            )

            MetaFun _ metaFunc metaArg ->
                metaFun
                    (substituteVariables replacements metaFunc)
                    (substituteVariables replacements metaArg)

            MetaRef _ fQName args maybeAliasedType ->
                case maybeAliasedType of
                    Just aliasedType ->
                        metaAlias fQName
                            (args
                                |> List.map (substituteVariables replacements)
                            )
                            (substituteVariables replacements aliasedType)

                    Nothing ->
                        metaRef fQName
                            (args
                                |> List.map (substituteVariables replacements)
                            )

            MetaUnit ->
                original


boolType : MetaType
boolType =
    metaRef (fqn "Morphir.SDK" "Basics" "Bool") []


charType : MetaType
charType =
    metaRef (fqn "Morphir.SDK" "Char" "Char") []


stringType : MetaType
stringType =
    metaRef (fqn "Morphir.SDK" "String" "String") []


intType : MetaType
intType =
    metaRef (fqn "Morphir.SDK" "Basics" "Int") []


floatType : MetaType
floatType =
    metaRef (fqn "Morphir.SDK" "Basics" "Float") []

uuidType : MetaType
uuidType =
    metaRef (fqn "Morphir.SDK" "UUID" "UUID") []


listType : MetaType -> MetaType
listType itemType =
    metaRef (fqn "Morphir.SDK" "List" "List") [ itemType ]


contains : MetaType -> MetaType -> Bool
contains innerType outerType =
    if innerType == outerType then
        True

    else
        case outerType of
            MetaVar _ ->
                False

            MetaTuple _ metaElems ->
                metaElems
                    |> List.any (contains innerType)

            MetaRecord _ _ _ metaFields ->
                metaFields
                    |> Dict.values
                    |> List.any (contains innerType)

            MetaFun _ metaFunc metaArg ->
                contains innerType metaFunc || contains innerType metaArg

            MetaRef _ _ args maybeAliasedType ->
                case maybeAliasedType of
                    Just aliasedType ->
                        args
                            |> List.any (contains innerType)
                            |> (||) (contains innerType aliasedType)

                    Nothing ->
                        args
                            |> List.any (contains innerType)

            MetaUnit ->
                False


removeAliases : MetaType -> MetaType
removeAliases original =
    case original of
        MetaVar _ ->
            original

        MetaTuple _ metaElems ->
            metaTuple
                (metaElems
                    |> List.map removeAliases
                )

        MetaRecord _ recordVar isOpen metaFields ->
            metaRecord recordVar
                isOpen
                (metaFields
                    |> Dict.map
                        (\_ fieldType ->
                            removeAliases fieldType
                        )
                )

        MetaFun _ metaFunc metaArg ->
            metaFun
                (removeAliases metaFunc)
                (removeAliases metaArg)

        MetaRef _ fQName args maybeAliasedType ->
            case maybeAliasedType of
                Just aliasedType ->
                    removeAliases aliasedType

                Nothing ->
                    metaRef fQName
                        (args
                            |> List.map removeAliases
                        )

        MetaUnit ->
            original
