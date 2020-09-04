package morphir.sdk

import company.operations.BooksAndRecordsObject


class BooksAndRecordsSpringBoot extends SpringBootStatefulAppAdapter [company.operations.BooksAndRecords.ID,
  company.operations.BooksAndRecords.DealCmd,
  company.operations.BooksAndRecords.Deal,
  company.operations.BooksAndRecords.DealEvent] (StatefulApp (BooksAndRecordsObject.logic)) {

  override def read(key: company.operations.BooksAndRecords.ID) =
    Some (company.operations.BooksAndRecords.Deal(key, null, null, null))

  def serialize(key: company.operations.BooksAndRecords.ID, state: company.operations.BooksAndRecords.Deal, event: company.operations.BooksAndRecords.DealEvent) =
    ""



}
