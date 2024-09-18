package org.finos.morphir.lang.elm

import kyo.*
import metaconfig.*
import metaconfig.generic.*
import neotype.*

type ElmPackageName = ElmPackageName.Type
object ElmPackageName extends Subtype[String]:
  inline def pattern = "^(?<author>[-a-zA-Z0-9@:%_\\+.~#?&]{2,})/(?<name>[-a-zA-Z0-9@:%_\\+.~#?&]{2,})$".r
  inline override def validate(input: String) = pattern.matches(input)

  given confEncoder: ConfEncoder[ElmPackageName] = ConfEncoder.StringEncoder.contramap(_.value)

  given confDecoder: ConfDecoder[ElmPackageName] = ConfDecoder.stringConfDecoder.flatMap: str =>
    parse(str).fold((err: Result.Error[String]) => Configured.error(err.show))(Configured.ok)

  def parse(input: String): Result[String, ElmPackageName] = Result.fromEither(make(input))
  extension (self: ElmPackageName)
    def value: String       = self
    def author: String      = pattern.findFirstMatchIn(self).get.group("author")
    def packageName: String = pattern.findFirstMatchIn(self).get.group("name")

end ElmPackageName

type ElmNamespace = ElmNamespace.Type
object ElmNamespace extends Subtype[String]:
  inline def pattern                          = """^([A-Z][a-zA-Z0-9]*)(\.[A-Z][a-zA-Z0-9]*)*$""".r
  inline override def validate(input: String) = pattern.matches(input)

  given confEncoder: ConfEncoder[ElmNamespace] = ConfEncoder.StringEncoder.contramap(_.value)
  extension (self: ElmNamespace)
    def value: String       = self
    def parts: List[String] = self.split('.').toList

type ElmModuleName = ElmModuleName.Type
object ElmModuleName extends Subtype[String]:
  inline def pattern                            = """^([A-Z][a-zA-Z0-9]*)(\.[A-Z][a-zA-Z0-9]*)*$""".r
  given confEncoder: ConfEncoder[ElmModuleName] = ConfEncoder.StringEncoder.contramap(_.value)
  given confDecoder: ConfDecoder[ElmModuleName] = ConfDecoder.stringConfDecoder.flatMap {
    str =>
      parse(str).fold((err: Result.Error[String]) => Configured.error(err.show))(Configured.ok)
  }

  def parse(input: String): Result[String, ElmModuleName] = Result.fromEither(make(input))

  extension (name: ElmModuleName)
    def parts: List[String] = name.split('.').toList
    def value: String       = name
    def namespace: Option[ElmNamespace] =
      val idx = name.lastIndexOf('.')
      if idx < 0 then
        None
      else
        Some(ElmNamespace.unsafeMake(name.substring(0, idx)))
