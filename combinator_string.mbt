///|
pub type StringParser[T] = Parser[Input, T]

///|
pub fn[U] Parser::string_map(
  self : Parser[Input, Char],
  f : (String) -> U,
) -> Parser[Input, U] {
  self.bind(value => pure(f(value.to_string())))
}

///|
pub fn many_chars(parser : Parser[Input, Char]) -> Parser[Input, String] {
  Parser::new(input => {
    let chars = Array::new()
    for rest = input {
      match parser.run(rest) {
        Ok((ch, next)) => {
          chars.push(ch)
          continue next
        }
        Err(error) =>
          break error.reject_if_committed(String::from_array(chars), rest)
      }
    }
  })
}

///|
pub fn many_chars1(parser : Parser[Input, Char]) -> Parser[Input, String] {
  parser.bind(head => many_chars(parser).map(tail => head.to_string() + tail))
}
