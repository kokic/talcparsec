///|
/// Input abstraction for parser combinators.
///
/// Provides the `Cursor` trait for position-tracking input cursors and the
/// concrete `Input` struct, an immutable UTF-16 character cursor with
/// line/column bookkeeping. The `Cursor` trait enables parameterising
/// parsers over arbitrary input sources.

///|
/// A source position reported by parser diagnostics.
pub(all) struct Position {
  offset : Int
  line : Int
  column : Int
} derive(Eq, Debug)

///|
/// Operations shared by parser input cursors. `cursor` must increase whenever
/// an input element is consumed.
pub(open) trait Cursor {
  fn cursor(Self) -> Int
  fn position(Self) -> Position
  fn is_at_eof(Self) -> Bool
  fn same_cursor(Self, other : Self) -> Bool = _
}

///|
/// Immutable character input cursor.
/// Offsets are UTF-16 code unit offsets, matching MoonBit string indexing.
/// Line/column positions are computed lazily from `line_starts` on demand.
pub(all) struct Input {
  source : String
  offset : Int
  line_starts : Array[Int]
} derive(Eq, Debug)

///|
pub fn Input::new(source : String) -> Input {
  let line_starts = Array()
  line_starts.push(0)
  for offset, ch in source.iter2() {
    if ch == '\n' {
      line_starts.push(offset + ch.utf16_len())
    }
  }
  { source, offset: 0, line_starts }
}

///|
pub fn Input::is_eof(self : Input) -> Bool {
  self.offset >= self.source.length()
}

///|
pub fn Input::peek(self : Input) -> Char? {
  self.source.get_char(self.offset)
}

///|
pub fn Input::next(self : Input) -> (Char, Input)? {
  self.peek().map(ch => (ch, self.advance(ch)))
}

///|
pub fn Input::advance(self : Input, ch : Char) -> Input {
  { ..self, offset: self.offset + ch.utf16_len() }
}

///|
pub fn Input::advance_string(self : Input, text : String) -> Input {
  { ..self, offset: self.offset + text.length() }
}

///|
pub fn Input::remaining(self : Input) -> StringView {
  self.source.view(start_offset=self.offset)
}

///|
pub impl Cursor for Input with fn cursor(self) {
  self.offset
}

///|
pub impl Cursor for Input with fn position(self) {
  let starts = self.line_starts
  let lo = for lo = 0, hi = starts.length() {
    guard lo + 1 < hi else { break lo }
    let mid = (lo + hi) / 2
    if starts[mid] <= self.offset {
      continue mid, hi
    } else {
      continue lo, mid
    }
  }
  { offset: self.offset, line: lo + 1, column: self.offset - starts[lo] + 1 }
}

///|
pub impl Cursor for Input with fn is_at_eof(self) {
  self.is_eof()
}

///|
/// Checks whether the cursor has the same position as `other`.
///
/// Parameters:
///
/// * `self` : The current cursor.
/// * `other` : Another cursor to compare against.
///
/// Used internally by `many` and `many_until` to detect parsers
/// that accepted empty input.
///
/// Returns `true` if both cursors are at the same position.
impl Cursor with fn same_cursor(self, other) {
  self.cursor() == other.cursor()
}

///|
pub extend Input with Cursor::{cursor, position, is_at_eof, same_cursor}

///|
pub extend Input with Eq::{not_equal, equal}

///|
pub extend Input with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Position with Eq::{not_equal, equal}

///|
pub extend Position with @moonbitlang/core/debug.Debug::{to_repr}
