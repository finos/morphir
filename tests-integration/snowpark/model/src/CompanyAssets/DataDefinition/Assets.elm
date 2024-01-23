module CompanyAssets.DataDefinition.Assets exposing (..)
import CompanyAssets.DataDefinition.Types exposing (Price, AssetCategory, AssetSubCategory(..))

type alias Asset =
      { assetId : Int
      , name : String
      , category : AssetCategory
      , subcategory : Maybe AssetSubCategory
      , price : Price
      , purchaseYear : Int
      , vendorId : Int
      }
