module API exposing (..)

import Data exposing (..)

---- Elements
createElement : Domain -> Element -> Cmd Msg
updateElement : Domain -> Element -> Cmd Msg
moveElement : ElementID -> Domain -> Cmd Msg
renameElement : ElementID -> ElementID -> Cmd Msg 
deleteElement : ElementID -> Cmd Msg

setElementConstraints : ElementConstraints -> Cmd Msg

---- Datasets
createDataset : Dataset -> Cmd Msg
updateDataset : Dataset -> Cmd Msg
deleteDataset : DatasetID -> Cmd Msg

---- Finance
linkToElement : ElementID -> A -> Cmd Msg
unlinkFromElement : ElementID -> A -> Cmd Msg

linkToDataset : DatasetID -> A -> Cmd Msg
unlinkFromDataset : DatasetID -> A -> Cmd Msg
