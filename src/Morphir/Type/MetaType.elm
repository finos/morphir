module Morphir.Type.MetaType exposing (..)

import Dict exposing (Dict)
import Morphir.IR.FQName as FQName exposing (FQName, fqn)
import Morphir.IR.Name as Name exposing (Name)
import Set exposing (Set)


type MetaType
    = MetaVar Variable
    | MetaRef FQName
    | MetaTuple (List MetaType)
    | MetaRecord (Maybe Variable) (Dict Name MetaType)
    | MetaApply MetaType MetaType
    | MetaFun MetaType MetaType
    | MetaUnit
    | MetaAlias FQName MetaType


toString : MetaType -> String
toString metaType =
    case metaType of
        MetaVar ( n, i, j ) ->
            "var_" ++ n ++ "_" ++ String.fromInt i ++ "_" ++ String.fromInt j

        MetaRef fQName ->
            FQName.toString fQName

        MetaTuple metaTypes ->
            String.concat [ "( ", metaTypes |> List.map toString |> String.join ", ", " )" ]

        MetaRecord extends fields ->
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

        MetaApply funType argType ->
            case argType of
                MetaApply _ _ ->
                    String.concat [ toString funType, " (", toString argType, ")" ]

                _ ->
                    String.concat [ toString funType, " ", toString argType ]

        MetaFun argType returnType ->
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

        MetaRef fQName ->
            Set.empty

        MetaTuple elems ->
            elems
                |> List.foldl
                    (\t vars -> Set.union vars (variables t))
                    Set.empty

        MetaRecord maybeVar fields ->
            let
                aliasVars =
                    case maybeVar of
                        Just var ->
                            Set.singleton var

                        Nothing ->
                            Set.empty

                fieldVars =
                    fields
                        |> Dict.toList
                        |> List.foldl
                            (\( _, t ) vars -> Set.union vars (variables t))
                            Set.empty
            in
            Set.union aliasVars fieldVars

        MetaApply fun arg ->
            Set.union
                (variables fun)
                (variables arg)

        MetaFun arg return ->
            Set.union
                (variables arg)
                (variables return)

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

            MetaTuple metaElems ->
                MetaTuple
                    (metaElems
                        |> List.map (substituteVariable var replacement)
                    )

            MetaRecord extends metaFields ->
                if extends == Just var then
                    replacement

                else
                    MetaRecord extends
                        (metaFields
                            |> Dict.map
                                (\_ fieldType ->
                                    substituteVariable var replacement fieldType
                                )
                        )

            MetaApply metaFun metaArg ->
                MetaApply
                    (substituteVariable var replacement metaFun)
                    (substituteVariable var replacement metaArg)

            MetaFun metaFun metaArg ->
                MetaFun
                    (substituteVariable var replacement metaFun)
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
    MetaApply (MetaRef (fqn "Morphir.SDK" "List" "List")) itemType
