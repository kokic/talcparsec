///|
/// Immutable input cursor used by every parser invocation.
/// Offsets are UTF-16 code unit offsets, matching MoonBit string indexing.
pub(all) struct Input {
  source : String
  offset : Int
  line : Int
  column : Int
} derive(Eq, Debug)

///|
pub fn Input::new(source : String) -> Input {
  { source, offset: 0, line: 1, column: 1 }
}

///|
pub fn Input::source(self : Input) -> String {
  self.source
}

///|
pub fn Input::offset(self : Input) -> Int {
  self.offset
}

///|
pub fn Input::line(self : Input) -> Int {
  self.line
}

///|
pub fn Input::column(self : Input) -> Int {
  self.column
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
pub fn Input::advance(self : Input, ch : Char) -> Input {
  if ch == '\n' {
    Input::{
      source: self.source,
      offset: self.offset + ch.utf16_len(),
      line: self.line + 1,
      column: 1,
    }
  } else {
    Input::{
      source: self.source,
      offset: self.offset + ch.utf16_len(),
      line: self.line,
      column: self.column + 1,
    }
  }
}

///|
pub fn Input::advance_string(self : Input, text : String) -> Input {
  let mut input = self
  for ch in text.iter() {
    input = input.advance(ch)
  }
  input
}

///|
pub fn Input::remaining(self : Input) -> StringView {
  self.source.view(start_offset=self.offset)
}
