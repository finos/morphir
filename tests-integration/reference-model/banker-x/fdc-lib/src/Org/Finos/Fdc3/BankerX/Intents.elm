module Org.Finos.Fdc3.BankerX.Intents exposing (..)

type alias InterestRate = Int

type alias PromotionalPeriod =
  { months: Int
  , promotionalRate: InterestRate
  }

type alias Amount = Int
type alias Vendor = String
type alias Timestamp = Int
type alias UserId = String
type alias Category = String
type alias PointOfPurchase = String

type alias ProviderTerms =
  { provider: String
  , points: Int
  , interestRate: InterestRate
  , promotionalPeriod: PromotionalPeriod
  }

  type alias GetTerms =
    { amount: Amount
    , vendor: Vendor
    , purchaseTimestamp: Timestamp
    , userId: UserId
    , category: Category
    , pointOfPurchase: PointOfPurchase
    }
