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
pub fn[T] pure(value : T) -> Parser[T] {
  Parser::new(input => Ok(value, input))
}

///|
pub fn[T] fail(expected : String) -> Parser[T] {
  Parser::new(input => Err(ParseError::new(input, expected)))
}

///|
pub fn[T] delay(thunk : () -> Parser[T]) -> Parser[T] {
  Parser::new(input => thunk().run(input))
}
