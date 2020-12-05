module Morphir.Elm.ExtractTypes exposing (FieldDef, mapDistribution)

import Dict
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type exposing (Type)


type alias FieldDef =
    { domain : String
    , name : String
    , tpe : String
    }


mapDistribution : Distribution -> List FieldDef
mapDistribution distro =
    case distro of
        Distribution.Library _ _ packageDef ->
            mapPackageDefinition packageDef


mapPackageDefinition : Package.Definition ta va -> List FieldDef
mapPackageDefinition packageDef =
    packageDef.modules
        |> Dict.toList
        |> List.concatMap
            (\( moduleName, accessControlledModuleDef ) ->
                mapModuleDefinition moduleName accessControlledModuleDef.value
            )


mapModuleDefinition : Module.ModuleName -> Module.Definition ta va -> List FieldDef
mapModuleDefinition moduleName moduleDef =
    moduleDef.types
        |> Dict.toList
        |> List.concatMap
            (\( typeName, accessControlledDocumentedTypeDef ) ->
                mapTypeDefinition moduleName typeName accessControlledDocumentedTypeDef.value.value
            )


mapTypeDefinition : Module.ModuleName -> Name -> Type.Definition ta -> List FieldDef
mapTypeDefinition moduleName typeName typeDef =
    case typeDef of
        Type.TypeAliasDefinition _ (Type.Record _ fields) ->
            fields
                |> List.map
                    (\field ->
                        FieldDef
                            (mapModuleNameAndTypeNameToDomain moduleName typeName)
                            (mapFieldName field.name)
                            (mapTypeToString field.tpe)
                    )

        _ ->
            []


mapModuleNameAndTypeNameToDomain : Module.ModuleName -> Name -> String
mapModuleNameAndTypeNameToDomain moduleName typeName =
    String.join "."
        [ moduleName
            |> Path.toString Name.toTitleCase "."
        , typeName
            |> Name.toTitleCase
        ]


mapFieldName : Name -> String
mapFieldName fieldName =
    fieldName
        |> Name.toCamelCase


mapTypeToString : Type ta -> String
mapTypeToString tpe =
    case tpe of
        Type.Reference _ (FQName _ modulePath localName) _ ->
            String.join "."
                [ modulePath
                    |> Path.toString Name.toTitleCase "."
                , localName
                    |> Name.toTitleCase
                ]

        _ ->
            "UNHANDLED"