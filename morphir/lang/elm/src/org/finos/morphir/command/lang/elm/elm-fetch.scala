
package org.finos.morphir.lang.elm.command

import org.finos.morphir.command.* 
import kyo.* 

final case class FetchParams()

final case class Fetch(params:FetchParams) extends Command[FetchParams]:
    def run(params:FetchParams): Unit < (IO & Abort[Throwable]) = 
        kyo.Console.println("Running fetch")
        

