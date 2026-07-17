///|
test "monadic bind composes parsers" {
  let parser = char('a').bind(_ => ascii_digit())
  let result = parser.parse(Input::new("a7"))
  @test.assert_eq(result, Ok('7'))
}

///|
test "method chain parses token list" {
  let identifier = ascii_letter()
    .some()
    .map(chars => String::from_array(chars))
    .lexeme()
  let parser = identifier.sep_by(symbol(","))
  let result = parser.parse(Input::new("foo, bar, baz"))
  @test.assert_eq(result, Ok(["foo", "bar", "baz"]))
}

///|
test "choice does not backtrack committed consumption" {
  let parser = string("ab").then(char('c')).or(string("ab").then(char('d')))
  match parser.parse(Input::new("abd")) {
    Err(error) => {
      @test.assert_eq(error.offset(), 2)
      @test.assert_eq(error.is_committed(), true)
    }
    Ok(_) => @test.fail("expected committed parse error")
  }
}

///|
test "attempt enables explicit backtracking" {
  let parser = string("ab")
    .then(char('c'))
    .attempt()
    .or(string("ab").then(char('d')))
  let result = parser.parse(Input::new("abd"))
  @test.assert_eq(result, Ok('d'))
}

///|
test "between and eof track line and column" {
  let parser = ascii_digit().between(char('('), char(')')).skip(eof())
  let result = parser.parse(Input::new("(3)"))
  @test.assert_eq(result, Ok('3'))
  match parser.parse(Input::new("(3)\n")) {
    Err(error) => {
      @test.assert_eq(error.line(), 1)
      @test.assert_eq(error.column(), 4)
    }
    Ok(_) => @test.fail("expected trailing input error")
  }
}

///|
test "repetition rejects empty parser" {
  let parser : Parser[Input, Char] = pure('x')
  match parser.many().parse_partial(Input::new("abc")) {
    Err(error) =>
      @test.assert_eq(error.message_text(), "many parser accepted empty input")
    Ok(_) => @test.fail("expected empty parser repetition error")
  }
}

///|
test "take_while consumes contiguous matching input" {
  let parser = take_while("letters", Char::is_ascii_alphabetic)
  @test.assert_eq(
    parser.parse_partial(Input::new("abc123")),
    Ok(("abc", Input::new("abc123").advance_string("abc"))),
  )
  match parser.parse_partial(Input::new("123")) {
    Err(error) => {
      @test.assert_eq(error.offset(), 0)
      @test.assert_eq(error.expected(), ["letters"])
    }
    Ok(_) => @test.fail("expected take_while to reject empty match")
  }
}
