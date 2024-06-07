#![allow(dead_code, unused)]

use coerce::actor::message::{Handler, Message};
use coerce::actor::{Actor, IntoActor, IntoActorId};

pub mod workspace;

pub mod project {
    struct ProjectActor {}
}
