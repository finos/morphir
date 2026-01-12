module ElmCompat.Api exposing
    ( Request
    , Response
    , ApiError(..)
    , createOrder
    , getOrderStatus
    , processRequest
    )

{-| API module demonstrating request/response patterns.

This module provides types and functions for a simple API layer,
demonstrating how Morphir handles common API patterns.

-}

import ElmCompat.Main exposing (CustomerOrder, OrderStatus(..), Product, Quantity)


{-| Represents an API request to create or modify an order.
-}
type alias Request =
    { action : String
    , orderId : Maybe String
    , products : List ( Product, Quantity )
    }


{-| Represents an API response.
-}
type alias Response =
    { success : Bool
    , message : String
    , orderId : Maybe String
    }


{-| Possible API errors.
-}
type ApiError
    = InvalidRequest String
    | OrderNotFound String
    | InternalError


{-| Create a new order from a list of products.
-}
createOrder : String -> List ( Product, Quantity ) -> CustomerOrder
createOrder orderId products =
    { orderId = orderId
    , products = products
    , status = Pending
    }


{-| Get the status of an order as a string response.
-}
getOrderStatus : CustomerOrder -> Response
getOrderStatus order =
    let
        statusStr =
            case order.status of
                Pending ->
                    "Order is pending"

                Confirmed ->
                    "Order has been confirmed"

                Shipped ->
                    "Order has been shipped"

                Delivered ->
                    "Order has been delivered"

                Cancelled ->
                    "Order was cancelled"
    in
    { success = True
    , message = statusStr
    , orderId = Just order.orderId
    }


{-| Process an API request and return a response.
-}
processRequest : Request -> Response
processRequest request =
    case request.action of
        "create" ->
            if List.isEmpty request.products then
                { success = False
                , message = "Cannot create order with no products"
                , orderId = Nothing
                }

            else
                { success = True
                , message = "Order created successfully"
                , orderId = Just "new-order-id"
                }

        "status" ->
            case request.orderId of
                Just id ->
                    { success = True
                    , message = "Order status retrieved"
                    , orderId = Just id
                    }

                Nothing ->
                    { success = False
                    , message = "Order ID required for status check"
                    , orderId = Nothing
                    }

        _ ->
            { success = False
            , message = "Unknown action: " ++ request.action
            , orderId = Nothing
            }
