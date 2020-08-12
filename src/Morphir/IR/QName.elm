{-
Copyright 2020 Morgan Stanley

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-}


module Morphir.IR.QName exposing
    ( QName(..), toTuple, getModulePath, getLocalName
    , fromName, fromTuple
    , toString
    )

{-| Module to work with qualified names. A qualified name is a combination of a module path and a local name.

@docs QName, toTuple, getModulePath, getLocalName


# Creation

@docs fromName, fromTuple


# String conversion

@docs toString

-}

import Morphir.IR.Name exposing (Name)
import Morphir.IR.Path as Path exposing (Path)


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
fromName : Path -> Name -> QName
fromName modulePath localName =
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
