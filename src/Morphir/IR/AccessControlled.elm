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


module Morphir.IR.AccessControlled exposing
    ( AccessControlled, Access(..)
    , public, private
    , withPublicAccess, withPrivateAccess, withAccess
    , map
    )

{-| Module to manage access to a node in the IR. This is only used to declare access levels
not to enforce them. Enforcement can be done through the helper functions
[withPublicAccess](#withPublicAccess) and [withPrivateAccess](#withPrivateAccess) but it's
up to the consumer of the API to call the right function.

@docs AccessControlled, Access


# Creation

@docs public, private


# Query

@docs withPublicAccess, withPrivateAccess, withAccess


# Transform

@docs map

-}


{-| Type that represents different access levels.
-}
type alias AccessControlled a =
    { access : Access
    , value : a
    }


{-| Public or private access.
-}
type Access
    = Public
    | Private


{-| Mark a node as public access. Actors with both public and private access are allowed to see.
-}
public : a -> AccessControlled a
public value =
    AccessControlled Public value


{-| Mark a node as private access. Only actors with private access level can see.
-}
private : a -> AccessControlled a
private value =
    AccessControlled Private value


{-| Get the value with public access level. Will return `Nothing` if the value is private.

    withPublicAccess (public 13) -- Just 13

    withPublicAccess (private 13) -- Nothing

-}
withPublicAccess : AccessControlled a -> Maybe a
withPublicAccess ac =
    case ac.access of
        Public ->
            Just ac.value

        Private ->
            Nothing


{-| Get the value with private access level. Will always return the value.

    withPrivateAccess (public 13) -- 13

    withPrivateAccess (private 13) -- 13

-}
withPrivateAccess : AccessControlled a -> a
withPrivateAccess ac =
    case ac.access of
        Public ->
            ac.value

        Private ->
            ac.value


{-| Get the value with public or private access level. Will return `Nothing` if the value is private and accessed using
public access.

    withAccess Public (public 13) -- Just 13

    withAccess Public (private 13) -- Nothing

    withAccess Private (public 13) -- 13

    withAccess Private (private 13) -- 13

-}
withAccess : Access -> AccessControlled a -> Maybe a
withAccess access ac =
    case access of
        Public ->
            withPublicAccess ac

        Private ->
            Just (withPrivateAccess ac)


{-| Apply a function to the access controlled value but keep the access unchanged.
-}
map : (a -> b) -> AccessControlled a -> AccessControlled b
map f ac =
    AccessControlled ac.access (f ac.value)
