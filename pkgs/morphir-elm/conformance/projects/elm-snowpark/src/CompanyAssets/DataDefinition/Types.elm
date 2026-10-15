module CompanyAssets.DataDefinition.Types exposing (Price, AssetCategory(..), AssetSubCategory(..), Year)

type alias Price = Float

type alias Year = Int


type AssetCategory =
    Vehicle
    | Furniture
    | Building
    | OfficeEquipment


type AssetSubCategory =
    Car
    | Boat
    | Office
    | Warehouse
    | Truck
    | Computer
    | Printer
    | Phone
    | Rental