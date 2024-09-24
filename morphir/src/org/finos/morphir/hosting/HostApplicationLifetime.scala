package org.finos.morphir.hosting
import kyo.*
import metaconfig.*
import kyo.Hub.Listener

trait HostApplicationLifetime:
  def applicationStarted: Listener[Unit] < IO
  def applicationStopping: Listener[Unit] < IO
  def applicationStopped: Listener[Unit] < IO
  def stopApplication(): Unit < Async

object HostApplicationLifetime:
  trait Error extends Exception:
    def message: String

  enum ApplicationLifetimeEvent:
    case Started(conf: Conf)
    case Stopping
    case Stopped

  final case class Live(
    channel: Channel[Unit],
    applicationStartedHub: Hub[Unit],
    applicationStoppingHub: Hub[Unit],
    applicationStoppedHub: Hub[Unit]
  ) extends HostApplicationLifetime:
    override def applicationStarted: Listener[Unit] < IO  = applicationStartedHub.listen
    override def applicationStopping: Listener[Unit] < IO = applicationStoppingHub.listen
    override def applicationStopped: Listener[Unit] < IO  = applicationStoppedHub.listen
    override def stopApplication(): Unit < Async          = channel.offerUnit(())
