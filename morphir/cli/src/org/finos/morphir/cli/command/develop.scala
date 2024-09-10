package org.finos.morphir.cli.command

import caseapp.*
import org.finos.morphir.cli.given

final case class DevelopOptions()

object Develop extends Command[DevelopOptions]:  
  def run(options: DevelopOptions, remainingArgs: RemainingArgs): Unit =
    pprint.log("DevelopOptions:")
    pprint.log(options)
    pprint.log("Remaining Args:")
    pprint.log(remainingArgs)    
