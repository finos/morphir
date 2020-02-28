module Morphir.IR.QName exposing
    ( QName, fromTuple, toTuple, qName, getModulePath, getLocalName
    , toString
    , fuzzQName
    , encodeQName, decodeQName
    )

{-| Module to work with qualified names. A qualified name is a combination of a module path and a local name.

@docs QName, fromTuple, toTuple, qName, getModulePath, getLocalName


# String conversion

@docs toString


# Property Testing

@docs fuzzQName


# Serialization

@docs encodeQName, decodeQName

-}

import Fuzz exposing (Fuzzer)
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.Name exposing (Name, decodeName, encodeName, fuzzName)
import Morphir.IR.Path as Path exposing (Path, decodePath, encodePath, fuzzPath)


{-| Type that represents a qualified name.
-}
type QName
    = QName Path Name


{-| Turn a qualified name into a tuple.
-}
toTuple : QName -> ( Path, Name )
toTuple (QName m l) =
    ( m, l )


{-| Turn a tuple into a qualified name.
-}
fromTuple : ( Path, Name ) -> QName
fromTuple ( m, l ) =
    QName m l


{-| Creates a qualified name.
-}
qName : Path -> Name -> QName
qName modulePath localName =
    QName modulePath localName


{-| Get the module path part of a qualified name.
-}
getModulePath : QName -> Path
getModulePath (QName modulePath _) =
    modulePath


{-| Get the local name part of a qualified name.
-}
getLocalName : QName -> Name
getLocalName (QName _ localName) =
    localName


{-| Turn a qualified name into a string using the specified
path and name conventions.

    qname =
        QName.fromTuple
            (Path.fromList
                [ Name.fromList [ "foo", "bar" ]
                , Name.fromList [ "baz" ]
                ]
            , Name.fromList [ "a", "name" ]
            )

    toString Name.toTitleCase Name.toCamelCase "." qname
    --> "FooBar.Baz.aName"

    toString Name.toSnakeCase Name.toSnakeCase "/" qname
    --> "foo_bar/baz/a_name"

-}
toString : (Name -> String) -> (Name -> String) -> String -> QName -> String
toString pathPartToString nameToString sep (QName mPath lName) =
    mPath
        |> Path.toList
        |> List.map pathPartToString
        |> List.append [ nameToString lName ]
        |> String.join sep


{-| QName fuzzer.
-}
fuzzQName : Fuzzer QName
fuzzQName =
    Fuzz.map2 QName
        fuzzPath
        fuzzName


{-| Encode a qualified name to JSON.
-}
encodeQName : QName -> Encode.Value
encodeQName (QName modulePath localName) =
    Encode.list identity
        [ modulePath |> encodePath
        , localName |> encodeName
        ]


{-| Decode a qualified name from JSON.
-}
decodeQName : Decode.Decoder QName
decodeQName =
    Decode.map2 QName
        (Decode.index 0 decodePath)
        (Decode.index 1 decodeName)
