package morphir.sdk


@org.springframework.web.bind.annotation.RestController
class BooksAndRecordsSpringBoot extends company.operations.SpringBootStatefulAppAdapter [company.operations.BooksAndRecords.ID,
  company.operations.BooksAndRecords.DealCmd,
  company.operations.BooksAndRecords.Deal,
  company.operations.BooksAndRecords.DealEvent] (StatefulApp (company.operations.BooksAndRecordsObject.logic)) {



  override def read(key: company.operations.BooksAndRecords.ID) = {
    scala.jdk.javaapi.OptionConverters.toScala(dealRepository.findById(key))
  }

  override def deserialize(command : company.operations.BooksAndRecords.DealCmd) = {
      command match {
        case company.operations.BooksAndRecords.OpenDeal(dealId, _, _, _) => dealId
        case company.operations.BooksAndRecords.CloseDeal(dealId) => dealId
      }
  }

  def serialize(key: company.operations.BooksAndRecords.ID, state: company.operations.BooksAndRecords.Deal, event: company.operations.BooksAndRecords.DealEvent) =
    ""




}
