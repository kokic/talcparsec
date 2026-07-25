///|
/// String-specific parser combinators and type aliases.
///
/// Provides `StringParser`, `CParser`, `SParser` type aliases and the
/// `many_chars` / `many_chars1` helpers that collect character-level
/// results into `String` values.

///|
/// Convenience alias for `Parser[Input, T]`, used for string-input parsers.
pub type StringParser[T] = Parser[Input, T]

///|
pub type CParser = StringParser[Char]

///|
pub type SParser = StringParser[String]

///|
/// Maps a `char` parser's result to a `String` before applying `f`.
#inline
pub fn[U, E : Commit] ParserRaw::string_map(
  self : ParserRaw[Input, Char, E],
  f : (String) -> U,
) -> ParserRaw[Input, U, E] {
  self.bind(value => pure(f(value.to_string())))
}

///|
/// Zero or more repetitions of a char parser, collecting results
/// into a `String`.
///
/// Unlike `take_while`, succeeds on zero matches (returns empty string).
pub fn[E : Commit + ParseFailure] many_chars(
  parser : ParserRaw[Input, Char, E],
) -> ParserRaw[Input, String, E] {
  parser.many().map(chars => String::from_array(chars))
}

///|
/// One or more repetitions of a char parser, collecting results
/// into a `String`.
///
/// Fails on zero matches.
#inline
pub fn[E : Commit + ParseFailure] many_chars1(
  parser : ParserRaw[Input, Char, E],
) -> ParserRaw[Input, String, E] {
  parser.some().map(chars => String::from_array(chars))
}
