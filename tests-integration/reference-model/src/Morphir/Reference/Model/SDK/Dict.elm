module Morphir.Reference.Model.SDK.Dict exposing (..)

import Dict exposing (Dict)


dictEmpty : Dict String String
dictEmpty =
    Dict.empty


dictSingleton : String -> String -> Dict String String
dictSingleton key value =
    Dict.singleton key value


dictIsEmpty : Dict String String -> Bool
dictIsEmpty dictionary =
    Dict.isEmpty dictionary


dictRemove : String -> Dict String String -> Dict String String
dictRemove key dict =
    Dict.remove key dict


dictMember : String -> Dict String String -> Bool
dictMember key dict =
    Dict.member key dict


dictSize : Dict String String -> Int
dictSize dict =
    Dict.size dict


dictKeys : Dict String String -> List String
dictKeys dict =
    Dict.keys dict


dictValues : Dict String String -> List String
dictValues dict =
    Dict.values dict


dictToList : Dict String String -> List ( String, String )
dictToList dict =
    Dict.toList dict


dictInsert : String -> String -> Dict String String -> Dict String String
dictInsert key value dict =
    Dict.insert key value dict


initialUsers : Dict number String
initialUsers =
    Dict.fromList [ ( 1, "John" ), ( 2, "Brad" ) ]


updatedUsers : Dict number String
updatedUsers =
    Dict.update 1 (Maybe.map (\name -> String.append name " Johnson")) initialUsers


mapUsers : Dict String String -> Dict String String
mapUsers dict =
    Dict.map (\id name -> id ++ name) dict



--dictFoldl : Dict String String -> List String
--dictFoldl dict =
--    Dict.foldl (\_ x acc -> x :: acc) [] dict
