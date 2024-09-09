package org.finos.morphir.cli
import caseapp.*
import caseapp.core.argparser.{ArgParser, SimpleArgParser}
import caseapp.core.Error
import kyo.*

given oslibPathArgParser: ArgParser[os.Path] = SimpleArgParser.from("path"): input =>
  try
    Right(os.Path(input))
  catch
    case e: Throwable => Left(Error.MalformedValue(input, "Failed to parse input value as a path"))

given kyoPathArgParser: ArgParser[kyo.Path] = SimpleArgParser.from("path"): input =>
  try
    Right(kyo.Path(input))
  catch
    case e: Throwable => Left(Error.MalformedValue(input, "Failed to parse input value as a path"))
