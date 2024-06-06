#![allow(dead_code, unused)]
use coerce::actor::context::ActorContext;
use coerce::actor::message::{Handler, Message};
use coerce::actor::system::ActorSystem;
use coerce::actor::{Actor, ActorId, IntoActor, IntoActorId};

use async_trait::async_trait;
use tokio::sync::oneshot::{channel, Sender};
pub mod workspace {
    use crate::models::workspace::Workspace;
    use async_trait::async_trait;
    use coerce::actor::context::ActorContext;
    use coerce::actor::message::{Handler, Message};
    use coerce::actor::{Actor, ActorId, IntoActor, IntoActorId};
    use std::ffi::OsString;
    use tokio::sync::oneshot::Sender;

    pub struct WorkspaceActor {
        state: WorkspaceState,
        on_done: Option<Sender<()>>,
    }

    impl WorkspaceActor {
        pub fn new(launch_dir: OsString, sender: Sender<()>) -> Self {
            Self {
                state: WorkspaceState::New { launch_dir },
                on_done: Some(sender),
            }
        }
    }

    #[async_trait]
    impl Actor for WorkspaceActor {
        async fn started(&mut self, ctx: &mut ActorContext) {
            println!("WorkspaceActor started");
            if (self.state.is_new()) {
                //TODO: Locate workspace
            }
        }
    }

    #[async_trait]
    impl Handler<WorkspaceEvent> for WorkspaceActor {
        async fn handle(&mut self, msg: WorkspaceEvent, ctx: &mut ActorContext) {}
    }

    #[derive(Debug, PartialEq, Eq)]
    enum WorkspaceState {
        New { launch_dir: OsString },
        Active { workspace: Workspace },
    }

    impl WorkspaceState {
        pub fn is_new(&self) -> bool {
            match self {
                WorkspaceState::New { .. } => true,
                _ => false,
            }
        }
    }

    pub enum WorkspaceEvent {
        Activated { workspace: Workspace },
        NotLocated { search_path: OsString },
    }

    impl Message for WorkspaceEvent {
        type Result = ();
    }

    pub struct WorkspaceCoordinator {
        workspaces: Vec<WorkspaceHandle>,
        on_work_completed: Option<Sender<()>>,
    }

    impl WorkspaceCoordinator {
        pub fn new(sender: Sender<()>) -> Self {
            Self {
                workspaces: Vec::new(),
                on_work_completed: Some(sender),
            }
        }
    }

    #[async_trait]
    impl Actor for WorkspaceCoordinator {
        async fn started(&mut self, ctx: &mut ActorContext) {
            println!("WorkspaceCoordinator started");
        }
    }

    struct WorkspaceHandle {
        workspace: Workspace,
        actor_id: ActorId,
    }
}

pub mod project {
    struct ProjectActor {}
}
