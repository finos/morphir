package morphir.rdf.nquads

import neotype.*
import morphir.rdf.ValidationResult
import morphir.rdf.nquads.internal.lexer
import parsley.Success
import parsley.Failure
import java.net.URI

case class IriRef private (underlying: String) {
  override def toString() = s"<$underlying>"
  lazy val uri: URI = URI.create(underlying)
  def withFragment(fragment: String): IriRef =
    uri.getFragment() match
      case null => IriRef(underlying + "#" + fragment)
      case existing =>
        IriRef(underlying.replace("#" + existing, "#" + fragment))
}

object IriRef:

  def parse(input: String): Either[String, IriRef] =
    lexer.IRIREF.parse(input) match
      case Success(ref) => Right(IriRef(ref))
      case Failure(err) => Left(err.toString())

  /** Bypasses validation and creates an IriRef directly. CAUTION: This method
    * does not validate the input string, make sure you not what you are
    * doing!!!!
    */
  private[nquads] def unsafeMake(value: String): IriRef = IriRef(value)

  object WellKnown:
    object MorphirSpecific:
      val Morphir = IriRef("https://morphir.finos.org/")
      val MorphirOntology = IriRef("https://morphir.finos.org/ontology/")
      val MorphirVocabulary = IriRef("https://morphir.finos.org/vocabulary/")
      val MorphirData = IriRef("https://morphir.finos.org/data/")
      val MorphirCodeModel = IriRef("https://morphir.finos.org/codemodel/")
