///|
pub struct Health {
  priv accepted : Ref[Int32]
  priv filtered : Ref[Int32]
  priv dropped : Ref[Int32]
  priv unavailable : Ref[Int32]
}

///|
pub fn Health::new() -> Health {
  { accepted: Ref(0), filtered: Ref(0), dropped: Ref(0), unavailable: Ref(0), }
}

///|
pub fn Health::to_json(self : Health) -> Json {
  {
    "accepted": self.accepted.val,
    "filtered": self.filtered.val,
    "dropped": self.dropped.val,
    "unavailable": self.unavailable.val,
  }
}

///|
/// Per-observer delivery isolation, with a non-recursive health channel.
/// Host callbacks perform only bounded enqueue work. Drain is host-owned.
pub fn Observer::isolated(self : Observer, health : Health) -> Observer {
  let busy = Ref(false)
  {
    ..self,
    try_record: fn(record) {
      let delivery = if busy.val {
        Dropped
      } else {
        busy.val = true
        let result = (self.try_record)(record) catch { _ => Unavailable }
        busy.val = false
        result
      }
      match delivery {
        Accepted => health.accepted.val += 1
        Filtered => health.filtered.val += 1
        Dropped => health.dropped.val += 1
        Unavailable => health.unavailable.val += 1
      }
      delivery
    },
  }
}

///|
pub fn Observer::record(self : Observer, record : Observation) -> Delivery {
  (self.try_record)(record) catch {
    _ => Unavailable
  }
}
