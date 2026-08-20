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

///|
test "not_followed_by succeeds when inner parser fails" {
  let parser = char('x').not_followed_by("x").then(char('a'))
  @test.assert_eq(parser.parse(Input::new("a")), Ok('a'))
}

///|
test "not_followed_by fails when inner parser succeeds" {
  let parser = char('x').not_followed_by("x").then(char('a'))
  match parser.parse(Input::new("x")) {
    Err(error) => @test.assert_eq(error.message_text(), "unexpected x")
    Ok(_) => @test.fail("expected not_followed_by to reject x")
  }
}

///|
test "not_followed_by guards repetition" {
  let any_char = satisfy("any", fn(_) { true })
  let non_star = char('*').not_followed_by("'*'").then(any_char)
  let parser = char('*')
    .then(non_star.some().map(chars => String::from_array(chars)))
    .skip(char('*'))
  @test.assert_eq(parser.parse(Input::new("*bold*")), Ok("bold"))
}

///|
test "many_chars collects zero or more matches" {
  let not_newline = satisfy("not newline", fn(c) { c != '\n' })
  @test.assert_eq(many_chars(not_newline).parse(Input::new("")), Ok(""))
  @test.assert_eq(many_chars(not_newline).parse(Input::new("abc")), Ok("abc"))
  let (result, _) = many_chars(not_newline)
    .parse_partial(Input::new("abc\ndef"))
    .unwrap()
  @test.assert_eq(result, "abc")
}

///|
test "many_chars1 requires at least one match" {
  let digit = ascii_digit()
  @test.assert_eq(many_chars1(digit).parse(Input::new("42")), Ok("42"))
  match many_chars1(digit).parse(Input::new("abc")) {
    Err(_) => ()
    Ok(_) => @test.fail("expected many_chars1 to reject no match")
  }
}

///|
test "many_until stops at terminator" {
  let body = ascii_digit().map(ch => ch.to_string())
  let terminator = char(';')
  let result = body.many_until(terminator).parse(Input::new("123;"))
  @test.assert_eq(result, Ok(["1", "2", "3"]))
}

///|
test "many_until returns empty on immediate terminator" {
  let body = ascii_digit().map(ch => ch.to_string())
  let terminator = char(';')
  let result = body.many_until(terminator).parse(Input::new(";"))
  @test.assert_eq(result, Ok([]))
}

///|
test "many_until returns accumulated when body fails" {
  let body = ascii_digit().map(ch => ch.to_string())
  let terminator = char(';')
  @test.assert_eq(
    body.many_until(terminator).parse(Input::new("123")),
    Ok(["1", "2", "3"]),
  )
}

///|
test "choice tries alternatives in order" {
  let parser = choice([char('a'), char('b'), char('c')])
  @test.assert_eq(parser.parse(Input::new("a")), Ok('a'))
  @test.assert_eq(parser.parse(Input::new("b")), Ok('b'))
  @test.assert_eq(parser.parse(Input::new("c")), Ok('c'))
  match parser.parse(Input::new("x")) {
    Err(error) => @test.assert_eq(error.expected().contains("'a'"), true)
    Ok(_) => @test.fail("expected choice to fail on no match")
  }
}

///|
test "choice preserves commit on backtrack" {
  let parser = choice([
    string("ab").then(char('c')),
    string("ab").then(char('d')),
  ])
  match parser.parse(Input::new("abd")) {
    Err(error) => @test.assert_eq(error.is_committed(), true)
    Ok(_) => @test.fail("expected committed parse error")
  }
}

///|
test "merge preserves commit across differing offsets" {
  let parser = char('#').then(char('a')).then(char('b')).attempt()
    .or(char('#').then(char('z')))
    .or(char('#'))
  match parser.parse(Input::new("#ax")) {
    Err(error) => {
      @test.assert_eq(error.is_committed(), true)
      @test.assert_eq(error.offset(), 2)
    }
    Ok(_) => @test.fail("expected committed parse error")
  }
}

///|
test "label preserves committed flag" {
  let committed = ParserRaw::new((input : Input) =>
    Err(ParseError::new(input, "x").with_commit()))
  match committed.label("y").parse(Input::new("abc")) {
    Err(error) => @test.assert_eq(error.is_committed(), true)
    Ok(_) => @test.fail("expected failure")
  }
}

///|
test "line parsers handle CRLF" {
  @test.assert_eq(rest_of_line.parse(Input::new("abc\r\n")), Ok("abc\n"))
  match rest_of_line.parse_partial(Input::new("line1\r\nline2\r\n")) {
    Ok((line, rest)) => {
      @test.assert_eq(line, "line1\n")
      @test.assert_eq(rest.remaining().to_string(), "line2\r\n")
    }
    Err(_) => @test.fail("expected CRLF line to parse")
  }
}
