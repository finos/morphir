module Morphir.JsonSchema.Utils exposing (..)

import Dict
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path exposing (Path)
import Morphir.IR.Type as Type exposing (Type)


type alias QualifiedName =
    ( Path, Name )


extractTypes : ModuleName -> Module.Definition () (Type ()) -> List ( QualifiedName, Type.Definition () )
extractTypes modName definition =
    definition.types
        |> Dict.toList
        |> List.map
            (\( name, accessControlled ) ->
                ( ( modName, name ), accessControlled.value.value )
            )


getTypeDefinitionFromModule : Name -> ModuleName -> Maybe (Module.Definition () (Type ())) -> List (Type.Definition ())
getTypeDefinitionFromModule typeName _ moduleDef =
    case moduleDef of
        Just moduleDefn ->
            moduleDefn.types
                |> Dict.toList
                |> List.filterMap
                    (\( name, accControlled ) ->
                        case accControlled.value.value of
                            Type.TypeAliasDefinition _ _ ->
                                let
                                    typName =
                                        [ typeName |> Name.toTitleCase |> String.toLower ]
                                in
                                if typName == name then
                                    Just accControlled.value.value

                                else
                                    Nothing

                            Type.CustomTypeDefinition _ _ ->
                                if typeName == name then
                                    Just accControlled.value.value

                                else
                                    Nothing
                    )

        Nothing ->
            []


isTypeOrModule : String -> StringType
isTypeOrModule val =
    let
        words =
            val
                |> String.split ":"
                |> List.length
    in
    if words == 3 then
        TypeNameString

    else if words == 2 then
        ModuleNameString

    else
        UnknownString


type StringType
    = TypeNameString
    | ModuleNameString
    | UnknownString
