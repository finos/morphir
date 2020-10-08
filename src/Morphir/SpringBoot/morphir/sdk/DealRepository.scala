package morphir.sdk

trait DealRepository extends org.springframework.data.mongodb.repository.MongoRepository[company.operations.BooksAndRecords.Deal, String] {}