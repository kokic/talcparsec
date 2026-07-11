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
pub fn[T] ParseError::reject_if_committed(
  self : ParseError,
  value : T,
  rest : Input,
) -> ParseResult[T] {
  guard self.committed else { Ok(value, rest) }
  Err(self)
}

///|
pub fn ParseError::new(input : Input, expected : String) -> ParseError {
  {
    offset: input.offset,
    line: input.line,
    column: input.column,
    expected: [expected],
    message: "",
    committed: false,
  }
}

///|
pub fn ParseError::message(input : Input, message : String) -> ParseError {
  {
    offset: input.offset,
    line: input.line,
    column: input.column,
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
