//! Installed implementation association claims. No build/source authority.
use super::*;
tagged! { pub OsOperand("kind") {
    UnixBytes => "unix-bytes" {bytes:ObservedBytes=>"bytes"},
    WindowsWide => "windows-wide" {units:Items<Natural<0,65535>,0,{usize::MAX}> =>"units"},
} }
words! { pub FileMode { Regular=>"regular",Executable=>"executable" } }
record! { pub PackageFile {path:SourcePath=>"path",mode:FileMode=>"mode",byte_length:Natural<0,{u64::MAX}> =>"byteLength",sha256:ContentSha256=>"sha256"} }
tagged! { pub SourceEntry("kind") {
    File=>"file" {path:SourcePath=>"path",mode:FileMode=>"mode",byte_length:Natural<0,{u64::MAX}> =>"byteLength",sha256:ContentSha256=>"sha256"},
    SymlinkLiteral=>"symlink-literal" {path:SourcePath=>"path",target_bytes:ObservedBytes=>"targetBytes",byte_length:Natural<0,{u64::MAX}> =>"byteLength",sha256:ContentSha256=>"sha256"},
} }
record! { pub PackageCensus {root:OsOperand=>"root",entries:Items<PackageFile,0,{usize::MAX}> =>"entries",sha256:ContentSha256=>"sha256"} }
words! { pub ObjectFormat { Sha1=>"sha1",Sha256=>"sha256" } }
words! { pub TrackedStatus { Unchanged=>"unchanged",Changed=>"changed" } }
record! { pub SourceAssociation {root:OsOperand=>"root",head:Text<1,64> =>"head",object_format:ObjectFormat=>"objectFormat",tracked_status:TrackedStatus=>"trackedStatus",entries:Items<SourceEntry,0,{usize::MAX}> =>"entries",sha256:ContentSha256=>"sha256"} }
tagged! { pub VersionObservation("kind") {Unobserved=>"unobserved"{}} }
record! { pub RuntimeObservation {program:OsOperand=>"program",byte_length:Natural<0,{u64::MAX}> =>"byteLength",sha256:ContentSha256=>"sha256",version:VersionObservation=>"version"} }
tagged! { pub LaunchObservation("kind") {
    NodePackage=>"node-package"{entry:OsOperand=>"entry"},
    NativeExecutable=>"native-executable"{program:OsOperand=>"program",byte_length:Natural<0,{u64::MAX}> =>"byteLength",sha256:ContentSha256=>"sha256"},
} }
record! { pub CommandPaths {launch_file:OsOperand=>"launchFile",connection_file:OsOperand=>"connectionFile",source_selection_file:OsOperand=>"sourceSelectionFile",project_selection_file:OsOperand=>"projectSelectionFile",destination:OsOperand=>"destination"} }
literal! {pub GitTool=>"git"}
words! {pub GitQuery{Revision=>"revision",TrackedInventory=>"tracked-inventory",TrackedStatus=>"tracked-status"}}
record! {pub ToolProcess {
    process_ordinal:Natural<0,{u64::MAX}> =>"processOrdinal",tool:GitTool=>"tool",query:GitQuery=>"query",program:OsOperand=>"program",directory:OsOperand=>"directory",arguments:Items<OsOperand,0,{usize::MAX}> =>"arguments",
    completion:DirectProcessCompletion=>"completion",stdout:ObservedBytes=>"stdout",stderr:ObservedBytes=>"stderr",stderr_truncated:MeasuredBool=>"stderrTruncated",descendants:DescendantCoverage=>"descendants",
}}
tagged! { pub ImplementationObservation("kind") {
    Unobserved=>"unobserved"{},
    Observed=>"observed"{before_action:Natural<0,{u64::MAX}> =>"beforeAction",launch:LaunchObservation=>"launch",runtime:RuntimeObservation=>"runtime",command_paths:CommandPaths=>"commandPaths",package:PackageCensus=>"package",source:SourceAssociation=>"source",metadata_tools:Items<ToolProcess,0,{usize::MAX}> =>"metadataTools"},
} }
pub(super) struct Descriptor<'a> {
    pub(super) path: &'a str,
    pub(super) kind: u8,
    pub(super) mode: u8,
    pub(super) length: u64,
    pub(super) digest: &'a [u8; 32],
}
impl PackageFile {
    pub(super) fn descriptor(&self) -> Descriptor<'_> {
        Descriptor {
            path: self.path.as_str(),
            kind: 0,
            mode: match self.mode {
                FileMode::Regular => 0,
                FileMode::Executable => 1,
            },
            length: self.byte_length.0,
            digest: &self.sha256.0,
        }
    }
}
impl SourceEntry {
    pub(super) fn descriptor(&self) -> Descriptor<'_> {
        match self {
            Self::File {
                path,
                mode,
                byte_length,
                sha256,
            } => Descriptor {
                path: path.as_str(),
                kind: 0,
                mode: match mode {
                    FileMode::Regular => 0,
                    FileMode::Executable => 1,
                },
                length: byte_length.0,
                digest: &sha256.0,
            },
            Self::SymlinkLiteral {
                path,
                byte_length,
                sha256,
                ..
            } => Descriptor {
                path: path.as_str(),
                kind: 1,
                mode: 0,
                length: byte_length.0,
                digest: &sha256.0,
            },
        }
    }
}
pub(in crate::workbench::model_originals::workflow) const REVISION: &[&str] = &[
    "rev-parse",
    "--path-format=absolute",
    "--show-toplevel",
    "--show-object-format",
    "HEAD",
];
pub(in crate::workbench::model_originals::workflow) const INVENTORY: &[&str] =
    &["ls-files", "--stage", "-z"];
pub(in crate::workbench::model_originals::workflow) const STATUS: &[&str] = &[
    "--no-optional-locks",
    "-c",
    "core.fsmonitor=false",
    "status",
    "--porcelain=v1",
    "-z",
    "--untracked-files=no",
];
