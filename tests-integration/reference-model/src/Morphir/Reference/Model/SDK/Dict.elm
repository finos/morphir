module Morphir.Reference.Model.SDK.Dict exposing (..)

import Dict exposing (Dict)


dictEmpty : Dict k v
dictEmpty =
    Dict.empty


dictSingleton : comparable -> b -> Dict comparable b
dictSingleton key value =
    Dict.singleton key value


dictIsEmpty : Dict k v -> Bool
dictIsEmpty dictionary =
    Dict.isEmpty dictionary


dictRemove : comparable -> Dict comparable v -> Dict comparable v
dictRemove key dict =
    Dict.remove key dict


dictMember : comparable -> Dict comparable v -> Bool
dictMember key dict =
    Dict.member key dict


dictSize : Dict k v -> Int
dictSize dict =
    Dict.size dict


dictKeys : Dict k v -> List k
dictKeys dict =
    Dict.keys dict


dictValues : Dict k v -> List v
dictValues dict =
    Dict.values dict


dictToList : Dict k v -> List ( k, v )
dictToList dict =
    Dict.toList dict


dictInsert : comparable -> b -> Dict comparable b -> Dict comparable b
dictInsert key value dict =
    Dict.insert key value dict


initialUsers : Dict number String
initialUsers =
    Dict.fromList [ ( 1, "John" ), ( 2, "Brad" ) ]


updatedUsers : Dict number String
updatedUsers =
    Dict.update 1 (Maybe.map (\name -> String.append name " Johnson")) initialUsers
