package org.finos.morphir.command
import kyo.* 
import scala.concurrent.*
trait Command[Params]:

    def run(params:Params): Unit < (IO & Abort[Throwable])

    final def runFuture(params:Params): Future[Unit] = 
        val effect = run(params)
        val fiber = KyoApp.runFiber(effect)
        val toFuture = fiber.toFuture
        KyoApp.run(toFuture)

    final def unsafeRun(params:Params): Unit = 
        val effect = run(params)
        KyoApp.run(effect)        
    
    final def unsafeRunResult(params:Params): Result[Throwable, Unit] = 
        val effect = run(params)
        val fiber = KyoApp.runFiber(effect)
        val result = fiber.getResult
        KyoApp.run(result)
        

