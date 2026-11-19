///|
/// A pinned native directory. Close it exactly once while its paths are in use.
pub struct BoundedDirectory {
  priv fd : Int32
}

///|
#borrow(path)
extern "C" fn bounded_open(parent : Int32, path : Bytes) -> Int32 = "morphir_bounded_directory_open"

///|
pub fn BoundedDirectory::open(path : String) -> BoundedDirectory raise {
  guard !path.contains_char('\u0000') else {
    raise IOError("bounded.invalid_path")
  }
  let fd = bounded_open(-1, cstring(path))
  guard fd >= 0 else { raise IOError("bounded.open_directory: " + path) }
  { fd, }
}

///|
pub fn BoundedDirectory::close(self : BoundedDirectory) -> Unit {
  ignore(file_close(self.fd))
}

///|
fn bounded_name(name : String) -> Bytes raise {
  guard name != "" &&
    name != "." &&
    name != ".." &&
    !name.contains("/") &&
    !name.contains("\\") &&
    !name.contains_char('\u0000') else {
    raise IOError("bounded.invalid_component: " + name)
  }
  cstring(name)
}

///|
pub fn BoundedDirectory::child(
  self : BoundedDirectory,
  name : String,
) -> BoundedDirectory raise {
  let fd = bounded_open(self.fd, bounded_name(name))
  guard fd >= 0 else { raise IOError("bounded.open_directory: " + name) }
  { fd, }
}

///|
extern "C" fn bounded_list(
  fd : Int32,
  limit : Int32,
  interrupted : FuncRef[() -> Bool],
) -> Bytes = "morphir_bounded_directory_list"

///|
pub fn BoundedDirectory::list(
  self : BoundedDirectory,
  limit : Int32,
) -> Array[String] raise {
  decode_directory_listing(
    bounded_list(self.fd, limit, fn() { interruption_requested() }),
    limit,
  )
}

///|
#borrow(name)
extern "C" fn bounded_stamp(fd : Int32, name : Bytes) -> Bytes = "morphir_bounded_directory_stamp"

///|
/// Metadata identity and change stamp, without following a child symbolic link.
pub fn BoundedDirectory::stamp(
  self : BoundedDirectory,
  name? : String,
) -> String raise {
  let native_name = match name {
    Some(name) => bounded_name(name)
    None => b"\x00"
  }
  let result = bounded_stamp(self.fd, native_name)
  guard result[0] == 0 else { raise IOError("bounded.source_changed") }
  @utf8.decode(result[1:])
}

///|
#borrow(name)
extern "C" fn bounded_read(fd : Int32, name : Bytes, limit : Int32) -> Bytes = "morphir_bounded_directory_read"

///|
pub fn BoundedDirectory::read(
  self : BoundedDirectory,
  name : String,
  limit : Int32,
) -> Bytes raise {
  let result = bounded_read(self.fd, bounded_name(name), limit)
  match result[0] {
    b'\x00' => result[1:].to_owned()
    b'\x02' => raise IOError("bounded.document_limit: " + name)
    b'\x03' => raise IOError("bounded.source_changed: " + name)
    _ => raise IOError("bounded.read_document: " + name)
  }
}

///|
extern "C" fn bounded_owned(fd : Int32) -> Bool = "morphir_bounded_directory_owned"

///|
pub fn BoundedDirectory::require_owned(self : BoundedDirectory) -> Unit raise {
  guard bounded_owned(self.fd) else {
    raise IOError("bounded.output_parent_not_owned")
  }
}

///|
#borrow(name)
extern "C" fn bounded_mkdir(fd : Int32, name : Bytes) -> Int32 = "morphir_bounded_directory_mkdir"

///|
pub fn BoundedDirectory::mkdir(
  self : BoundedDirectory,
  name : String,
) -> Unit raise {
  check(bounded_mkdir(self.fd, bounded_name(name)), "bounded.mkdir: " + name)
}

///|
#borrow(name)
extern "C" fn bounded_remove(
  fd : Int32,
  name : Bytes,
  directory : Bool,
) -> Int32 = "morphir_bounded_directory_remove"

///|
pub fn BoundedDirectory::remove(
  self : BoundedDirectory,
  name : String,
  directory~ : Bool,
) -> Unit raise {
  check(
    bounded_remove(self.fd, bounded_name(name), directory),
    "bounded.remove: " + name,
  )
}

///|
#borrow(name, bytes)
extern "C" fn bounded_write(
  fd : Int32,
  name : Bytes,
  offset : Int32,
  create : Bool,
  bytes : Bytes,
  size : Int32,
) -> Int32 = "morphir_bounded_directory_write"

///|
pub fn BoundedDirectory::write(
  self : BoundedDirectory,
  name : String,
  bytes : Bytes,
  offset~ : Int32,
  create~ : Bool,
) -> Unit raise {
  check(
    bounded_write(
      self.fd,
      bounded_name(name),
      offset,
      create,
      bytes,
      bytes.length(),
    ),
    "bounded.write: " + name,
  )
}

///|
#borrow(parent, from, to)
extern "C" fn bounded_publish(
  fd : Int32,
  parent : Bytes,
  stage : Int32,
  from : Bytes,
  to : Bytes,
) -> Int32 = "morphir_bounded_directory_publish"

///|
pub fn BoundedDirectory::publish(
  self : BoundedDirectory,
  parent : String,
  stage : BoundedDirectory,
  from : String,
  to : String,
) -> Unit raise {
  guard !parent.contains_char('\u0000') else {
    raise IOError("bounded.invalid_path")
  }
  check(
    bounded_publish(
      self.fd,
      cstring(parent),
      stage.fd,
      bounded_name(from),
      bounded_name(to),
    ),
    "bounded.publish: " + to,
  )
}

///|
#borrow(name)
extern "C" fn bounded_discard(
  parent : Int32,
  stage : Int32,
  name : Bytes,
) -> Int32 = "morphir_bounded_directory_discard"

///|
pub fn BoundedDirectory::discard(
  self : BoundedDirectory,
  stage : BoundedDirectory,
  name : String,
) -> Unit raise {
  match bounded_discard(self.fd, stage.fd, bounded_name(name)) {
    0 => ()
    -2 => raise IOError("bounded.cleanup_limit: " + name)
    _ => raise IOError("bounded.cleanup_unconfirmed: " + name)
  }
}

///|
extern "C" fn bounded_outside(fd : Int32, source : Int32) -> Bool = "morphir_bounded_directory_outside"

///|
pub fn BoundedDirectory::require_outside(
  self : BoundedDirectory,
  source : BoundedDirectory,
) -> Unit raise {
  guard bounded_outside(self.fd, source.fd) else {
    raise IOError("bounded.output_parent_inside_source")
  }
}

///|
#borrow(name)
extern "C" fn bounded_file_open(
  fd : Int32,
  name : Bytes,
  limit : Int32,
) -> Int32 = "morphir_bounded_file_open"

///|
/// Read a pinned regular entry in chunks and refuse a replacement or mutation.
pub fn BoundedDirectory::scan(
  self : BoundedDirectory,
  name : String,
  size : Int32,
  check : () -> Unit raise,
  consume : (Bytes) -> Unit,
) -> Unit raise {
  check()
  let expected = self.stamp(name~)
  let fd = bounded_file_open(self.fd, bounded_name(name), size)
  guard fd >= 0 else { raise IOError("bounded.stage_read: " + name) }
  defer ignore(file_close(fd))
  let entry = BoundedDirectory::{ fd, }
  guard entry.stamp() == expected else {
    raise IOError("bounded.stage_changed: " + name)
  }
  let buffer = FixedArray::make(65536, b'\x00')
  let mut count = 0
  while true {
    check()
    let capacity = if size - count >= 65536 { 65536 } else { size - count + 1 }
    let read = file_read(fd, buffer, capacity)
    guard read >= 0 && read <= size - count else {
      raise IOError("bounded.stage_read: " + name)
    }
    if read == 0 {
      break
    }
    count += read
    consume(Bytes::from_array(buffer[:read].to_owned()))
  }
  guard count == size &&
    entry.stamp() == expected &&
    self.stamp(name~) == expected else {
    raise IOError("bounded.stage_changed: " + name)
  }
}

///|
pub struct TaskLease {
  priv fd : Int32
}

///|
#borrow(name)
extern "C" fn bounded_try_task_lease(
  parent : Int32,
  name : Bytes,
  exclusive : Bool,
) -> Int32 = "morphir_bounded_try_task_lease"

///|
/// Open the persistent POSIX lock. Exclusive callers may create it. Shared
/// callers require an existing lock. Return None only for contention.
pub fn BoundedDirectory::try_task_lease(
  self : BoundedDirectory,
  name : String,
  exclusive~ : Bool = false,
) -> TaskLease? raise {
  let fd = bounded_try_task_lease(self.fd, bounded_name(name), exclusive)
  match fd {
    -2 => None
    fd if fd >= 0 => Some({ fd, })
    _ => raise IOError("bounded.cannot_open_task_lock: " + name)
  }
}

///|
pub fn TaskLease::close(self : TaskLease) -> Unit {
  ignore(file_close(self.fd))
}

///|
#borrow(name)
extern "C" fn bounded_task_lease_matches(
  fd : Int32,
  parent : Int32,
  name : Bytes,
) -> Bool = "morphir_bounded_task_lease_matches"

///|
pub fn TaskLease::matches(
  self : TaskLease,
  parent : BoundedDirectory,
  name : String,
) -> Bool raise {
  bounded_task_lease_matches(self.fd, parent.fd, bounded_name(name))
}

///|
pub extern "C" fn task_lock_pause() -> Unit = "morphir_bounded_task_lock_pause"

///|
extern "C" fn task_timestamp_bytes() -> Bytes = "morphir_bounded_task_timestamp"

///|
pub fn task_timestamp() -> String raise {
  let bytes = task_timestamp_bytes()
  guard bytes.length() == 20 else {
    raise IOError("task_record.clock_unavailable")
  }
  @utf8.decode(bytes[:])
}

///|
#borrow(staged, name)
extern "C" fn bounded_replace_file(
  parent : Int32,
  staged : Bytes,
  name : Bytes,
) -> Int32 = "morphir_bounded_replace_file"

///|
pub fn BoundedDirectory::replace_file(
  self : BoundedDirectory,
  staged : String,
  name : String,
) -> Unit raise {
  check(
    bounded_replace_file(self.fd, bounded_name(staged), bounded_name(name)),
    "task_record.replace_failed: " + name,
  )
}

///|
extern "C" fn bounded_same_directory(first : Int32, second : Int32) -> Bool = "morphir_bounded_same_directory"

///|
pub fn BoundedDirectory::same_directory(
  self : BoundedDirectory,
  other : BoundedDirectory,
) -> Bool {
  bounded_same_directory(self.fd, other.fd)
}
