///|
pub(all) struct Parser[I, T] {
  parse_fn : (I) -> Result[(T, I), ParseError]
}

///|
pub fn[I, T] Parser::new(
  parse_fn : (I) -> Result[(T, I), ParseError],
) -> Parser[I, T] {
  { parse_fn, }
}

///|
pub fn[I, T] Parser::run(
  self : Parser[I, T],
  input : I,
) -> Result[(T, I), ParseError] {
  (self.parse_fn)(input)
}

///|
pub fn[I : Cursor, T] Parser::parse(
  self : Parser[I, T],
  input : I,
) -> Result[T, ParseError] {
  match self.run(input) {
    Ok((value, input)) => {
      guard !input.is_at_eof() else { Ok(value) }
      Err(ParseError::new(input, "end of input"))
    }
    Err(error) => Err(error)
  }
}

///|
pub fn[I, T] Parser::parse_partial(
  self : Parser[I, T],
  input : I,
) -> Result[(T, I), ParseError] {
  self.run(input)
}

///|
pub fn[I, T] pure(value : T) -> Parser[I, T] {
  Parser::new(input => Ok((value, input)))
}

///|
pub fn[I : Cursor, T] fail(expected : String) -> Parser[I, T] {
  Parser::new(input => Err(ParseError::new(input, expected)))
}

///|
pub fn[I, T] delay(thunk : () -> Parser[I, T]) -> Parser[I, T] {
  Parser::new(input => thunk().run(input))
}
