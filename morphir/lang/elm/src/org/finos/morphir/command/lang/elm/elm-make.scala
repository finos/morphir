package org.finos.morphir.lang.elm.command

import org.finos.morphir.command.* 
import kyo.* 

final case class MakeParams()

final case class Make(params:MakeParams) extends Command[MakeParams]:
    def run(params:MakeParams): Unit < (IO & Abort[Throwable]) = 
        kyo.Console.println("Running make")
        
