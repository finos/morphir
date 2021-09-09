module Morphir.TypeScript.Backend exposing (mapTypeDefinition)

{-| This module contains the TypeScript backend that translates the Morphir IR into TypeScript.
-}

import Dict
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Type as Type
import Morphir.TypeScript.AST as TS


{-| Map a Morphir type definition into a list of TypeScript type definitions. The reason for returning a list is that
some Morphir type definitions can only be represented by a combination of multiple type definitions in TypeScript.
-}
mapTypeDefinition : Name -> Type.Definition ta -> List TS.TypeDef
mapTypeDefinition name typeDef =
    case typeDef of
        Type.TypeAliasDefinition typeArgs typeExp ->
            [ TS.TypeAlias
                (name |> Name.toTitleCase)
                (typeExp |> mapTypeExp)
            ]

        Type.CustomTypeDefinition typeArgs accessControlledConstructors ->
            let
                constructors =
                    accessControlledConstructors.value
                        |> Dict.toList

                constructorInterfaces =
                    constructors
                        |> List.map
                            (\( ctorName, ctorArgs ) ->
                                TS.Interface
                                    (ctorName |> Name.toTitleCase)
                                    (ctorArgs
                                        |> List.map
                                            (\( argName, argType ) ->
                                                ( argName |> Name.toCamelCase, mapTypeExp argType )
                                            )
                                    )
                            )

                union =
                    TS.TypeAlias
                        (name |> Name.toTitleCase)
                        (TS.Union
                            (constructors
                                |> List.map
                                    (\( ctorName, _ ) ->
                                        TS.TypeRef (ctorName |> Name.toTitleCase)
                                    )
                            )
                        )
            in
            constructorInterfaces ++ [ union ]


{-| Map a Morphir type expression into a TypeScript type expression.
-}
mapTypeExp : Type.Type ta -> TS.TypeExp
mapTypeExp tpe =
    case tpe of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "string" ] ], [ "string" ] ) [] ->
            TS.String

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "int" ] ) [] ->
            TS.Number

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] ->
            TS.Number

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "bool" ] ) [] ->
            TS.Boolean

        Type.Reference _ ( packageName, moduleName, localName ) [] ->
            TS.TypeRef (localName |> Name.toTitleCase)

        _ ->
            TS.Any
