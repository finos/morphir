///|
/// Run-wide services shared by native execution and workspace ownership.
pub(all) struct Services {
  configuration : @configuration.Config
  logger : &@logging.Logger
}

///|
/// The desktop owns the real resource callbacks; the framework owns their order
/// and ensures that every started service is stopped after embedder shutdown.
pub fn create(
  configuration : @configuration.Config,
  logger : &@logging.Logger,
  start_workspace~ : async () -> Unit,
  stop_workspace~ : async () -> Unit,
  start_executions~ : async () -> Unit,
  stop_executions~ : async () -> Unit,
) -> @lander_host.Host[Services] raise {
  let environment : Map[String, String] = Map([])
  @lander_host.builder(
    @lander_core.AppName::parse("morphir-workbench"),
    [],
    env_vars=environment,
  )
  |> @lander_host.skip_env_source
  |> @lander_host.service(
    "native-executions",
    start=_ => {
      start_executions()
      logger.debug("Started native executions", [])
    },
    stop=_ => {
      stop_executions()
      logger.debug("Stopped native executions", [])
    },
  )
  |> @lander_host.service(
    "workspace-files",
    start=_ => {
      start_workspace()
      logger.debug("Started workspace files", [])
    },
    stop=_ => {
      stop_workspace()
      logger.debug("Stopped workspace files", [])
    },
  )
  |> @lander_host.build(_ => { configuration, logger, })
}

///|
priv enum Startup {
  Waiting
  Running(@lander_host.Lifetime)
  Stopped(@lander_host.RunOutcome)
  Aborted
}

///|
/// A supervised host task within Proton's application task group.
pub struct Controller {
  priv lifetime : @lander_host.Lifetime
  priv task : @async.Task[@lander_host.RunOutcome]
  priv lock : @async.Mutex
  priv mut outcome : @lander_host.RunOutcome?
}

///|
pub suberror HostStoppedBeforeStartup

///|
/// Wait for the host's services to start before allowing the UI to use them.
pub async fn start(
  group : @async.TaskGroup[Unit],
  host : @lander_host.Host[Services],
) -> Controller {
  let startup : Ref[Startup] = Ref(Waiting)
  let changed = @async.CondVar::Cond()
  let task = group.spawn(
    async fn() {
      errdefer {
        if startup.val is Waiting {
          startup.val = Aborted
        }
        changed.broadcast()
      }
      let outcome = @lander_host.run(host, context => {
        startup.val = Running(context.lifetime)
        changed.broadcast()
        while true {
          @async.sleep(60000)
        }
      })
      if startup.val is Waiting {
        startup.val = Stopped(outcome)
      }
      changed.broadcast()
      outcome
    },
    allow_failure=true,
  )
  while startup.val is Waiting {
    changed.wait()
  }
  match startup.val {
    Running(lifetime) =>
      { lifetime, task, lock: @async.Mutex::Mutex(), outcome: None, }
    Stopped(outcome) => {
      if outcome.failures().get(0) is Some(error) {
        raise error
      }
      raise HostStoppedBeforeStartup
    }
    Aborted => {
      ignore(task.wait())
      raise HostStoppedBeforeStartup
    }
    Waiting => abort("startup wait ended without a host state")
  }
}

///|
/// A real embedder stop, followed by confirmed completion of resource cleanup.
/// Repeated shutdown callbacks share the same outcome and do not stop twice.
pub async fn Controller::shutdown(self : Controller) -> @lander_host.RunOutcome {
  self.lock.acquire()
  defer self.lock.release()
  if self.outcome is Some(outcome) {
    return outcome
  }
  self.lifetime.stop_from_embedder()
  let outcome = self.task.wait()
  self.outcome = Some(outcome)
  outcome
}
