///|
/// Error model: traits and concrete type for parse diagnostics.
///
/// Defines the trait hierarchy `Commit` → `CanMerge` → `Positioned` → `ParseFailure`
/// and the default `ParseError` struct. The generic function `commit_then_merge`
/// captures the core choice-combinator logic independently of the concrete error type.

///|
/// Types that track parse commitment — when a parser consumes input
/// and then fails, the error is "committed" to prevent backtracking.
pub(open) trait Commit {
  fn is_committed(Self) -> Bool
  fn mark_committed(Self) -> Self
  fn clear_commit(Self) -> Self
  fn[I, T] reject_if_committed(Self, value : T, rest : I) -> Result[
    (T, I),
    Self,
  ]
}

///|
/// Error types whose alternatives can be merged.
/// Furthest position wins; expected labels are combined.
pub(open) trait CanMerge {
  fn merge(Self, other : Self) -> Self
}

///|
/// Error types that carry a source position (offset, line, column).
pub(open) trait Positioned {
  fn error_offset(Self) -> Int
  fn error_line(Self) -> Int
  fn error_column(Self) -> Int
}

///|
/// Full parsing failure contract. Combines commit tracking, error merging,
/// source positioning, and construction from a cursor.
pub(open) trait ParseFailure: Commit + CanMerge + Positioned {
  fn[I : Cursor] signal(input : I, expected : String) -> Self
  fn[I : Cursor] message(input : I, msg : String) -> Self
}

///|
/// Parse failure metadata. `committed` prevents alternatives from backtracking
/// across input that has already been consumed.
pub(all) struct ParseError {
  offset : Int
  line : Int
  column : Int
  expected : String
  alternatives : Array[String]?
  message : String
  committed : Bool
} derive(Eq, Debug)

///|
pub fn[I, T] ParseError::reject_if_committed(
  self : ParseError,
  value : T,
  rest : I,
) -> Result[(T, I), ParseError] {
  guard self.committed else { Ok((value, rest)) }
  Err(self)
}

///|
pub fn[I : Cursor] ParseError::new(input : I, expected : String) -> ParseError {
  let position = input.position()
  {
    offset: position.offset,
    line: position.line,
    column: position.column,
    expected,
    alternatives: None,
    message: "",
    committed: false,
  }
}

///|
pub fn[I : Cursor] ParseError::message(input : I, msg : String) -> ParseError {
  let position = input.position()
  {
    offset: position.offset,
    line: position.line,
    column: position.column,
    expected: "",
    alternatives: None,
    message: msg,
    committed: false,
  }
}

///|
pub fn ParseError::offset(self : ParseError) -> Int {
  Positioned::error_offset(self)
}

///|
pub fn ParseError::line(self : ParseError) -> Int {
  Positioned::error_line(self)
}

///|
pub fn ParseError::column(self : ParseError) -> Int {
  Positioned::error_column(self)
}

///|
pub fn ParseError::expected(self : ParseError) -> Array[String] {
  let labels = if self.expected == "" { [] } else { [self.expected] }
  self.alternatives.map_or(labels, alts => [..labels, ..alts])
}

///|
pub fn ParseError::message_text(self : ParseError) -> String {
  self.message
}

///|
pub fn ParseError::is_committed(self : ParseError) -> Bool {
  Commit::is_committed(self)
}

///|
pub fn ParseError::with_commit(self : ParseError) -> ParseError {
  Commit::mark_committed(self)
}

///|
pub fn ParseError::without_commit(self : ParseError) -> ParseError {
  Commit::clear_commit(self)
}

///|
pub fn ParseError::merge(self : ParseError, other : ParseError) -> ParseError {
  CanMerge::merge(self, other)
}

///|
/// --- Commit impl ---
pub impl Commit for ParseError with fn is_committed(self) {
  self.committed
}

///|
pub impl Commit for ParseError with fn mark_committed(self) {
  { ..self, committed: true }
}

///|
pub impl Commit for ParseError with fn clear_commit(self) {
  { ..self, committed: false }
}

///|
pub impl Commit for ParseError with fn[I, T] reject_if_committed(
  self,
  value : T,
  rest : I,
) -> Result[(T, I), ParseError] {
  guard self.committed else { Ok((value, rest)) }
  Err(self)
}

///|
/// --- CanMerge impl ---
///
/// A committed failure at any offset commits the merged error: the
/// commit flag is OR'd even when the furthest-position error (the one
/// kept for diagnostics) is itself uncommitted. Otherwise a committed
/// failure at a shallower offset would be silently swallowed by a deeper
/// uncommitted one, letting choice backtracks that must not happen.

///|
fn ParseError::combine_labels(
  self : ParseError,
  other : ParseError,
) -> ParseError {
  let primary = if self.expected != "" { self.expected } else { other.expected }
  let message = if self.message != "" { self.message } else { other.message }
  let committed = self.committed || other.committed
  let mut new_labels : Array[String]? = None
  if self.expected != "" && other.expected != "" {
    let duplicate = self.alternatives.map_or(false, alts => {
      alts.contains(other.expected)
    })
    if !duplicate {
      new_labels = Some([other.expected])
    }
  }
  if other.alternatives is Some(other_alts) {
    for label in other_alts {
      guard label != primary else { continue }
      let duplicate = self.alternatives.map_or(false, alts => {
        alts.contains(label)
      })
      guard !duplicate else { continue }
      guard new_labels is Some(labels) else {
        new_labels = Some([label])
        continue
      }
      labels.push(label)
    }
  }
  let alternatives = self.alternatives.map_or(new_labels, alts => {
    new_labels.map_or(Some(alts), new => {
      let combined = alts.copy()
      combined.append(new)
      Some(combined)
    })
  })
  {
    offset: self.offset,
    line: self.line,
    column: self.column,
    expected: primary,
    alternatives,
    message,
    committed,
  }
}

///|
pub impl CanMerge for ParseError with fn merge(self, other) {
  if self.offset > other.offset {
    { ..self, committed: self.committed || other.committed }
  } else if other.offset > self.offset {
    { ..other, committed: self.committed || other.committed }
  } else if other.expected == self.expected {
    guard other.alternatives is None else {
      ParseError::combine_labels(self, other)
    }
    let committed = self.committed || other.committed
    let message = if self.message != "" { self.message } else { other.message }
    if committed == self.committed && message == self.message {
      self
    } else {
      { ..self, message, committed }
    }
  } else {
    ParseError::combine_labels(self, other)
  }
}

///|
/// --- Positioned impl ---
pub impl Positioned for ParseError with fn error_offset(self) {
  self.offset
}

///|
pub impl Positioned for ParseError with fn error_line(self) {
  self.line
}

///|
pub impl Positioned for ParseError with fn error_column(self) {
  self.column
}

///|
/// --- ParseFailure impl ---
pub impl ParseFailure for ParseError with fn[I : Cursor] signal(
  input : I,
  expected : String,
) -> ParseError {
  ParseError::new(input, expected)
}

///|
pub impl ParseFailure for ParseError with fn[I : Cursor] message(
  input : I,
  msg : String,
) -> ParseError {
  ParseError::message(input, msg)
}

///|
pub extend ParseError with Eq::{not_equal, equal}

///|
pub extend ParseError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ParseError with Commit::{mark_committed, clear_commit}

///|
pub extend ParseError with Positioned::{error_line, error_offset, error_column}

///|
pub extend ParseError with ParseFailure::{signal}

///|
pub fn ParseError::to_string(self : ParseError) -> String {
  let base = "parse error at \{self.line}:\{self.column}"
  if self.message != "" {
    "\{base}: \{self.message}"
  } else {
    let labels = self.expected()
    if labels.length() > 0 {
      "\{base}: expected \{labels.join(" or ")}"
    } else {
      base
    }
  }
}

///|
/// Generic error combinator usable with any `E : Commit + CanMerge`.
fn[E : Commit + CanMerge] commit_then_merge(first : E, second : E) -> E {
  guard !Commit::is_committed(first) else { first }
  CanMerge::merge(first, second)
}

///|
test "trait-based generic error handling" {
  let err_a = ParseError::new(Input::new("x"), "a")
  let err_b = ParseError::new(Input::new("y"), "b")
  let committed = ParseError::new(Input::new("x"), "a").with_commit()
  let r1 = commit_then_merge(committed, err_b)
  @test.assert_eq(Commit::is_committed(r1), true)
  let r2 = commit_then_merge(err_a, err_b)
  @test.assert_eq(Positioned::error_offset(r2), 0)
}
