module CompanyAssets.Rules.DepreciationRules exposing (usefulLifeExceeded)

import CompanyAssets.DataDefinition.Assets exposing (Asset)
import CompanyAssets.DataDefinition.Types exposing (AssetCategory(..), AssetSubCategory(..))
import CompanyAssets.DataDefinition.Types exposing (Price, Year)


usefulLifeExceeded : Year -> List Asset -> List { category : String, price : Price }
usefulLifeExceeded currentYear assets =
    assets 
        |> List.map 
                (\asset -> 
                    { category = 
                        if check_rental_property currentYear asset then
                            "rental property"
                        else if check_vessels currentYear asset then
                            "vessel"
                        else if check_office_equipment currentYear asset then
                            "office"
                        else if check_for_computer_equipment currentYear asset then 
                            "computer"
                        else if check_for_cars currentYear asset then
                            "cars"
                        else
                            ""
                    , price = asset.price
                    }
                )
        |> List.filter (\p -> p.category /= "")

check_for_cars : Year -> Asset -> Bool
check_for_cars currentYear asset =
    case (asset.category, asset.subcategory) of
        (Vehicle, Just Car) -> (currentYear - asset.purchaseYear) >= 5
        (Vehicle, Just Truck) -> (currentYear - asset.purchaseYear) >= 5
        (_,_) -> False

check_for_computer_equipment : Year -> Asset -> Bool
check_for_computer_equipment currentYear asset =
    case (asset.category, asset.subcategory) of
        (OfficeEquipment, Just Computer) -> (currentYear - asset.purchaseYear) >= 6
        (OfficeEquipment, Just Printer) -> (currentYear - asset.purchaseYear) >= 7
        _ -> False


check_office_equipment : Year -> Asset -> Bool
check_office_equipment currentYear asset =
    case (asset.category, asset.subcategory) of
        (OfficeEquipment, Just Phone) -> (currentYear - asset.purchaseYear) >= 6
        (Furniture, _) -> (currentYear - asset.purchaseYear) >= 7
        _ -> False


compare_maybe_value : Maybe a -> a -> Bool
compare_maybe_value maybeValue toCompare =
    maybeValue
        |> Maybe.map (\t -> t == toCompare)
        |> Maybe.withDefault False

check_vessels : Year -> Asset -> Bool
check_vessels currentYear asset =
    compare_maybe_value asset.subcategory Boat 
    && currentYear - asset.purchaseYear >= 10


check_rental_property : Year -> Asset -> Bool
check_rental_property currentYear asset =
    asset.category == Building 
    && compare_maybe_value  asset.subcategory Rental
    && currentYear - asset.purchaseYear >= 27

        