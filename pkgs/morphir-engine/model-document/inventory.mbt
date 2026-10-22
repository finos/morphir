///|
/// Numeric release metadata from the model-originals IR-header contract.
/// This is not a SemVer parser or a semantic-format support claim. The external
/// boundary validates the original spelling with its existing SemVer library.
pub struct OriginalRelease {
  priv major : UInt32
  priv minor : UInt32
  priv patch : UInt32
} derive(Eq, Debug)

///|
pub extend OriginalRelease with Eq::{equal, not_equal}

///|
pub extend OriginalRelease with @debug.Debug::{to_repr}

///|
pub fn OriginalRelease::new(
  major : UInt32,
  minor : UInt32,
  patch : UInt32,
) -> OriginalRelease {
  { major, minor, patch, }
}

///|
pub fn OriginalRelease::to_release_string(self : OriginalRelease) -> String {
  "\{self.major}.\{self.minor}.\{self.patch}"
}

///|
pub(all) enum OriginalSourceHeader {
  NotReported
  Reported(OriginalRelease)
} derive(Eq, Debug)

///|
pub extend OriginalSourceHeader with Eq::{equal, not_equal}

///|
pub extend OriginalSourceHeader with @debug.Debug::{to_repr}

///|
/// Sole private byte storage shared by local trees and connected inventories.
priv struct InventoryStorage {
  files : Map[String, Bytes]
  directories : Array[String]
} derive(Eq, Debug)

///|
fn InventoryStorage::capture(
  files : Map[String, Bytes],
  directories : Array[String],
  profile : InventoryPathProfile,
) -> InventoryStorage raise DocumentError {
  if directories.length() > 100064 ||
    files.length() > 100064 - directories.length() ||
    (profile is Local && (files.length() > 4096 || directories.length() > 4096)) {
    raise TooLarge
  }
  let paths = files.keys().collect()
  validate_inventory_paths(paths, directories, profile~)
  let byte_limit = if profile is Connected { 67108864 } else { 16777216 }
  let mut bytes = 0
  for path in paths {
    if files[path].length() > byte_limit - bytes {
      raise TooLarge
    }
    bytes += files[path].length()
  }
  let owned : Map[String, Bytes] = Map([])
  for path in paths {
    owned[path] = copy_bytes(files[path])
  }
  let directories = directories.copy()
  directories.sort()
  { files: owned, directories, }
}

///|
fn InventoryStorage::copy_files(self : InventoryStorage) -> Map[String, Bytes] {
  self.files.map(fn(_, bytes) { copy_bytes(bytes) })
}

///|
fn InventoryStorage::directory_paths(self : InventoryStorage) -> Array[String] {
  self.directories.copy()
}

///|
fn InventoryStorage::download_file(
  self : InventoryStorage,
  path : String,
) -> Json raise DocumentError {
  guard self.files.get(path) is Some(bytes) else { raise InvalidFilename }
  {
    "path": path,
    "content": @base64.encode(bytes[:]),
    "binary": true,
    "encoding": "base64",
  }
}

///|
fn InventoryStorage::download(self : InventoryStorage) -> Json {
  let paths = self.files.keys().collect()
  paths.sort()
  {
    "files": paths.map(path => {
      (
        {
          "path": path,
          "content": @base64.encode(self.files[path][:]),
          "binary": true,
          "encoding": "base64",
        } : Json)
    }),
    "directories": self.directory_paths(),
  }
}

///|
/// Exact originals retained without semantic inspection or typed adoption.
/// Construction checks storage shape and bounds, not protocol verification,
/// source authority, accepted release or product opening currentness.
pub struct OriginalInventory {
  source_header : OriginalSourceHeader
  priv storage : InventoryStorage
  priv entries : Array[OriginalInventoryEntry]
} derive(Eq, Debug)

///|
pub extend OriginalInventory with Eq::{equal, not_equal}

///|
pub extend OriginalInventory with @debug.Debug::{to_repr}

///|
/// The actual shared receiver must validate the complete transfer before the
/// application publishes this storage. Its Unicode/protocol checks stay there.
pub fn OriginalInventory::from_connected(
  files : Map[String, Bytes],
  directories : Array[String],
  source_header : OriginalSourceHeader,
) -> OriginalInventory raise DocumentError {
  if files.is_empty() && directories.is_empty() {
    raise InvalidReply
  }
  let storage = InventoryStorage::capture(files, directories, Connected)
  let paths = storage.files.keys().collect()
  paths.sort()
  {
    source_header,
    storage,
    // Capture has validated these paths. Index once; browsing never sorts,
    // reparses the whole inventory or copies any original byte buffers.
    entries: paths.map(path => OriginalInventoryEntry::File(OriginalPath(path))) +
    storage.directories.map(path => {
      OriginalInventoryEntry::Directory(OriginalPath(path))
    }),
  }
}

///|
pub(all) enum OriginalInventoryEntry {
  File(OriginalPath)
  Directory(OriginalPath)
} derive(Eq, Debug)

///|
pub extend OriginalInventoryEntry with Eq::{equal, not_equal}

///|
pub extend OriginalInventoryEntry with @debug.Debug::{to_repr}

///|
pub fn OriginalInventory::entry_count(self : OriginalInventory) -> Int32 {
  self.entries.length()
}

///|
/// Readonly length metadata for preflight; this does not copy or expose bytes.
pub fn OriginalInventory::file_byte_length(
  self : OriginalInventory,
  path : OriginalPath,
) -> UInt64? {
  self.storage.files
  .get(path.to_string())
  .map(bytes => bytes.length().to_uint64())
}

///|
/// Constant-time access to the immutable index; an entry grants no download authority.
pub fn OriginalInventory::entry(
  self : OriginalInventory,
  index : Int32,
) -> OriginalInventoryEntry? {
  self.entries.get(index)
}

///|
pub fn OriginalInventory::copy_files(
  self : OriginalInventory,
) -> Map[String, Bytes] {
  self.storage.copy_files()
}

///|
/// List retained files without copying their original byte buffers.
pub fn OriginalInventory::file_paths(self : OriginalInventory) -> Array[String] {
  let paths = self.storage.files.keys().collect()
  paths.sort()
  paths
}

///|
pub fn OriginalInventory::directory_paths(
  self : OriginalInventory,
) -> Array[String] {
  self.storage.directory_paths()
}

///|
pub fn OriginalInventory::download_file(
  self : OriginalInventory,
  path : OriginalPath,
) -> Json raise DocumentError {
  self.storage.download_file(path.to_string())
}

///|
/// Existing archive adapter representation, from the same retained byte owner.
pub fn OriginalInventory::download(self : OriginalInventory) -> Json {
  self.storage.download()
}

///|
/// Validated aggregate metadata from this inventory, without byte-buffer copies.
/// No constructor or raw backing is exposed across the application boundary.
pub struct OriginalArchiveSizes {
  priv count : UInt64
  priv raw : UInt64
  priv names : UInt64
}

///|
pub fn OriginalArchiveSizes::entry_count(self : OriginalArchiveSizes) -> UInt64 {
  self.count
}

///|
pub fn OriginalArchiveSizes::file_bytes(self : OriginalArchiveSizes) -> UInt64 {
  self.raw
}

///|
pub fn OriginalArchiveSizes::archive_name_bytes(
  self : OriginalArchiveSizes,
) -> UInt64 {
  self.names
}

///|
fn archive_size_add(
  left : UInt64,
  right : UInt64,
) -> UInt64 raise DocumentError {
  if right > 18446744073709551615UL - left {
    raise TooLarge
  }
  left + right
}

///|
fn archive_utf8_size(path : String) -> UInt64 raise DocumentError {
  let units = path.code_units()
  let mut result = 0UL
  let mut index = 0
  while index < units.length() {
    let unit = units[index].to_int()
    let width = if unit >= 0xD800 && unit <= 0xDBFF {
      index += 1
      if index >= units.length() ||
        units[index].to_int() < 0xDC00 ||
        units[index].to_int() > 0xDFFF {
        raise InvalidFilename
      }
      4UL
    } else if unit >= 0xDC00 && unit <= 0xDFFF {
      raise InvalidFilename
    } else if unit < 0x80 {
      1UL
    } else if unit < 0x800 {
      2UL
    } else {
      3UL
    }
    result = archive_size_add(result, width)
    index += 1
  }
  result
}

///|
/// Scalar-only pass over SAME private storage. Directory slash bytes are emitted
/// by the archive, while implicit ancestors contribute neither entry nor name.
pub fn OriginalInventory::archive_sizes(
  self : OriginalInventory,
) -> OriginalArchiveSizes raise DocumentError {
  let mut count = 0UL
  let mut raw = 0UL
  let mut names = 0UL
  for path, bytes in self.storage.files {
    count = archive_size_add(count, 1UL)
    raw = archive_size_add(raw, bytes.length().to_uint64())
    names = archive_size_add(names, archive_utf8_size(path))
  }
  for path in self.storage.directories {
    count = archive_size_add(count, 1UL)
    names = archive_size_add(
      names,
      archive_size_add(archive_utf8_size(path), 1UL),
    )
  }
  { count, raw, names, }
}
