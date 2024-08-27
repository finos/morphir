package org.finos.morphir

import caseapp.*
import caseapp.core.argparser.{ArgParser, SimpleArgParser}
import caseapp.core.Error

package object cli:
  given ArgParser[os.Path] = SimpleArgParser.from("path"): input =>
    try
      Right(os.Path(input))
    catch
      case e: Throwable => Left(Error.MalformedValue(input, "Failed to parse input value as a path"))
