//! Kit parsing, loading, hashing and provenance.

pub mod embedded;
pub mod hash;
pub mod load;
pub mod source;
pub mod status;
pub mod syntax;

pub use hash::{ALGORITHM, ContentDigest, content_hash};
pub use load::{Kit, Profile, ResolvedText, load_kit};
pub use source::{KIT_PATH, KitSource};
pub use syntax::case::{CaseId, Compare, KitCase, KitError, KitFence, Status};
pub use syntax::info_string::{FenceInfo, Language, Role};
