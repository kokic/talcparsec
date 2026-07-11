///|
pub fn eof() -> Parser[Unit] {
  Parser::new(input => {
    if input.is_eof() {
      Ok((), input)
    } else {
      Err(ParseError::new(input, "end of input"))
    }
  })
}

///|
pub fn satisfy(name : String, predicate : (Char) -> Bool) -> Parser[Char] {
  Parser::new(input => {
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
  satisfy("'" + expected.to_string() + "'", ch => ch == expected)
}

///|
pub fn one_of(chars : String) -> Parser[Char] {
  satisfy("one of " + chars, ch => chars.contains_char(ch))
}

///|
pub fn none_of(chars : String) -> Parser[Char] {
  satisfy("none of " + chars, ch => !chars.contains_char(ch))
}

///|
pub fn string(expected : String) -> Parser[String] {
  Parser::new(input => {
    if input.remaining().has_prefix(expected.to_string_view()) {
      Ok(expected, input.advance_string(expected))
    } else {
      Err(ParseError::new(input, "\"" + expected + "\""))
    }
  })
}

///|
pub fn take_while(name : String, predicate : (Char) -> Bool) -> Parser[String] {
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
      Ok(String::from_array(chars), rest)
    }
  })
}

///|
pub fn ascii_digit() -> Parser[Char] {
  satisfy("ASCII digit", Char::is_ascii_digit)
}

///|
pub fn ascii_letter() -> Parser[Char] {
  satisfy("ASCII letter", Char::is_ascii_alphabetic)
}

///|
pub fn whitespace() -> Parser[Char] {
  satisfy("whitespace", Char::is_whitespace)
}

///|
pub fn spaces() -> Parser[Array[Char]] {
  whitespace().many()
}
