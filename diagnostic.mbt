///|
/// Types that track parse commitment — when a parser consumes input
/// and then fails, the error is "committed" to prevent backtracking.
pub(open) trait Commit {
  fn is_committed(Self) -> Bool
  fn mark_committed(Self) -> Self
  fn clear_commit(Self) -> Self
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
/// Parse failure metadata. `committed` prevents alternatives from backtracking
/// across input that has already been consumed.
pub(all) struct ParseError {
  offset : Int
  line : Int
  column : Int
  expected : Array[String]
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
    expected: [expected],
    message: "",
    committed: false,
  }
}

///|
pub fn[I : Cursor] ParseError::message(
  input : I,
  message : String,
) -> ParseError {
  let position = input.position()
  {
    offset: position.offset,
    line: position.line,
    column: position.column,
    expected: [],
    message,
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
  self.expected
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
impl Commit for ParseError with fn is_committed(self) {
  self.committed
}

///|
impl Commit for ParseError with fn mark_committed(self) {
  { ..self, committed: true }
}

///|
impl Commit for ParseError with fn clear_commit(self) {
  { ..self, committed: false }
}

///|
/// --- CanMerge impl ---
impl CanMerge for ParseError with fn merge(self, other) {
  if self.offset > other.offset {
    self
  } else if other.offset > self.offset {
    other
  } else {
    let expected = self.expected.copy()
    for item in other.expected {
      if !expected.contains(item) {
        expected.push(item)
      }
    }
    let message = if self.message != "" { self.message } else { other.message }
    {
      offset: self.offset,
      line: self.line,
      column: self.column,
      expected,
      message,
      committed: self.committed || other.committed,
    }
  }
}

///|
/// --- Positioned impl ---
impl Positioned for ParseError with fn error_offset(self) {
  self.offset
}

///|
impl Positioned for ParseError with fn error_line(self) {
  self.line
}

///|
impl Positioned for ParseError with fn error_column(self) {
  self.column
}

///|
pub fn ParseError::to_string(self : ParseError) -> String {
  let base = "parse error at " +
    self.line.to_string() +
    ":" +
    self.column.to_string()
  if self.message != "" {
    base + ": " + self.message
  } else if self.expected.length() > 0 {
    base + ": expected " + self.expected.join(" or ")
  } else {
    base
  }
}

///|
/// Generic error combinator usable with any `E : Commit + CanMerge`.
fn[E : Commit + CanMerge] commit_then_merge(first : E, second : E) -> E {
  if Commit::is_committed(first) {
    first
  } else {
    CanMerge::merge(first, second)
  }
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
