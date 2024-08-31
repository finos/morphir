package org.finos.morphir.cli
import caseapp.*
import caseapp.core.argparser.{ArgParser, SimpleArgParser}
import caseapp.core.Error

given ArgParser[os.Path] = SimpleArgParser.from("path"): input =>
  try
    Right(os.Path(input))
  catch
    case e: Throwable => Left(Error.MalformedValue(input, "Failed to parse input value as a path"))
