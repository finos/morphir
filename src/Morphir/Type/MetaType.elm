module Morphir.Type.MetaType exposing (MetaType(..), Variable, boolType, charType, floatType, intType, isNamedVariable, listType, metaAlias, metaFun, metaRecord, metaRef, metaTuple, metaUnit, metaVar, stringType, subVariable, substituteVariable, substituteVariables, toName, toString, variableByIndex, variableByName, variables, wrapInAliases)

import Dict exposing (Dict)
import Morphir.IR.FQName as FQName exposing (FQName, fqn)
import Morphir.IR.Name as Name exposing (Name)
import Set exposing (Set)


type MetaType
    = MetaVar Variable
    | MetaRef (Set Variable) FQName (List MetaType) (Maybe MetaType)
    | MetaTuple (Set Variable) (List MetaType)
    | MetaRecord (Set Variable) (Maybe Variable) (Dict Name MetaType)
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


metaRecord : Maybe Variable -> Dict Name MetaType -> MetaType
metaRecord extends fields =
    let
        fieldVars =
            fields
                |> Dict.toList
                |> List.map (Tuple.second >> variables)
                |> List.foldl Set.union Set.empty

        vars =
            extends
                |> Maybe.map (\eVar -> fieldVars |> Set.insert eVar)
                |> Maybe.withDefault fieldVars
    in
    MetaRecord vars extends fields


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
        vars =
            args
                |> List.map variables
                |> List.foldl Set.union Set.empty
                |> Set.union (variables tpe)
    in
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
            "var_" ++ (toName var |> Name.toSnakeCase)

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

        MetaRecord _ extends fields ->
            let
                prefix =
                    case extends of
                        Just var ->
                            "var_" ++ (toName var |> Name.toSnakeCase)

                        Nothing ->
                            ""

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
    ( Name, Int, Int )


nextVar : Variable -> Variable
nextVar ( n, i, s ) =
    ( n, i, s + 1 )


variableByIndex : Int -> Variable
variableByIndex i =
    ( [], i, 0 )


variableByName : Name -> Variable
variableByName name =
    ( name, 0, 0 )


isNamedVariable : Variable -> Bool
isNamedVariable ( name, _, _ ) =
    not (List.isEmpty name)


subVariable : Variable -> Variable
subVariable ( n, i, s ) =
    ( n, i, s + 1 )


toName : Variable -> Name
toName ( n, i, s ) =
    if List.isEmpty n then
        [ "t", String.fromInt i, String.fromInt s ]

    else if i > 0 || s > 0 then
        n ++ [ String.fromInt i, String.fromInt s ]

    else
        n


variables : MetaType -> Set Variable
variables metaType =
    case metaType of
        MetaVar variable ->
            Set.singleton variable

        MetaRef vars _ _ _ ->
            vars

        MetaTuple vars _ ->
            vars

        MetaRecord vars _ _ ->
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

            MetaRecord _ extends metaFields ->
                if extends == Just var then
                    replacement

                else
                    metaRecord extends
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


substituteVariables : List ( Variable, MetaType ) -> MetaType -> MetaType
substituteVariables replacements original =
    replacements
        |> List.foldl
            (\( var, replacement ) soFar ->
                soFar
                    |> substituteVariable var replacement
            )
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


listType : MetaType -> MetaType
listType itemType =
    metaRef (fqn "Morphir.SDK" "List" "List") [ itemType ]
