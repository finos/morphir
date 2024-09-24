package org.finos.morphir.elm.cli.fetch

import org.finos.morphir.lang.elm.command
import org.finos.morphir.lang.elm.command.*
import org.finos.morphir.cli.{given, *}
import caseapp.*
import kyo.*

final case class FetchOptions(projectDir: Option[kyo.Path] = None):
  def toParams: FetchParams =
    FetchParams(projectDir.getOrElse(kyo.Path(os.pwd.toString)))
