package org.finos.morphir.command
import kyo.* 
import scala.concurrent.*

/// A command is a unit of work that can be run by a KyoApp
trait Command[Params]:

    def run(params:Params): Unit < (IO & Abort[Throwable])

    final def runFuture(params:Params): Future[Unit] = 
        val effect = run(params)
        val fiber = Async.run(effect)
        val toFuture = fiber.map(_.toFuture)
        KyoApp.run(toFuture)

    final def unsafeRun(params:Params): Unit = 
        val effect = run(params)
        KyoApp.run(effect)        
    
    final def unsafeRunResult(params:Params): Result[Throwable, Unit] = 
        val effect = run(params)
        val result = Abort.run(effect)        
        KyoApp.run(result)
        