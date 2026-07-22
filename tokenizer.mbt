///|
pub fn[I : Cursor] eof() -> Parser[I, Unit] {
  Parser::new(input => {
    if input.is_at_eof() {
      Ok(((), input))
    } else {
      Err(ParseError::new(input, "end of input"))
    }
  })
}

///|
pub fn[I : Cursor, T] satisfy_input(
  next : (I) -> (T, I)?,
  name : String,
  predicate : (T) -> Bool,
) -> Parser[I, T] {
  Parser::new(input => {
    match next(input) {
      Some((token, rest)) =>
        if predicate(token) {
          Ok((token, rest))
        } else {
          Err(ParseError::new(input, name))
        }
      None => Err(ParseError::new(input, name))
    }
  })
}

///|
pub fn char(expected : Char) -> Parser[Input, Char] {
  satisfy("'" + expected.to_string() + "'", ch => ch == expected)
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
  satisfy("one of " + chars, ch => chars.contains_char(ch))
}

///|
pub fn none_of(chars : String) -> Parser[Input, Char] {
  satisfy("none of " + chars, ch => !chars.contains_char(ch))
}

///|
pub let not_newline : StringParser[Char] = satisfy("not newline", c => c != '\n')

///|
pub fn string(expected : String) -> Parser[Input, String] {
  Parser::new(input => {
    if input.remaining().has_prefix(expected.to_string_view()) {
      Ok((expected, input.advance_string(expected)))
    } else {
      Err(ParseError::new(input, "\"" + expected + "\""))
    }
  })
}

///|
pub fn take_while(
  name : String,
  predicate : (Char) -> Bool,
) -> Parser[Input, String] {
  Parser::new(input => {
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
    if chars.length() == 0 {
      Err(ParseError::new(input, name))
    } else {
      Ok((String::from_array(chars), rest))
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

///|
pub let space : StringParser[Char] = char(' ')
