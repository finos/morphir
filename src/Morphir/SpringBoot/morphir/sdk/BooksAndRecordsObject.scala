package company.operations


/** Generated based on Operations.BooksAndRecords
 */
object BooksAndRecordsObject {

  def logic(
             dealId: company.operations.BooksAndRecords.ID,
             deal: Option[company.operations.BooksAndRecords.Deal],
             dealCmd: company.operations.BooksAndRecords.DealCmd
           ): (company.operations.BooksAndRecords.ID, Option[company.operations.BooksAndRecords.Deal], company.operations.BooksAndRecords.DealEvent) =
    (dealId, deal, company.operations.BooksAndRecords.DuplicateDeal(dealId))

}
