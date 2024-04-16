package morphir.rdf.nquads

import neotype.*

type ValidationResult = Boolean | String
object ValidationResult:
  def apply(value: Boolean): ValidationResult = value
  def apply(value: String): ValidationResult = value
  object Invalid:
    def unapply(value: ValidationResult): Option[String] =
      value match
        case s: String => Some(s)
        case _         => None
  object Valid:
    def unapply(value: ValidationResult): Option[Boolean] =
      value match
        case b: Boolean => Some(b)
        case _          => None
