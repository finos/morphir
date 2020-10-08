package company.operations


/** Generated based on Operations.BooksAndRecords
*/
object BooksAndRecords{


  case class Deal(
                   @org.springframework.data.annotation.Id
                   arg1: company.operations.BooksAndRecords.ID,
                   arg2: company.operations.BooksAndRecords.ProductID,
                   arg3: company.operations.BooksAndRecords.Price,
                   arg4: company.operations.BooksAndRecords.Quantity
                 )


  // Commands
  @com.fasterxml.jackson.annotation.JsonTypeInfo(use = com.fasterxml.jackson.annotation.JsonTypeInfo.Id.NAME,
    include = com.fasterxml.jackson.annotation.JsonTypeInfo.As.PROPERTY, property = "type")
  @com.fasterxml.jackson.annotation.JsonSubTypes(Array
  (
    new com.fasterxml.jackson.annotation.JsonSubTypes.Type(value = classOf[OpenDeal], name = "openDeal"),
    new com.fasterxml.jackson.annotation.JsonSubTypes.Type(value = classOf[CloseDeal], name = "closeDeal")
  ))
  sealed trait DealCmd

  @org.springframework.context.annotation.Bean
  case class OpenDeal(
                       @com.fasterxml.jackson.annotation.JsonProperty("dealId") arg1: company.operations.BooksAndRecords.ID,
                       @com.fasterxml.jackson.annotation.JsonProperty("productId") arg2: company.operations.BooksAndRecords.ProductID,
                       @com.fasterxml.jackson.annotation.JsonProperty("price") arg3: company.operations.BooksAndRecords.Price,
                       @com.fasterxml.jackson.annotation.JsonProperty("quantity") arg4: company.operations.BooksAndRecords.Quantity
                     ) extends company.operations.BooksAndRecords.DealCmd

  @org.springframework.context.annotation.Bean
  case class CloseDeal(
                        @com.fasterxml.jackson.annotation.JsonProperty("dealId") arg1: company.operations.BooksAndRecords.ID
                      ) extends company.operations.BooksAndRecords.DealCmd

  sealed trait DealEvent {

  }

  case class DealOpened(
                         arg1: company.operations.BooksAndRecords.ID,
                         arg2: company.operations.BooksAndRecords.ProductID,
                         arg3: company.operations.BooksAndRecords.Price,
                         arg4: company.operations.BooksAndRecords.Quantity
                       ) extends company.operations.BooksAndRecords.DealEvent

  case class DealClosed(
                         arg1: company.operations.BooksAndRecords.ID
                       ) extends company.operations.BooksAndRecords.DealEvent

  case class InvalidQuantity(
                              arg1: company.operations.BooksAndRecords.ID,
                              arg2: company.operations.BooksAndRecords.Quantity
                            ) extends company.operations.BooksAndRecords.DealEvent

  case class InvalidPrice(
                           arg1: company.operations.BooksAndRecords.ID,
                           arg2: company.operations.BooksAndRecords.Price
                         ) extends company.operations.BooksAndRecords.DealEvent

  case class DuplicateDeal(
                            arg1: company.operations.BooksAndRecords.ID
                          ) extends company.operations.BooksAndRecords.DealEvent

  case class DealNotFound(
                           arg1: company.operations.BooksAndRecords.ID
                         ) extends company.operations.BooksAndRecords.DealEvent

  type ID = String

  type Price = Float

  type ProductID = String

  type Quantity = Int
}
