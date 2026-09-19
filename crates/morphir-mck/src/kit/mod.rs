//! Kit parsing, loading, hashing and provenance.

pub mod closure;
pub mod embedded;
pub mod hash;
pub mod load;
pub mod manifest;
pub mod snapshot;
pub mod source;
pub mod status;
pub mod syntax;
pub mod vendor;

pub use hash::{ALGORITHM, ContentDigest, content_hash};
pub use load::{Kit, Profile, ResolvedText, load_kit};
pub use source::{KIT_PATH, KitSource};
pub use syntax::case::{CaseId, Compare, KitCase, KitError, KitFence, Status};
pub use syntax::info_string::{FenceInfo, Language, Role};
