use std::{
    io,
    sync::{Arc, Mutex},
};

use base64::{Engine as _, engine::general_purpose::STANDARD};
use morphir_distribution::{RelativeArtifactPath, Sha256Digest};
use semver::Version;
use serde::Serialize;

use super::*;

pub const MAX_HOST_GENERATIONS: usize = 64;

/// The shared Rust/TypeScript profile uses canonical SemVer whose core fits
/// exactly in both libraries. Prerelease/build identifiers remain strings.
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(transparent)]
struct ProducerVersion(Version);
impl ProducerVersion {
    fn parse(text: &str) -> Result<Self, ArtifactError> {
        const MAX_SAFE_COMPONENT: u64 = 9_007_199_254_740_991;
        let parsed = Version::parse(text).map_err(|_| ArtifactError::InvalidIdentity)?;
        if parsed.to_string() != text
            || [parsed.major, parsed.minor, parsed.patch]
                .into_iter()
                .any(|component| component > MAX_SAFE_COMPONENT)
        {
            return Err(ArtifactError::InvalidIdentity);
        }
        Ok(Self(parsed))
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Producer {
    id: ProducerId,
    version: ProducerVersion,
}
impl Producer {
    pub fn parse(id: &str, version: &str) -> Result<Self, ArtifactError> {
        Ok(Self {
            id: ProducerId::parse(id)?,
            version: ProducerVersion::parse(version)?,
        })
    }
}

#[derive(Clone, Debug)]
pub struct GenerationContext {
    session: SessionId,
    provider: ProviderId,
    target: GenerationTarget,
    ir_version: GenerationIrVersion,
    producer: Producer,
}
impl GenerationContext {
    pub fn new(
        session: SessionId,
        provider: ProviderId,
        target: GenerationTarget,
        ir_version: GenerationIrVersion,
        producer: Producer,
    ) -> Self {
        Self {
            session,
            provider,
            target,
            ir_version,
            producer,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ArtifactDescriptor {
    id: ArtifactId,
    path: RelativeArtifactPath,
    kind: ArtifactKind,
    byte_length: usize,
    sha256: Sha256Digest,
}
impl ArtifactDescriptor {
    pub fn id(&self) -> &ArtifactId {
        &self.id
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GeneratedArtifactManifest {
    status: ReadyStatus,
    profile: ProfileName,
    contract_version: ArtifactContractVersion,
    session_id: SessionId,
    provider_id: ProviderId,
    generation_id: GenerationId,
    producer: Producer,
    target: GenerationTarget,
    ir_version: GenerationIrVersion,
    artifacts: Vec<ArtifactDescriptor>,
    diagnostics: ArtifactDiagnostics,
}
impl GeneratedArtifactManifest {
    pub fn generation_id(&self) -> &GenerationId {
        &self.generation_id
    }
    pub fn artifacts(&self) -> &[ArtifactDescriptor] {
        &self.artifacts
    }
}
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
enum ReadyStatus {
    #[serde(rename = "ready")]
    Ready,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ArtifactChunk {
    profile: ProfileName,
    contract_version: ArtifactContractVersion,
    generation_id: GenerationId,
    artifact_id: ArtifactId,
    offset: ByteOffset,
    next_offset: ByteOffset,
    content: String,
}
impl ArtifactChunk {
    pub fn content(&self) -> &str {
        &self.content
    }
    pub fn next_offset(&self) -> ByteOffset {
        self.next_offset
    }
}

/// Host-wide reservation includes in-flight decoding and retained bytes.
/// A generation slot bounds empty-file descriptors independently of bytes.
#[derive(Clone, Default)]
pub struct HostArtifactCapacity(Arc<Mutex<CapacityUsage>>);
#[derive(Clone)]
pub struct ArtifactUsageObserver(HostArtifactCapacity);
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ArtifactUsage {
    reserved_bytes: usize,
    reserved_generations: usize,
    active_invocations: usize,
}
impl ArtifactUsage {
    pub fn reserved_bytes(self) -> usize {
        self.reserved_bytes
    }
    pub fn reserved_generations(self) -> usize {
        self.reserved_generations
    }
    pub fn active_invocations(self) -> usize {
        self.active_invocations
    }
}
impl ArtifactUsageObserver {
    pub fn snapshot(&self) -> ArtifactUsage {
        let usage = self.0.0.lock().expect("artifact capacity mutex");
        ArtifactUsage {
            reserved_bytes: usage.bytes,
            reserved_generations: usage.generations,
            active_invocations: usize::from(matches!(usage.producer, ProducerSlot::Reserved)),
        }
    }
}
#[derive(Default)]
struct CapacityUsage {
    bytes: usize,
    generations: usize,
    producer: ProducerSlot,
}
#[derive(Default)]
enum ProducerSlot {
    #[default]
    Available,
    Reserved,
}
pub(crate) struct ArtifactInvocationPermit(HostArtifactCapacity);
struct Reservation {
    capacity: HostArtifactCapacity,
    bytes: usize,
}
impl HostArtifactCapacity {
    pub fn observer(&self) -> ArtifactUsageObserver {
        ArtifactUsageObserver(self.clone())
    }
    pub(crate) fn reserve_invocation(&self) -> Result<ArtifactInvocationPermit, ArtifactError> {
        let mut usage = self.0.lock().expect("artifact capacity mutex");
        if matches!(usage.producer, ProducerSlot::Reserved) {
            return Err(ArtifactError::Capacity);
        }
        usage.producer = ProducerSlot::Reserved;
        Ok(ArtifactInvocationPermit(self.clone()))
    }
    pub fn reserved_bytes(&self) -> usize {
        self.0.lock().expect("artifact capacity mutex").bytes
    }
    pub fn reserved_generations(&self) -> usize {
        self.0.lock().expect("artifact capacity mutex").generations
    }
    fn reserve(&self, bytes: usize) -> Result<Reservation, ArtifactError> {
        let mut usage = self.0.lock().expect("artifact capacity mutex");
        let next = usage
            .bytes
            .checked_add(bytes)
            .ok_or(ArtifactError::Capacity)?;
        if next > MAX_SET_BYTES || usage.generations >= MAX_HOST_GENERATIONS {
            return Err(ArtifactError::Capacity);
        }
        usage.bytes = next;
        usage.generations += 1;
        Ok(Reservation {
            capacity: self.clone(),
            bytes,
        })
    }
}
impl Drop for ArtifactInvocationPermit {
    fn drop(&mut self) {
        self.0.0.lock().expect("artifact capacity mutex").producer = ProducerSlot::Available;
    }
}
impl Reservation {
    fn reserve_bytes(&mut self, bytes: usize) -> Result<(), ArtifactError> {
        let mut usage = self.capacity.0.lock().expect("artifact capacity mutex");
        let next = usage
            .bytes
            .checked_add(bytes)
            .ok_or(ArtifactError::Capacity)?;
        if next > MAX_SET_BYTES {
            return Err(ArtifactError::Capacity);
        }
        usage.bytes = next;
        self.bytes += bytes;
        Ok(())
    }
}
impl Drop for Reservation {
    fn drop(&mut self) {
        let mut usage = self.capacity.0.lock().expect("artifact capacity mutex");
        usage.bytes -= self.bytes;
        usage.generations -= 1;
    }
}

struct RetainedGeneration {
    manifest: GeneratedArtifactManifest,
    set: GeneratedArtifactSet,
    _reservation: Reservation,
}
#[derive(Default)]
pub struct ArtifactSession(SessionState);
#[derive(Default)]
enum SessionState {
    #[default]
    Empty,
    Generating(Reservation),
    Ready(Box<RetainedGeneration>),
    Released(GenerationId),
}
impl ArtifactSession {
    pub fn begin(&mut self, capacity: &HostArtifactCapacity) -> Result<(), ArtifactError> {
        match &self.0 {
            SessionState::Empty | SessionState::Released(_) => {
                let reservation = capacity.reserve(0)?;
                self.0 = SessionState::Generating(reservation);
                Ok(())
            }
            SessionState::Generating(_) | SessionState::Ready(_) => {
                Err(ArtifactError::ActiveGeneration)
            }
        }
    }
    pub fn fail(&mut self) {
        if matches!(self.0, SessionState::Generating(_)) {
            self.0 = SessionState::Empty;
        }
    }
    pub fn retain(
        &mut self,
        prepared: PreparedArtifacts,
        context: GenerationContext,
        diagnostics: ArtifactDiagnostics,
        capacity: &HostArtifactCapacity,
    ) -> Result<GeneratedArtifactManifest, ArtifactError> {
        if !matches!(self.0, SessionState::Generating(_)) {
            return Err(ArtifactError::ActiveGeneration);
        }
        // Every failure after begin restores Empty. Reservation is RAII-owned
        // locally until complete encoded envelope validation succeeds.
        let SessionState::Generating(mut reservation) = std::mem::take(&mut self.0) else {
            unreachable!()
        };
        // Capacity identity is captured by begin, never selected again after an
        // invocation. The argument is checked to reject accidental cross-host use.
        if !Arc::ptr_eq(&reservation.capacity.0, &capacity.0) {
            return Err(ArtifactError::Capacity);
        }
        reservation.reserve_bytes(prepared.decoded_length())?;
        let set = prepared.decode()?;
        let manifest = GeneratedArtifactManifest {
            status: ReadyStatus::Ready,
            profile: ProfileName,
            contract_version: ArtifactContractVersion,
            session_id: context.session,
            provider_id: context.provider,
            generation_id: GenerationId::fresh(),
            producer: context.producer,
            target: context.target,
            ir_version: context.ir_version,
            artifacts: set
                .artifacts
                .iter()
                .map(|artifact| ArtifactDescriptor {
                    id: ArtifactId::fresh(),
                    path: artifact.path.clone(),
                    kind: artifact.content.kind(),
                    byte_length: artifact.content.bytes().len(),
                    sha256: artifact.digest.clone(),
                })
                .collect(),
            diagnostics,
        };
        // A random-source collision must fail closed, never expose ambiguous
        // handles or rely on statistical uniqueness as a domain invariant.
        let ids: std::collections::BTreeSet<_> = manifest
            .artifacts
            .iter()
            .map(|artifact| &artifact.id)
            .collect();
        if ids.len() != manifest.artifacts.len() {
            return Err(ArtifactError::InvalidIdentity);
        }
        check_reply_budget(&manifest)?;
        self.0 = SessionState::Ready(Box::new(RetainedGeneration {
            manifest: manifest.clone(),
            set,
            _reservation: reservation,
        }));
        Ok(manifest)
    }
    pub fn read(
        &self,
        generation: &GenerationId,
        artifact: &ArtifactId,
        offset: ByteOffset,
        limit: ChunkLimit,
    ) -> Result<ArtifactChunk, ArtifactError> {
        let SessionState::Ready(ready) = &self.0 else {
            return Err(ArtifactError::UnknownHandle);
        };
        if &ready.manifest.generation_id != generation {
            return Err(ArtifactError::UnknownHandle);
        }
        let (_, file) = ready
            .manifest
            .artifacts
            .iter()
            .zip(&ready.set.artifacts)
            .find(|(descriptor, _)| &descriptor.id == artifact)
            .ok_or(ArtifactError::UnknownHandle)?;
        let bytes = file.content.bytes();
        if offset.get() > bytes.len() {
            return Err(ArtifactError::InvalidRange);
        }
        let end = bytes.len().min(offset.get() + limit.get());
        Ok(ArtifactChunk {
            profile: ProfileName,
            contract_version: ArtifactContractVersion,
            generation_id: generation.clone(),
            artifact_id: artifact.clone(),
            offset,
            next_offset: ByteOffset::new(end)?,
            content: STANDARD.encode(&bytes[offset.get()..end]),
        })
    }
    pub fn release(&mut self, generation: &GenerationId) -> Result<(), ArtifactError> {
        match &self.0 {
            SessionState::Ready(ready) if &ready.manifest.generation_id == generation => {
                self.0 = SessionState::Released(generation.clone());
                Ok(())
            }
            SessionState::Released(prior) if prior == generation => Ok(()),
            _ => Err(ArtifactError::UnknownHandle),
        }
    }
}

/// Measure the complete compact JSON-RPC success envelope with the largest
/// permitted request ID. This writer never allocates an oversized encoding.
pub fn check_reply_budget(result: &impl Serialize) -> Result<(), ArtifactError> {
    #[derive(Serialize)]
    struct Envelope<'a, T> {
        jsonrpc: &'static str,
        id: u64,
        result: &'a T,
    }
    struct BudgetWriter(usize);
    impl io::Write for BudgetWriter {
        fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
            self.0 = self
                .0
                .checked_add(bytes.len())
                .ok_or_else(|| io::Error::other("artifact reply budget"))?;
            if self.0 > MAX_REPLY_BYTES {
                return Err(io::Error::other("artifact reply budget"));
            }
            Ok(bytes.len())
        }
        fn flush(&mut self) -> io::Result<()> {
            Ok(())
        }
    }
    serde_json::to_writer(
        BudgetWriter(0),
        &Envelope {
            jsonrpc: "2.0",
            id: u64::MAX,
            result,
        },
    )
    .map_err(|_| ArtifactError::ReplyLimit)
}
