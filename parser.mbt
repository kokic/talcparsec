///|
/// Generic parser type parameterised by input `I`, result `T`, and error `E`.
/// The convenience alias `Parser[I, T]` fixes `E = ParseError` for common use.
pub(all) struct ParserRaw[I, T, E] {
  parse_fn : (I) -> Result[(T, I), E]
}

/// Convenience alias using the default ParseError.
pub type Parser[I, T] = ParserRaw[I, T, ParseError]

///|
pub fn[I, T, E] ParserRaw::new(
  parse_fn : (I) -> Result[(T, I), E],
) -> ParserRaw[I, T, E] {
  { parse_fn, }
}

///|
pub fn[I, T, E] ParserRaw::run(
  self : ParserRaw[I, T, E],
  input : I,
) -> Result[(T, I), E] {
  (self.parse_fn)(input)
}

///|
pub fn[I : Cursor, T, E : ParseFailure] ParserRaw::parse(
  self : ParserRaw[I, T, E],
  input : I,
) -> Result[T, E] {
  match self.run(input) {
    Ok((value, input)) => {
      guard !input.is_at_eof() else { Ok(value) }
      Err(ParseFailure::signal(input, "end of input"))
    }
    Err(error) => Err(error)
  }
}

///|
pub fn[I, T, E] ParserRaw::parse_partial(
  self : ParserRaw[I, T, E],
  input : I,
) -> Result[(T, I), E] {
  self.run(input)
}

///|
pub fn[I, T, E] pure(value : T) -> ParserRaw[I, T, E] {
  ParserRaw::new(input => Ok((value, input)))
}

///|
pub fn[I : Cursor, T, E : ParseFailure] fail(expected : String) -> ParserRaw[I, T, E] {
  ParserRaw::new(input => Err(ParseFailure::signal(input, expected)))
}

///|
pub fn[I, T, E] delay(thunk : () -> ParserRaw[I, T, E]) -> ParserRaw[I, T, E] {
  ParserRaw::new(input => thunk().run(input))
}
