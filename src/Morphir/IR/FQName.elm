module Morphir.IR.FQName exposing
    ( FQName(..), fQName, fromQName, getPackagePath, getModulePath, getLocalName
    , fuzzFQName
    , encodeFQName, decodeFQName
    )

{-| Module to work with fully-qualified names. A qualified name is a combination of a package path, a module path and a local name.

@docs FQName, fQName, fromQName, getPackagePath, getModulePath, getLocalName


# Property Testing

@docs fuzzFQName


# Serialization

@docs encodeFQName, decodeFQName

-}

import Fuzz exposing (Fuzzer)
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.Name exposing (Name, decodeName, encodeName, fuzzName)
import Morphir.IR.Path exposing (Path, decodePath, encodePath, fuzzPath)
import Morphir.IR.QName as QName exposing (QName)


{-| Type that represents a fully-qualified name.
-}
type FQName
    = FQName Path Path Name


{-| Create a fully-qualified name.
-}
fQName : Path -> Path -> Name -> FQName
fQName packagePath modulePath localName =
    FQName packagePath modulePath localName


{-| Create a fully-qualified from a qualified name.
-}
fromQName : Path -> QName -> FQName
fromQName packagePath qName =
    FQName packagePath (qName |> QName.getModulePath) (qName |> QName.getLocalName)


{-| Get the package path part of a fully-qualified name.
-}
getPackagePath : FQName -> Path
getPackagePath (FQName p _ _) =
    p


{-| Get the module path part of a fully-qualified name.
-}
getModulePath : FQName -> Path
getModulePath (FQName _ m _) =
    m


{-| Get the local name part of a fully-qualified name.
-}
getLocalName : FQName -> Name
getLocalName (FQName _ _ l) =
    l


{-| FQName fuzzer.
-}
fuzzFQName : Fuzzer FQName
fuzzFQName =
    Fuzz.map3 FQName
        fuzzPath
        fuzzPath
        fuzzName


{-| Encode a fully-qualified name to JSON.
-}
encodeFQName : FQName -> Encode.Value
encodeFQName (FQName packagePath modulePath localName) =
    Encode.list identity
        [ packagePath |> encodePath
        , modulePath |> encodePath
        , localName |> encodeName
        ]


{-| Decode a fully-qualified name from JSON.
-}
decodeFQName : Decode.Decoder FQName
decodeFQName =
    Decode.map3 FQName
        (Decode.index 0 decodePath)
        (Decode.index 1 decodePath)
        (Decode.index 2 decodeName)
