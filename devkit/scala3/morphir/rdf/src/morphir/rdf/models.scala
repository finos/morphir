package morphir.rdf

enum LiteralKind:
  case Simple
  case LangTag(tag: String)
  case DataType(dataType: morphir.rdf.DataType)

enum DataType:
  case DataTypeRef(id: Int)
  case DataTypeIRI(iri: String)

enum RdfIri:
  case Indirect(prefix: Int, name: Int)
