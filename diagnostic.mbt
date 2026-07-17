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
  self.offset
}

///|
pub fn ParseError::line(self : ParseError) -> Int {
  self.line
}

///|
pub fn ParseError::column(self : ParseError) -> Int {
  self.column
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
  self.committed
}

///|
pub fn ParseError::with_commit(self : ParseError) -> ParseError {
  {
    offset: self.offset,
    line: self.line,
    column: self.column,
    expected: self.expected,
    message: self.message,
    committed: true,
  }
}

///|
pub fn ParseError::without_commit(self : ParseError) -> ParseError {
  {
    offset: self.offset,
    line: self.line,
    column: self.column,
    expected: self.expected,
    message: self.message,
    committed: false,
  }
}

///|
pub fn ParseError::merge(self : ParseError, other : ParseError) -> ParseError {
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
