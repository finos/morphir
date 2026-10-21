//! Borrowed ZIP64 STORE facts only. No extraction, allocation or live authority.
//! The caller funds fixed scratch before this call and retains the actual bytes.
use super::{CompareOwner, CompareResource, ObservationError};
use std::cmp::Ordering;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum ZipStoreFault {
    End,
    Offsets,
    Header,
    Descriptor,
    Crc,
    Duplicate,
    Unsupported,
    Scratch,
    Work(ObservationError),
}
type Result<T> = std::result::Result<T, ZipStoreFault>;
#[derive(Clone, Copy)]
enum Kind {
    File,
    Directory,
}
#[derive(Clone, Copy)]
struct Member<'bytes> {
    name: &'bytes str,
    bytes: &'bytes [u8],
    start: usize,
    end: usize,
    kind: Kind,
}
pub(super) struct EntrySlot<'bytes>(Option<Member<'bytes>>);
impl EntrySlot<'_> {
    pub(super) const fn vacant() -> Self {
        Self(None)
    }
    #[cfg(test)]
    pub(super) fn is_vacant(&self) -> bool {
        self.0.is_none()
    }
}
pub(super) enum ZipStoreMember<'bytes> {
    File {
        name: &'bytes str,
        bytes: &'bytes [u8],
    },
    Directory {
        name: &'bytes str,
    },
}
pub(super) struct ZipStore<'bytes, 'scratch> {
    entries: &'scratch [EntrySlot<'bytes>],
}
impl std::fmt::Debug for ZipStore<'_, '_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ZipStore")
            .field("members", &self.entries.len())
            .finish()
    }
}
impl<'bytes> ZipStore<'bytes, '_> {
    pub(super) fn len(&self) -> usize {
        self.entries.len()
    }
    pub(super) fn members(&self) -> impl ExactSizeIterator<Item = ZipStoreMember<'bytes>> + '_ {
        self.entries.iter().map(|slot| {
            let member = slot.0.as_ref().expect("private validated occupied prefix");
            match member.kind {
                Kind::File => ZipStoreMember::File {
                    name: member.name,
                    bytes: member.bytes,
                },
                Kind::Directory => ZipStoreMember::Directory { name: member.name },
            }
        })
    }
}
struct Directory {
    offset: usize,
    end: usize,
    count: usize,
}
struct Reader<'bytes, 'owner> {
    actual: &'bytes [u8],
    owner: &'owner mut CompareOwner,
}
impl<'bytes> Reader<'bytes, '_> {
    fn charge(&mut self, resource: CompareResource, count: usize) -> Result<()> {
        self.owner
            .charge(resource, count)
            .map_err(ZipStoreFault::Work)
    }
    fn visit(&mut self) -> Result<()> {
        self.charge(CompareResource::StructuralVisits, 1)
    }
    fn check(&mut self, condition: impl FnOnce() -> bool, fault: ZipStoreFault) -> Result<()> {
        self.charge(CompareResource::Checks, 1)?;
        if condition() { Ok(()) } else { Err(fault) }
    }
    fn span(&mut self, at: usize, length: usize, fault: ZipStoreFault) -> Result<&'bytes [u8]> {
        self.visit()?;
        self.charge(CompareResource::Checks, 1)?;
        let remaining = self.actual.len().checked_sub(at).ok_or(fault)?;
        if length > remaining {
            return Err(fault);
        }
        Ok(&self.actual[at..at + length])
    }
    fn u16(&mut self, at: usize, fault: ZipStoreFault) -> Result<u16> {
        self.charge(CompareResource::ComparisonBytes, 2)?;
        let b = self.span(at, 2, fault)?;
        Ok(u16::from_le_bytes([b[0], b[1]]))
    }
    fn u32(&mut self, at: usize, fault: ZipStoreFault) -> Result<u32> {
        self.charge(CompareResource::ComparisonBytes, 4)?;
        let b = self.span(at, 4, fault)?;
        Ok(u32::from_le_bytes([b[0], b[1], b[2], b[3]]))
    }
    fn u64(&mut self, at: usize, fault: ZipStoreFault) -> Result<u64> {
        self.charge(CompareResource::ComparisonBytes, 8)?;
        let b = self.span(at, 8, fault)?;
        Ok(u64::from_le_bytes(
            b.try_into().expect("checked fixed eight-byte span"),
        ))
    }
    fn expect16(&mut self, at: usize, expected: u16, fault: ZipStoreFault) -> Result<()> {
        self.charge(CompareResource::Checks, 1)?;
        if self.u16(at, fault)? == expected {
            Ok(())
        } else {
            Err(fault)
        }
    }
    fn expect32(&mut self, at: usize, expected: u32, fault: ZipStoreFault) -> Result<()> {
        self.charge(CompareResource::Checks, 1)?;
        if self.u32(at, fault)? == expected {
            Ok(())
        } else {
            Err(fault)
        }
    }
    fn expect64(&mut self, at: usize, expected: u64, fault: ZipStoreFault) -> Result<()> {
        self.charge(CompareResource::Checks, 1)?;
        if self.u64(at, fault)? == expected {
            Ok(())
        } else {
            Err(fault)
        }
    }
    fn offset(&mut self, value: u64, fault: ZipStoreFault) -> Result<usize> {
        self.visit()?;
        let converted = usize::try_from(value).map_err(|_| fault)?;
        self.check(|| converted <= self.actual.len(), fault)?;
        Ok(converted)
    }
    fn end_of(&mut self, at: usize, length: usize, fault: ZipStoreFault) -> Result<usize> {
        self.span(at, length, fault)?;
        Ok(at + length)
    }
    fn same_bytes(&mut self, a: &[u8], b: &[u8], fault: ZipStoreFault) -> Result<()> {
        self.charge(CompareResource::Checks, 1)?;
        let Some(total) = a.len().checked_add(b.len()) else {
            return self
                .owner
                .refuse(ObservationError::SizeOverflow)
                .map_err(ZipStoreFault::Work);
        };
        self.charge(CompareResource::ComparisonBytes, total)?;
        if a == b { Ok(()) } else { Err(fault) }
    }
    fn directory(&mut self) -> Result<Directory> {
        use ZipStoreFault::End;
        self.visit()?;
        let legacy = self.actual.len().checked_sub(22).ok_or(End)?;
        let locator = legacy.checked_sub(20).ok_or(End)?;
        self.expect32(legacy, 0x0605_4b50, End)?;
        self.expect16(legacy + 20, 0, End)?;
        for field in [4, 6, 8, 10] {
            self.expect16(legacy + field, u16::MAX, End)?;
        }
        self.expect32(legacy + 12, u32::MAX, End)?;
        self.expect32(legacy + 16, u32::MAX, End)?;
        self.expect32(locator, 0x0706_4b50, End)?;
        self.expect32(locator + 4, 0, End)?;
        self.expect32(locator + 16, 1, End)?;
        let raw = self.u64(locator + 8, End)?;
        let end = self.offset(raw, End)?;
        let record_end = self.end_of(end, 56, End)?;
        self.check(|| record_end == locator, End)?;
        self.expect32(end, 0x0606_4b50, End)?;
        self.expect64(end + 4, 44, End)?;
        self.expect16(end + 12, 45, End)?;
        self.expect16(end + 14, 45, End)?;
        self.expect32(end + 16, 0, End)?;
        self.expect32(end + 20, 0, End)?;
        let per_disk = self.u64(end + 24, End)?;
        let count = self.u64(end + 32, End)?;
        self.check(|| count == per_disk, End)?;
        let length = self.u64(end + 40, End)?;
        let offset = self.u64(end + 48, End)?;
        let offset = self.offset(offset, End)?;
        let length = self.offset(length, End)?;
        let central_end = self.end_of(offset, length, End)?;
        self.check(|| central_end == end, End)?;
        Ok(Directory {
            offset,
            end: central_end,
            count: usize::try_from(count).map_err(|_| End)?,
        })
    }
    fn size_extra(&mut self, at: usize, size: usize) -> Result<()> {
        self.expect16(at, 1, ZipStoreFault::Unsupported)?;
        self.expect16(at + 2, 16, ZipStoreFault::Header)?;
        self.expect64(at + 4, size as u64, ZipStoreFault::Header)?;
        self.expect64(at + 12, size as u64, ZipStoreFault::Header)
    }
    fn member(
        &mut self,
        at: usize,
        central_end: usize,
        local_end: usize,
    ) -> Result<(Member<'bytes>, usize)> {
        use ZipStoreFault::{Header, Offsets, Unsupported};
        let fixed_end = self.end_of(at, 46, Header)?;
        self.check(|| fixed_end <= central_end, Header)?;
        self.expect32(at, 0x0201_4b50, Header)?;
        let made_by = self.u16(at + 4, Header)?;
        let version = self.u16(at + 6, Header)?;
        let flags = self.u16(at + 8, Header)?;
        let method = self.u16(at + 10, Header)?;
        let time = self.u16(at + 12, Header)?;
        let date = self.u16(at + 14, Header)?;
        let crc = self.u32(at + 16, Header)?;
        self.expect32(at + 20, u32::MAX, Header)?;
        self.expect32(at + 24, u32::MAX, Header)?;
        let name_length = usize::from(self.u16(at + 28, Header)?);
        self.expect16(at + 30, 20, Unsupported)?;
        self.expect16(at + 32, 0, Unsupported)?;
        self.expect16(at + 34, 0, Unsupported)?;
        let attributes = self.u32(at + 38, Header)?;
        let offset = self.u32(at + 42, Offsets)?;
        let start = self.offset(u64::from(offset), Offsets)?;
        let name_end = self.end_of(fixed_end, name_length, Header)?;
        let next = self.end_of(name_end, 20, Header)?;
        self.check(|| next <= central_end, Header)?;
        self.expect16(name_end, 1, Unsupported)?;
        self.expect16(name_end + 2, 16, Header)?;
        let raw_size = self.u64(name_end + 4, Offsets)?;
        let size = self.offset(raw_size, Offsets)?;
        self.expect64(name_end + 12, raw_size, Header)?;
        let name_bytes = self.span(fixed_end, name_length, Header)?;
        self.charge(CompareResource::ComparisonBytes, name_length)?;
        let name = std::str::from_utf8(name_bytes).map_err(|_| Header)?;
        self.check(|| !name.is_empty(), Header)?;
        let local_fixed_end = self.end_of(start, 30, Offsets)?;
        self.check(|| local_fixed_end <= local_end, Offsets)?;
        self.expect32(start, 0x0403_4b50, Header)?;
        self.expect16(start + 4, version, Header)?;
        self.expect16(start + 6, flags, Header)?;
        self.expect16(start + 8, method, Header)?;
        self.expect16(start + 10, time, Header)?;
        self.expect16(start + 12, date, Header)?;
        self.expect32(start + 14, 0, Header)?;
        self.expect32(start + 18, u32::MAX, Header)?;
        self.expect32(start + 22, u32::MAX, Header)?;
        self.expect16(start + 26, name_length as u16, Header)?;
        self.expect16(start + 28, 20, Unsupported)?;
        self.check(|| version == 45, Unsupported)?;
        self.check(|| flags == 0x0808, Unsupported)?;
        self.check(|| method == 0, Unsupported)?;
        let local_name_end = self.end_of(local_fixed_end, name_length, Offsets)?;
        let local_name = self.span(local_fixed_end, name_length, Offsets)?;
        self.same_bytes(local_name, name_bytes, Header)?;
        let data_start = self.end_of(local_name_end, 20, Offsets)?;
        self.size_extra(local_name_end, size)?;
        let data_end = self.end_of(data_start, size, Offsets)?;
        let member_end = self.end_of(data_end, 24, Offsets)?;
        self.check(|| member_end <= local_end, Offsets)?;
        self.charge(CompareResource::ComparisonBytes, 1)?;
        let kind = if name.ends_with('/') {
            Kind::Directory
        } else {
            Kind::File
        };
        let os = made_by >> 8;
        self.check(|| os == 0 || os == 3, Unsupported)?;
        let unix_kind = if os == 3 {
            (attributes >> 16) & 0o170000
        } else {
            0
        };
        self.check(|| matches!(unix_kind, 0 | 0o100000 | 0o040000), Unsupported)?;
        self.check(
            || attributes & 0x10 == 0 || matches!(kind, Kind::Directory),
            Header,
        )?;
        self.check(
            || unix_kind != 0o100000 || matches!(kind, Kind::File),
            Header,
        )?;
        self.check(
            || unix_kind != 0o040000 || matches!(kind, Kind::Directory),
            Header,
        )?;
        self.check(|| !matches!(kind, Kind::Directory) || size == 0, Header)?;
        self.expect32(data_end, 0x0807_4b50, ZipStoreFault::Descriptor)?;
        self.expect32(data_end + 4, crc, ZipStoreFault::Descriptor)?;
        self.expect64(data_end + 8, raw_size, ZipStoreFault::Descriptor)?;
        self.expect64(data_end + 16, raw_size, ZipStoreFault::Descriptor)?;
        let data = self.span(data_start, size, Offsets)?;
        self.charge(CompareResource::Checks, 1)?;
        self.charge(CompareResource::ComparisonBytes, size)?;
        let mut calculated = flate2::Crc::new();
        calculated.update(data);
        if calculated.sum() != crc {
            return Err(ZipStoreFault::Crc);
        }
        Ok((
            Member {
                name,
                bytes: data,
                start,
                end: member_end,
                kind,
            },
            next,
        ))
    }
    fn metadata<'a>(&mut self, slot: &'a EntrySlot<'bytes>) -> Result<&'a Member<'bytes>> {
        self.visit()?;
        slot.0.as_ref().ok_or(ZipStoreFault::Scratch)
    }
    fn compare(
        &mut self,
        a: &EntrySlot<'bytes>,
        b: &EntrySlot<'bytes>,
        key: SortKey,
    ) -> Result<Ordering> {
        let a = self.metadata(a)?;
        let b = self.metadata(b)?;
        self.charge(CompareResource::Checks, 1)?;
        match key {
            SortKey::Offset => Ok(a.start.cmp(&b.start)),
            SortKey::Name => {
                let Some(bytes) = a.name.len().checked_add(b.name.len()) else {
                    return self
                        .owner
                        .refuse(ObservationError::SizeOverflow)
                        .map_err(ZipStoreFault::Work);
                };
                self.charge(CompareResource::ComparisonBytes, bytes)?;
                Ok(a.name.as_bytes().cmp(b.name.as_bytes()))
            }
        }
    }
    fn swap(&mut self, slots: &mut [EntrySlot<'bytes>], a: usize, b: usize) -> Result<()> {
        self.charge(CompareResource::StructuralVisits, 2)?;
        slots.swap(a, b);
        Ok(())
    }
    fn sift(
        &mut self,
        slots: &mut [EntrySlot<'bytes>],
        mut root: usize,
        end: usize,
        key: SortKey,
    ) -> Result<()> {
        loop {
            self.visit()?;
            let child = root
                .checked_mul(2)
                .and_then(|n| n.checked_add(1))
                .ok_or(ZipStoreFault::Scratch)?;
            if child >= end {
                return Ok(());
            }
            let mut greatest = child;
            if child + 1 < end
                && self.compare(&slots[child], &slots[child + 1], key)? == Ordering::Less
            {
                greatest = child + 1;
            }
            if self.compare(&slots[root], &slots[greatest], key)? != Ordering::Less {
                return Ok(());
            }
            self.swap(slots, root, greatest)?;
            root = greatest;
        }
    }
    fn sort(&mut self, slots: &mut [EntrySlot<'bytes>], key: SortKey) -> Result<()> {
        for start in (0..slots.len() / 2).rev() {
            self.sift(slots, start, slots.len(), key)?;
        }
        for end in (1..slots.len()).rev() {
            self.swap(slots, 0, end)?;
            self.sift(slots, 0, end, key)?;
        }
        Ok(())
    }
}
#[derive(Clone, Copy)]
enum SortKey {
    Offset,
    Name,
}
pub(super) fn read<'bytes, 'scratch>(
    actual: &'bytes [u8],
    scratch: &'scratch mut [EntrySlot<'bytes>],
    owner: &mut CompareOwner,
) -> Result<ZipStore<'bytes, 'scratch>> {
    owner.ready().map_err(ZipStoreFault::Work)?;
    let mut reader = Reader { actual, owner };
    let directory = reader.directory()?;
    reader.check(
        || scratch.len() <= 100064 && directory.count <= scratch.len(),
        ZipStoreFault::Scratch,
    )?;
    for slot in scratch.iter() {
        reader.visit()?;
        reader.check(|| slot.0.is_none(), ZipStoreFault::Scratch)?;
    }
    let slots = &mut scratch[..directory.count];
    let mut at = directory.offset;
    for slot in slots.iter_mut() {
        reader.visit()?;
        let (member, next) = reader.member(at, directory.end, directory.offset)?;
        reader.visit()?; // Caller-funded metadata destination, before move.
        slot.0 = Some(member);
        at = next;
    }
    reader.check(|| at == directory.end, ZipStoreFault::End)?;
    reader.sort(slots, SortKey::Offset)?;
    let mut end = 0;
    for slot in slots.iter() {
        let metadata = reader.metadata(slot)?;
        reader.check(|| metadata.start == end, ZipStoreFault::Offsets)?;
        end = metadata.end;
    }
    reader.check(|| end == directory.offset, ZipStoreFault::Offsets)?;
    reader.sort(slots, SortKey::Name)?;
    for pair in slots.windows(2) {
        if reader.compare(&pair[0], &pair[1], SortKey::Name)? == Ordering::Equal {
            return Err(ZipStoreFault::Duplicate);
        }
    }
    Ok(ZipStore { entries: slots })
}
#[cfg(test)]
mod tests;
