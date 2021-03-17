module Morphir.Type.MetaType exposing (MetaType(..), Variable, boolType, charType, floatType, intType, listType, metaAlias, metaApply, metaFun, metaRecord, metaRef, metaTuple, metaUnit, metaVar, stringType, subVariable, substituteVariable, substituteVariables, toName, toString, variableByIndex, variables)

import Dict exposing (Dict)
import Morphir.IR.FQName as FQName exposing (FQName, fqn)
import Morphir.IR.Name as Name exposing (Name)
import Set exposing (Set)


type MetaType
    = MetaVar Variable
    | MetaRef FQName
    | MetaTuple (Set Variable) (List MetaType)
    | MetaRecord (Set Variable) (Maybe Variable) (Dict Name MetaType)
    | MetaApply (Set Variable) MetaType MetaType
    | MetaFun (Set Variable) MetaType MetaType
    | MetaUnit
    | MetaAlias FQName MetaType


metaVar : Variable -> MetaType
metaVar =
    MetaVar


metaRef : FQName -> MetaType
metaRef =
    MetaRef


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


metaApply : MetaType -> MetaType -> MetaType
metaApply fun arg =
    let
        vars =
            Set.union (variables fun) (variables arg)
    in
    MetaApply vars fun arg


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


metaAlias : FQName -> MetaType -> MetaType
metaAlias =
    MetaAlias


toString : MetaType -> String
toString metaType =
    case metaType of
        MetaVar ( n, i, j ) ->
            "var_" ++ n ++ "_" ++ String.fromInt i ++ "_" ++ String.fromInt j

        MetaRef fQName ->
            FQName.toString fQName

        MetaTuple _ metaTypes ->
            String.concat [ "( ", metaTypes |> List.map toString |> String.join ", ", " )" ]

        MetaRecord _ extends fields ->
            let
                prefix =
                    case extends of
                        Just ( n, i, j ) ->
                            "var_" ++ n ++ "_" ++ String.fromInt i ++ "_" ++ String.fromInt j ++ " | "

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

        MetaApply _ funType argType ->
            case argType of
                MetaApply _ _ _ ->
                    String.concat [ toString funType, " (", toString argType, ")" ]

                _ ->
                    String.concat [ toString funType, " ", toString argType ]

        MetaFun _ argType returnType ->
            String.concat [ toString argType, " -> ", toString returnType ]

        MetaUnit ->
            "()"

        MetaAlias alias targetType ->
            String.concat [ toString targetType, " as ", FQName.toString alias ]


type alias Variable =
    ( String, Int, Int )


nextVar : Variable -> Variable
nextVar ( n, i, s ) =
    ( n, i, s + 1 )


variableByIndex : Int -> Variable
variableByIndex i =
    ( "t", i, 0 )


variableByName : Name -> Variable
variableByName name =
    ( name |> Name.toCamelCase, 0, 0 )


subVariable : Variable -> Variable
subVariable ( n, i, s ) =
    ( n, i, s + 1 )


toName : Variable -> Name
toName ( n, i, s ) =
    [ n, String.fromInt i, String.fromInt s ]


variables : MetaType -> Set Variable
variables metaType =
    case metaType of
        MetaVar variable ->
            Set.singleton variable

        MetaRef _ ->
            Set.empty

        MetaTuple vars _ ->
            vars

        MetaRecord vars _ _ ->
            vars

        MetaApply vars _ _ ->
            vars

        MetaFun vars _ _ ->
            vars

        MetaUnit ->
            Set.empty

        MetaAlias _ t ->
            variables t


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

            MetaApply _ metaFunc metaArg ->
                metaApply
                    (substituteVariable var replacement metaFunc)
                    (substituteVariable var replacement metaArg)

            MetaFun _ metaFunc metaArg ->
                metaFun
                    (substituteVariable var replacement metaFunc)
                    (substituteVariable var replacement metaArg)

            MetaRef _ ->
                original

            MetaUnit ->
                original

            MetaAlias alias subject ->
                MetaAlias alias
                    (substituteVariable var replacement subject)

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
    MetaRef (fqn "Morphir.SDK" "Basics" "Bool")


charType : MetaType
charType =
    MetaRef (fqn "Morphir.SDK" "Char" "Char")


stringType : MetaType
stringType =
    MetaRef (fqn "Morphir.SDK" "String" "String")


intType : MetaType
intType =
    MetaRef (fqn "Morphir.SDK" "Basics" "Int")


floatType : MetaType
floatType =
    MetaRef (fqn "Morphir.SDK" "Basics" "Float")


listType : MetaType -> MetaType
listType itemType =
    metaApply (MetaRef (fqn "Morphir.SDK" "List" "List")) itemType
