///|
/// Input abstraction for parser combinators.
///
/// Provides the `Cursor` trait for position-tracking input cursors and the
/// concrete `Input` struct, an immutable UTF-16 character cursor with
/// line/column bookkeeping. The `Cursor` trait enables parameterising
/// parsers over arbitrary input sources.

///|
/// A source position reported by parser diagnostics.
#valtype
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
#valtype
pub(all) struct Input {
  source : String
  offset : Int
  line_starts : Array[Int]
} derive(Eq, Debug)

///|
pub fn Input::new(source : String) -> Input {
  { source, offset: 0, line_starts: scan_line_starts(source), }
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
  { ..self, offset: self.offset + ch.utf16_len(), }
}

///|
pub fn Input::advance_string(self : Input, text : String) -> Input {
  { ..self, offset: self.offset + text.length(), }
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
  { offset: self.offset, line: lo + 1, column: self.offset - starts[lo] + 1, }
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

///|
// JS has no native V128 operations. A compile-time constant removes SIMD
// branches there while keeping the same scalar tail and Unicode handling.
#cfg(target="js")
const UseSimd = false

///|
#cfg(not(target="js"))
const UseSimd = true

///|
/// Scan UTF-16 directly: LF is a single code unit, even next to surrogates.
/// Every vector load is guarded by the number of remaining code units.
#warnings("-alert_experimental")
fn scan_line_starts(source : String) -> Array[Int] {
  let starts = [0]
  let length = source.length()
  let tail = for offset = 0 {
    guard UseSimd && offset <= length - 8 else { break offset }
    let block = @v128.v128_load_i16x8(source, offset)
    let newline = @v128.i16x8_splat(10)
    if @v128.v128_any_true(@v128.i16x8_eq(block, newline)) {
      for index in offset..<(offset + 8) {
        if source[index] == 10 {
          starts.push(index + 1)
        }
      }
    }
    continue offset + 8
  }
  for index in tail..<length {
    if source[index] == 10 {
      starts.push(index + 1)
    }
  }
  starts
}
