///|
/// Character-level and token-level primitive parsers.
///
/// Defines the fundamental character parsers (`char`, `satisfy`, `string`,
/// `take_while`, etc.), generic token parser `satisfy_input`, whitespace
/// helpers, and pre-built convenience parsers for line-oriented input.

///|
pub fn[I : Cursor] eof() -> Parser[I, Unit] {
  ParserRaw::new(input => {
    guard input.is_at_eof() else {
      Err(ParseFailure::signal(input, "end of input"))
    }
    Ok(((), input))
  })
}

///|
pub fn[I : Cursor, T] satisfy_input(
  next : (I) -> (T, I)?,
  name : String,
  predicate : (T) -> Bool,
) -> Parser[I, T] {
  ParserRaw::new(input => {
    match next(input) {
      Some((token, rest)) => {
        guard predicate(token) else {
          Err(ParseFailure::signal(input, name))
        }
        Ok((token, rest))
      }
      None => Err(ParseFailure::signal(input, name))
    }
  })
}

///|
pub fn char(expected : Char) -> Parser[Input, Char] {
  satisfy("'\{expected}'", ch => ch == expected)
}

///|
pub fn satisfy(
  name : String,
  predicate : (Char) -> Bool,
) -> Parser[Input, Char] {
  satisfy_input(Input::next, name, predicate)
}

///|
pub fn one_of(chars : String) -> Parser[Input, Char] {
  satisfy("one of \{chars}", ch => chars.contains_char(ch))
}

///|
pub fn none_of(chars : String) -> Parser[Input, Char] {
  satisfy("none of \{chars}", ch => !chars.contains_char(ch))
}

///|
pub fn string(expected : String) -> Parser[Input, String] {
  ParserRaw::new(input => {
    guard input.remaining().has_prefix(expected.to_string_view()) else {
      Err(ParseFailure::signal(input, "\"\{expected}\""))
    }
    Ok((expected, input.advance_string(expected)))
  })
}

///|
pub fn take_while(
  name : String,
  predicate : (Char) -> Bool,
) -> Parser[Input, String] {
  ParserRaw::new(input => {
    let chars = Array::new()
    let rest = for rest = input {
      match rest.peek() {
        Some(ch) => {
          guard predicate(ch) else { break rest }
          chars.push(ch)
          continue rest.advance(ch)
        }
        None => break rest
      }
    }
    match chars {
      [] => Err(ParseFailure::signal(input, name))
      _ => Ok((String::from_array(chars), rest))
    }
  })
}

///|
pub fn ascii_digit() -> Parser[Input, Char] {
  satisfy("ASCII digit", Char::is_ascii_digit)
}

///|
pub fn ascii_letter() -> Parser[Input, Char] {
  satisfy("ASCII letter", Char::is_ascii_alphabetic)
}

///|
pub fn whitespace() -> Parser[Input, Char] {
  satisfy("whitespace", Char::is_whitespace)
}

///|
pub fn spaces() -> Parser[Input, Array[Char]] {
  whitespace().many()
}

/// --- Pre-built convenience parsers --------------------------------------

///|
pub let space : CParser = char(' ')

///|
pub let newline : CParser = char('\n')

///|
pub let not_newline : CParser = satisfy("not newline", c => c != '\n')

///|
pub let line_content : SParser = many_chars(not_newline)

///|
/// Maps content `c` to a parser that consumes a newline and returns `c` +
/// a newline character.
pub let with_line : (String) -> SParser = c => newline.map(_ => "\{c}\n")

///|
/// Consumes all non-newline characters, then consumes the trailing newline.
///
/// Returns the matched line content including the newline terminator.
pub let rest_of_line : SParser = line_content.bind(with_line)
