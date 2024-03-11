module Morphir.Daemon

open System
open System.Diagnostics
open System.IO
open System.IO.Abstractions
open System.Threading
open StreamJsonRpc

type MorphirDaemon(sender:Stream, reader:Stream) as this =
    let rpc: JsonRpc = JsonRpc.Attach(sender, reader, this)
    let traceListener = new DefaultTraceListener()
    
    do
        // hook up request/response logging for debugging
        rpc.TraceSource <- TraceSource(typeof<MorphirDaemon>.Name, SourceLevels.Verbose)
        rpc.TraceSource.Listeners.Add traceListener |> ignore
        
    let disconnectEvent = new ManualResetEvent(false)
    
    let exit () = disconnectEvent.Set() |> ignore
    
    let fs = FileSystem()
    
    do rpc.Disconnected.Add(fun _ -> exit ())
    
    interface IDisposable with
        member this.Dispose() =
            traceListener.Dispose()
            disconnectEvent.Dispose()
            
    /// returns a hot task that resolves when the stream has terminated            
    member this.WaitForClose = rpc.Completion