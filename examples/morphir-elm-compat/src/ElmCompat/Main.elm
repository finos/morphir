module ElmCompat.Main exposing
    ( Product
    , ProductId
    , Quantity
    , CustomerOrder
    , OrderStatus(..)
    , calculateTotal
    , applyDiscount
    , isValidOrder
    , orderStatusToString
    )

{-| Main module demonstrating Morphir-compatible Elm types and functions.

This module provides a simple e-commerce domain model for testing
the morphir-elm toolchain integration.

-}


{-| A unique identifier for products.
-}
type alias ProductId =
    String


{-| Represents a quantity of items.
-}
type alias Quantity =
    Int


{-| A product with price information.
-}
type alias Product =
    { id : ProductId
    , name : String
    , price : Float
    }


{-| Possible states of an order.
-}
type OrderStatus
    = Pending
    | Confirmed
    | Shipped
    | Delivered
    | Cancelled


{-| A customer order containing products and quantities.
-}
type alias CustomerOrder =
    { orderId : String
    , products : List ( Product, Quantity )
    , status : OrderStatus
    }


{-| Calculate the total price of an order.

    calculateTotal { orderId = "1", products = [ ( product, 2 ) ], status = Pending }

-}
calculateTotal : CustomerOrder -> Float
calculateTotal order =
    order.products
        |> List.map (\( product, qty ) -> product.price * toFloat qty)
        |> List.sum


{-| Apply a percentage discount to a price.

    applyDiscount 10 100.0 == 90.0

-}
applyDiscount : Float -> Float -> Float
applyDiscount discountPercent originalPrice =
    let
        discount =
            originalPrice * (discountPercent / 100)
    in
    originalPrice - discount


{-| Check if an order is valid (has at least one product with positive quantity).
-}
isValidOrder : CustomerOrder -> Bool
isValidOrder order =
    case order.products of
        [] ->
            False

        _ ->
            List.all (\( _, qty ) -> qty > 0) order.products


{-| Convert an order status to a human-readable string.
-}
orderStatusToString : OrderStatus -> String
orderStatusToString status =
    case status of
        Pending ->
            "Pending"

        Confirmed ->
            "Confirmed"

        Shipped ->
            "Shipped"

        Delivered ->
            "Delivered"

        Cancelled ->
            "Cancelled"
