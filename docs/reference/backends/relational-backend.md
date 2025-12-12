---
id: relational-backend
title: Relational Backend
---

# Relational Backend Documentation

## Joins

The purpose of joins is to look up extra information for each record in some relation and then use it to enrich or 
filter the original relation. While their semantics fit into relational algebra directly as a single operation they 
usually translate into a combination of multiple operations in the functional programming model. 

1. What data are we looking up
2. How it's applied to the output

### Look up optional value

```sql
SELECT 
    request.product_id as product_id, 
    inventory.available_units as available_units 
FROM Requests as request
LEFT JOIN Inventory as inventory
    ON inventory.product_id = request.product_id 
```


```elm
type alias Request =
    { productID : String
    }

type alias Inventory =
    { productID : String
    , availableUnits : Int 
    } 

type alias Availability =
    { productID : String
    , availableUnits : Maybe Int
    }

checkAvailability : List Request -> Dict String Inventory -> List Availability 
checkAvailability requests inventory =
    requests
        |> List.map
            (\request ->
                { productID = request.productID
                , availableUnits = 
                    inventory 
                        |> Dict.get request.productID
                        |> Maybe.map .availableUnits
                } 
            )
```

### Look up optional value with default

```elm
type alias Request =
    { productID : String
    }

type alias Availability =
    { productID : String
    , availableUnits : Int
    }

checkAvailability : List Request -> Dict String Int -> List Availability 
checkAvailability requests inventory =
    requests
        |> List.map
            (\request ->
                { productID = request.productID
                , availableUnits = 
                    inventory 
                        |> Dict.get request.productID
                        |> Dict.withDefault 0
                } 
            )
```
### Look up required value

```elm
type alias Request =
    { productID : String
    }

type alias Availability =
    { productID : String
    , availableUnits : Int
    }

checkAvailability : List Request -> Dict String Int -> List Availability 
checkAvailability requests inventory =
    requests
        |> List.map
            (\request ->
                { productID = request.productID
                , availableUnits = 
                    inventory 
                        |> Dict.get request.productID
                        |> required
                } 
            )
```

### Filter on missing value

```elm
type alias Request =
    { productID : String
    }

type alias Availability =
    { productID : String
    , availableUnits : Int
    }

checkAvailability : List Request -> Dict String Int -> List Availability 
checkAvailability requests inventory =
    requests
        |> List.filterMap
            (\request ->
                inventory 
                    |> Dict.get request.productID
                    |> Maybe.map 
                        (\available ->
                            { productID = request.productID
                            , availableUnits = available
                            } 
                        )               
            )
```


