module Morphir.Elm.IncrementalResolve.Codec exposing (..)

import Json.Encode as Encode exposing (list, string)
import Morphir.Elm.IncrementalResolve exposing (Error(..), KindOfName(..))
import Morphir.IR.Module exposing (QualifiedModuleName)


encodeKindOfName : KindOfName -> Encode.Value
encodeKindOfName kindOfName =
    case kindOfName of
        Type ->
            string "Type"

        Constructor ->
            string "Constructor"

        Value ->
            string "Value"


encodeQualifiedModuleName : QualifiedModuleName -> Encode.Value
encodeQualifiedModuleName ( packageName, moduleName ) =
    list identity
        [ list (list string) packageName
        , list (list string) moduleName
        ]


encodeError : Error -> Encode.Value
encodeError error =
    case error of
        NoMorphirPackageFoundForElmModule strings ->
            list identity
                [ string "NoMorphirPackageFoundForElmModule"
                , list string strings
                ]

        ModuleNotImported strings ->
            list identity
                [ string "ModuleNotImported"
                , list string strings
                ]

        ModuleOrAliasNotImported str ->
            list identity
                [ string "ModuleOrAliasNotImported"
                , string str
                ]

        ModuleDoesNotExposeLocalName packageName moduleName name kindOfName ->
            list identity
                [ string "ModuleDoesNotExposeLocalName"
                , list (list string) packageName
                , list (list string) moduleName
                , list string name
                , encodeKindOfName kindOfName
                ]

        ModulesDoNotExposeLocalName modName importedModsQName localName kindOfName ->
            list identity
                [ string "ModulesDoNotExposeLocalName"
                , string modName
                , list encodeQualifiedModuleName importedModsQName
                , list string localName
                , encodeKindOfName kindOfName
                ]

        MultipleModulesExposeLocalName importedModsQName name kindOfName ->
            list identity
                [ string "MultipleModulesExposeLocalName"
                , list encodeQualifiedModuleName importedModsQName
                , list string name
                , encodeKindOfName kindOfName
                ]

        LocalNameNotImported name kindOfName ->
            list identity
                [ string "LocalNameNotImported"
                , list string name
                , encodeKindOfName kindOfName
                ]

        ImportedModuleNotFound qualifiedModuleName ->
            list identity
                [ string "ImportedModuleNotFound"
                , encodeQualifiedModuleName qualifiedModuleName
                ]

        ImportedLocalNameNotFound qualifiedModuleName name kindOfName ->
            list identity
                [ string "ImportedLocalNameNotFound"
                , encodeQualifiedModuleName qualifiedModuleName
                , list string name
                , encodeKindOfName kindOfName
                ]

        ImportingConstructorsOfNonCustomType qualifiedModuleName name ->
            list identity
                [ encodeQualifiedModuleName qualifiedModuleName
                , list string name
                ]
