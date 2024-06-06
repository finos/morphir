#![allow(dead_code, unused)]
use coerce::actor::context::ActorContext;
use coerce::actor::message::{Handler, Message};
use coerce::actor::system::ActorSystem;
use coerce::actor::{Actor, ActorId, IntoActor, IntoActorId};

use async_trait::async_trait;
use tokio::sync::oneshot::{channel, Sender};
pub mod workspace {
    use crate::models::tools::ToolId;
    use crate::models::workspace::{Workspace, WorkspaceRoot};
    use async_trait::async_trait;
    use coerce::actor::context::ActorContext;
    use coerce::actor::message::{Handler, Message};
    use coerce::actor::{Actor, ActorId, IntoActor, IntoActorId};
    use std::ffi::OsString;
    use std::sync::{Arc, Mutex};
    use tokio::sync::oneshot::Sender;

    pub struct WorkspaceActor {
        tool_id: ToolId,
        state: WorkspaceState,
        on_done: Option<Sender<Option<WorkspaceRoot>>>,
    }

    impl WorkspaceActor {
        pub fn new(
            tool_id: ToolId,
            start_dir: OsString,
            sender: Sender<Option<WorkspaceRoot>>,
        ) -> Self {
            Self {
                tool_id,
                state: WorkspaceState::New { start_dir },
                on_done: Some(sender),
            }
        }
    }

    #[async_trait]
    impl Actor for WorkspaceActor {
        async fn started(&mut self, ctx: &mut ActorContext) {
            println!("WorkspaceActor started");
            match &self.state {
                WorkspaceState::New { start_dir } => {
                    let workspace_config_dir = format!(".{}", self.tool_id.as_str());
                    let maybe_workspace_root =
                        Workspace::find_root(workspace_config_dir, start_dir);
                    println!("Maybe workspace root: {:?}", maybe_workspace_root);
                    let actor_ref = self.actor_ref(ctx);
                    match maybe_workspace_root {
                        Some(workspace_root) => {
                            let workspace = Workspace::new(workspace_root.clone());
                            let activated_event = WorkspaceEvent::Activated { workspace_root };
                            self.state = WorkspaceState::Active { workspace };
                            actor_ref.notify(activated_event);
                        }
                        None => {
                            actor_ref.notify(WorkspaceEvent::NotLocated {
                                search_path: start_dir.clone(),
                            });
                        }
                    }
                }
                _ => {}
            }
        }
    }

    #[async_trait]
    impl Handler<WorkspaceEvent> for WorkspaceActor {
        async fn handle(&mut self, msg: WorkspaceEvent, ctx: &mut ActorContext) {
            match &msg {
                WorkspaceEvent::Activated { workspace_root } => {
                    println!("WorkspaceActor::handle - WorkspaceEvent::Activated");
                    if let Some(on_done) = self.on_done.take() {
                        let _ = on_done.send(Some(workspace_root.clone()));
                    }
                    ctx.stop(None);
                }
                WorkspaceEvent::NotLocated { search_path } => {
                    println!("WorkspaceActor::handle - WorkspaceEvent::NotLocated");
                    if let Some(on_done) = self.on_done.take() {
                        let _ = on_done.send(None);
                    }
                    ctx.stop(None);
                }
            }
        }
    }

    #[derive(Debug)]
    enum WorkspaceState {
        New { start_dir: OsString },
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
        Activated { workspace_root: WorkspaceRoot },
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
