package org.finos.morphir.build.elm.api

import upickle.default.{ReadWriter => RW, macroRW}
import org.finos.morphir.build._

final case class ElmFormatOptions(
    output: Option[String] = None,
    yes: Boolean = false,
    validate: Boolean = false,
    stdin: Boolean = false,
    elmVersion: Option[String] = None,
)

object ElmFormatOptions {
    implicit val rw: RW[ElmFormatOptions] = macroRW
}