///|
/// A presentation cursor, independent of original-byte ownership and authority.
struct OriginalsPage {
  number : Int32
} derive(Eq, Debug)

///|
let originals_page_size : Int32 = 100

///|
fn OriginalsPage::first() -> OriginalsPage {
  { number: 0, }
}

///|
fn OriginalsPage::start(self : OriginalsPage) -> Int32 {
  self.number * originals_page_size
}

///|
fn OriginalsPage::fits(self : OriginalsPage, total : Int32) -> Bool {
  self.start() < total
}

///|
fn OriginalsPage::previous(self : OriginalsPage) -> OriginalsPage? {
  if self.number == 0 {
    None
  } else {
    Some({ number: self.number - 1, })
  }
}

///|
fn OriginalsPage::next(self : OriginalsPage, total : Int32) -> OriginalsPage? {
  let next = { number: self.number + 1, }
  if next.fits(total) {
    Some(next)
  } else {
    None
  }
}
