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
    {
      source: self.source,
      offset: self.offset + ch.utf16_len(),
      line: self.line + 1,
      column: 1,
    }
  } else {
    {
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

///|
pub(all) enum ParseResult[T] {
  Ok(T, Input)
  Err(ParseError)
} derive(Eq, Debug)

///|
pub fn[T] ParseResult::is_ok(self : ParseResult[T]) -> Bool {
  match self {
    Ok(_, _) => true
    Err(_) => false
  }
}

///|
pub fn[T] ParseResult::unwrap(self : ParseResult[T]) -> (T, Input) {
  match self {
    Ok(value, input) => (value, input)
    Err(error) => abort(error.to_string())
  }
}

///|
pub(all) struct Parser[T] {
  parse_fn : (Input) -> ParseResult[T]
}

///|
pub fn[T] Parser::new(parse_fn : (Input) -> ParseResult[T]) -> Parser[T] {
  { parse_fn, }
}

///|
pub fn[T] Parser::run(self : Parser[T], input : Input) -> ParseResult[T] {
  (self.parse_fn)(input)
}

///|
pub fn[T] Parser::parse(
  self : Parser[T],
  source : String,
) -> Result[T, ParseError] {
  match self.run(Input::new(source)) {
    Ok(value, input) =>
      if input.is_eof() {
        Ok(value)
      } else {
        Err(ParseError::new(input, "end of input"))
      }
    Err(error) => Err(error)
  }
}

///|
pub fn[T] Parser::parse_partial(
  self : Parser[T],
  source : String,
) -> ParseResult[T] {
  self.run(Input::new(source))
}

///|
pub fn[T, U] Parser::bind(
  self : Parser[T],
  next : (T) -> Parser[U],
) -> Parser[U] {
  Parser::new(fn(input) {
    match self.run(input) {
      Ok(value, rest) =>
        match next(value).run(rest) {
          Ok(out, end) => Ok(out, end)
          Err(error) =>
            Err(
              if rest.offset != input.offset {
                error.with_commit()
              } else {
                error
              },
            )
        }
      Err(error) => Err(error)
    }
  })
}

///|
pub fn[T, U] Parser::map(self : Parser[T], f : (T) -> U) -> Parser[U] {
  self.bind(fn(value) { pure(f(value)) })
}

///|
pub fn[T, U] Parser::then(self : Parser[T], next : Parser[U]) -> Parser[U] {
  self.bind(fn(_) { next })
}

///|
pub fn[T, U] Parser::skip(self : Parser[T], next : Parser[U]) -> Parser[T] {
  self.bind(fn(value) { next.map(fn(_) { value }) })
}

///|
pub fn[T] Parser::or(self : Parser[T], other : Parser[T]) -> Parser[T] {
  Parser::new(fn(input) {
    match self.run(input) {
      Ok(value, rest) => Ok(value, rest)
      Err(first) =>
        if first.committed {
          Err(first)
        } else {
          match other.run(input) {
            Ok(value, rest) => Ok(value, rest)
            Err(second) => Err(first.merge(second))
          }
        }
    }
  })
}

///|
pub fn[T] Parser::attempt(self : Parser[T]) -> Parser[T] {
  Parser::new(fn(input) {
    match self.run(input) {
      Ok(value, rest) => Ok(value, rest)
      Err(error) => Err(error.without_commit())
    }
  })
}

///|
pub fn[T] Parser::optional(self : Parser[T]) -> Parser[T?] {
  Parser::new(fn(input) {
    match self.run(input) {
      Ok(value, rest) => Ok(Some(value), rest)
      Err(error) => if error.committed { Err(error) } else { Ok(None, input) }
    }
  })
}

///|
pub fn[T] Parser::many(self : Parser[T]) -> Parser[Array[T]] {
  Parser::new(fn(input) {
    let mut rest = input
    let values = Array::new()
    let mut done = false
    while !done {
      match self.run(rest) {
        Ok(value, next) =>
          if next.offset == rest.offset {
            return Err(
              ParseError::message(rest, "many parser accepted empty input"),
            )
          } else {
            values.push(value)
            rest = next
          }
        Err(error) =>
          if error.committed {
            return Err(error)
          } else {
            done = true
          }
      }
    }
    Ok(values, rest)
  })
}

///|
pub fn[T] Parser::some(self : Parser[T]) -> Parser[Array[T]] {
  self.bind(fn(head) {
    self
    .many()
    .map(fn(tail) {
      let values = Array::new(capacity=tail.length() + 1)
      values.push(head)
      values.append(tail)
      values
    })
  })
}

///|
pub fn[T, S] Parser::sep_by(
  self : Parser[T],
  sep : Parser[S],
) -> Parser[Array[T]] {
  self.sep_by1(sep).or(pure([]))
}

///|
pub fn[T, S] Parser::sep_by1(
  self : Parser[T],
  sep : Parser[S],
) -> Parser[Array[T]] {
  self.bind(fn(head) {
    sep
    .then(self)
    .many()
    .map(fn(tail) {
      let values = Array::new(capacity=tail.length() + 1)
      values.push(head)
      values.append(tail)
      values
    })
  })
}

///|
pub fn[T] Parser::label(self : Parser[T], expected : String) -> Parser[T] {
  Parser::new(fn(input) {
    match self.run(input) {
      Ok(value, rest) => Ok(value, rest)
      Err(error) =>
        if error.offset == input.offset {
          Err(ParseError::new(input, expected))
        } else {
          Err(error)
        }
    }
  })
}

///|
pub fn[T] Parser::lexeme(self : Parser[T]) -> Parser[T] {
  self.skip(spaces())
}

///|
pub fn[T, L, R] Parser::between(
  self : Parser[T],
  left : Parser[L],
  right : Parser[R],
) -> Parser[T] {
  left.then(self).skip(right)
}

///|
pub fn[T, L] Parser::after(self : Parser[T], left : Parser[L]) -> Parser[T] {
  left.then(self)
}

///|
pub fn[T, R] Parser::before(self : Parser[T], right : Parser[R]) -> Parser[T] {
  self.skip(right)
}

///|
pub fn[T] pure(value : T) -> Parser[T] {
  Parser::new(fn(input) { Ok(value, input) })
}

///|
pub fn[T] fail(expected : String) -> Parser[T] {
  Parser::new(fn(input) { Err(ParseError::new(input, expected)) })
}

///|
pub fn eof() -> Parser[Unit] {
  Parser::new(fn(input) {
    if input.is_eof() {
      Ok((), input)
    } else {
      Err(ParseError::new(input, "end of input"))
    }
  })
}

///|
pub fn satisfy(name : String, predicate : (Char) -> Bool) -> Parser[Char] {
  Parser::new(fn(input) {
    match input.peek() {
      Some(ch) =>
        if predicate(ch) {
          Ok(ch, input.advance(ch))
        } else {
          Err(ParseError::new(input, name))
        }
      None => Err(ParseError::new(input, name))
    }
  })
}

///|
pub fn char(expected : Char) -> Parser[Char] {
  satisfy("'" + expected.to_string() + "'", fn(ch) { ch == expected })
}

///|
pub fn one_of(chars : String) -> Parser[Char] {
  satisfy("one of " + chars, fn(ch) { chars.contains_char(ch) })
}

///|
pub fn none_of(chars : String) -> Parser[Char] {
  satisfy("none of " + chars, fn(ch) { !chars.contains_char(ch) })
}

///|
pub fn string(expected : String) -> Parser[String] {
  Parser::new(fn(input) {
    if input.remaining().has_prefix(expected.to_string_view()) {
      Ok(expected, input.advance_string(expected))
    } else {
      Err(ParseError::new(input, "\"" + expected + "\""))
    }
  })
}

///|
pub fn take_while(name : String, predicate : (Char) -> Bool) -> Parser[String] {
  Parser::new(fn(input) {
    let mut rest = input
    let chars = Array::new()
    let mut done = false
    while !done {
      match rest.peek() {
        Some(ch) =>
          if predicate(ch) {
            chars.push(ch)
            rest = rest.advance(ch)
          } else {
            done = true
          }
        None => done = true
      }
    }
    if chars.length() == 0 {
      Err(ParseError::new(input, name))
    } else {
      Ok(String::from_array(chars), rest)
    }
  })
}

///|
pub fn ascii_digit() -> Parser[Char] {
  satisfy("ASCII digit", fn(ch) { ch.is_ascii_digit() })
}

///|
pub fn ascii_letter() -> Parser[Char] {
  satisfy("ASCII letter", fn(ch) { ch.is_ascii_alphabetic() })
}

///|
pub fn whitespace() -> Parser[Char] {
  satisfy("whitespace", fn(ch) { ch.is_whitespace() })
}

///|
pub fn spaces() -> Parser[Array[Char]] {
  whitespace().many()
}

///|
pub fn[T] lexeme(parser : Parser[T]) -> Parser[T] {
  parser.lexeme()
}

///|
pub fn symbol(text : String) -> Parser[String] {
  string(text).lexeme()
}

///|
pub fn[T, L, R] between(
  left : Parser[L],
  parser : Parser[T],
  right : Parser[R],
) -> Parser[T] {
  parser.between(left, right)
}

///|
pub fn[T] delay(thunk : () -> Parser[T]) -> Parser[T] {
  Parser::new(fn(input) { thunk().run(input) })
}
