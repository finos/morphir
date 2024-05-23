module Morphir.Visual.Components.ModalComponent exposing (attachModal)

{-
   @docs attachModal

-}

import Element exposing (Attribute, Element, centerX, centerY, el, fill, height, inFront, rgba255, width)
import Element.Background as Background
import Element.Border as Border
import Element.Events exposing (onClick)
import Morphir.Visual.Theme exposing (Theme)


type alias Config msg =
    { content : Element msg
    , isOpen : Bool
    , onClose : msg
    }


attachModal : Theme -> Config msg -> Attribute msg
attachModal theme config =
    inFront <|
        if config.isOpen then
            el [ width fill, height fill, Background.color (rgba255 0 0 0 0.5), onClick config.onClose ] <|
                el [ centerX, centerY, Border.shadow
            { offset = ( 0, 3 )
            , size = 3
            , blur = 9
            , color = rgba255 0 0 0 0.4
            } ] config.content

        else
            Element.none
