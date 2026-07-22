///|
/// Convenience alias for `Parser[Input, T]`, used for string-input parsers.
pub type StringParser[T] = Parser[Input, T]

///|
/// Maps a `char` parser's result to a `String` before applying `f`.
///
/// Parameters:
///
/// * `self` : A parser that yields a single `Char`.
/// * `f` : A function from `String` to the desired result type.
///
/// Returns a parser that yields the result of `f` applied to
/// the string representation of the matched character.
#inline
pub fn[U] Parser::string_map(
  self : Parser[Input, Char],
  f : (String) -> U,
) -> Parser[Input, U] {
  self.bind(value => pure(f(value.to_string())))
}

///|
/// Zero or more repetitions of a char parser, collecting results
/// into a `String`.
///
/// Parameters:
///
/// * `parser` : A char parser to repeat.
///
/// Unlike `take_while`, succeeds on zero matches (returns empty string).
/// Stops on non-committed failure.
///
/// Returns a parser that yields the collected characters as a `String`.
pub fn many_chars(parser : Parser[Input, Char]) -> Parser[Input, String] {
  parser.many().map(chars => String::from_array(chars))
}

///|
/// One or more repetitions of a char parser, collecting results
/// into a `String`.
///
/// Parameters:
///
/// * `parser` : A char parser to repeat. Must match at least once.
///
/// Fails on zero matches.
/// Returns a parser that yields the collected characters as a `String`.
#inline
pub fn many_chars1(parser : Parser[Input, Char]) -> Parser[Input, String] {
  parser.some().map(chars => String::from_array(chars))
}
