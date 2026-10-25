///|
using @talcparsec {
  type Input,
  type Parser,
  type ParserRaw,
  type ParseError,
  char,
  ascii_digit,
  ascii_letter,
  string,
  symbol,
  satisfy,
  take_while,
  many_chars,
  many_chars1,
  choice,
  eof,
  pure,
  fail,
  rest_of_line,
}

///|
test "monadic bind composes parsers" {
  let parser : Parser[Input, Char] = char('a').bind(_ => ascii_digit())
  let result = parser.parse(Input::new("a7"))
  @test.assert_eq(result, Ok('7'))
}

///|
test "method chain parses token list" {
  let identifier = ascii_letter()
    .some()
    .map(chars => String::from_array(chars))
    .lexeme()
  let parser : Parser[Input, Array[String]] = identifier.sep_by(symbol(","))
  let result = parser.parse(Input::new("foo, bar, baz"))
  @test.assert_eq(result, Ok(["foo", "bar", "baz"]))
}

///|
test "choice does not backtrack committed consumption" {
  let parser : Parser[Input, Char] = string("ab")
    .then(char('c'))
    .or(string("ab").then(char('d')))
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
  let parser : Parser[Input, Char] = string("ab")
    .then(char('c'))
    .attempt()
    .or(string("ab").then(char('d')))
  let result = parser.parse(Input::new("abd"))
  @test.assert_eq(result, Ok('d'))
}

///|
test "between and eof track line and column" {
  let parser : Parser[Input, Char] = ascii_digit()
    .between(char('('), char(')'))
    .skip(eof())
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
    Err(_) => ()
    Ok(_) => @test.fail("expected empty parser repetition error")
  }
}

///|
test "take_while consumes contiguous matching input" {
  let parser : Parser[Input, String] = take_while(
    "letters",
    Char::is_ascii_alphabetic,
  )
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
  let parser : Parser[Input, Char] = char('x')
    .not_followed_by("x")
    .then(char('a'))
  @test.assert_eq(parser.parse(Input::new("a")), Ok('a'))
}

///|
test "not_followed_by fails when inner parser succeeds" {
  let parser : Parser[Input, Char] = char('x')
    .not_followed_by("x")
    .then(char('a'))
  match parser.parse(Input::new("x")) {
    Err(_) => ()
    Ok(_) => @test.fail("expected not_followed_by to reject x")
  }
}

///|
test "not_followed_by guards repetition" {
  let any_char = satisfy("any", _ => true)
  let non_star = char('*').not_followed_by("'*'").then(any_char)
  let parser : Parser[Input, String] = char('*')
    .then(non_star.some().map(chars => String::from_array(chars)))
    .skip(char('*'))
  @test.assert_eq(parser.parse(Input::new("*bold*")), Ok("bold"))
}

///|
test "many_chars collects zero or more matches" {
  let not_newline : Parser[Input, Char] = satisfy("not newline", c => c != '\n')
  @test.assert_eq(many_chars(not_newline).parse(Input::new("")), Ok(""))
  @test.assert_eq(many_chars(not_newline).parse(Input::new("abc")), Ok("abc"))
  let (result, _) = many_chars(not_newline)
    .parse_partial(Input::new("abc\ndef"))
    .unwrap()
  @test.assert_eq(result, "abc")
}

///|
test "many_chars1 requires at least one match" {
  let digit : Parser[Input, Char] = ascii_digit()
  @test.assert_eq(many_chars1(digit).parse(Input::new("42")), Ok("42"))
  match many_chars1(digit).parse(Input::new("abc")) {
    Err(_) => ()
    Ok(_) => @test.fail("expected many_chars1 to reject no match")
  }
}

///|
test "many_until stops at terminator" {
  let body : Parser[Input, String] = ascii_digit().map(ch => ch.to_string())
  let terminator = char(';')
  let result = body.many_until(terminator).parse(Input::new("123;"))
  @test.assert_eq(result, Ok(["1", "2", "3"]))
}

///|
test "many_until returns empty on immediate terminator" {
  let body : Parser[Input, String] = ascii_digit().map(ch => ch.to_string())
  let terminator = char(';')
  let result = body.many_until(terminator).parse(Input::new(";"))
  @test.assert_eq(result, Ok([]))
}

///|
test "many_until returns accumulated when body fails" {
  let body : Parser[Input, String] = ascii_digit().map(ch => ch.to_string())
  let terminator = char(';')
  @test.assert_eq(
    body.many_until(terminator).parse(Input::new("123")),
    Ok(["1", "2", "3"]),
  )
}

///|
test "choice tries alternatives in order" {
  let parser : Parser[Input, Char] = choice([char('a'), char('b'), char('c')])
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
  let parser : Parser[Input, Char] = choice([
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
  let parser : Parser[Input, Char] = char('#')
    .then(char('a'))
    .then(char('b'))
    .attempt()
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
  let committed : Parser[Input, Char] = ParserRaw::new((input : Input) => {
    Err(ParseError::new(input, "x").with_commit())
  })
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
      @test.assert_eq(rest.remaining().to_owned(), "line2\r\n")
    }
    Err(_) => @test.fail("expected CRLF line to parse")
  }
}

///|
test "line positions use UTF-16 offsets after supplementary characters" {
  let input = Input::new("😀\nx\r\n😺\ny")
  @test.assert_eq(input.advance('😀').position(), {
    offset: 2,
    line: 1,
    column: 3,
  })
  @test.assert_eq(input.advance_string("😀\n").position(), {
    offset: 3,
    line: 2,
    column: 1,
  })
  @test.assert_eq(input.advance_string("😀\nx\r\n😺\n").position(), {
    offset: 9,
    line: 4,
    column: 1,
  })
  @test.assert_eq(input.advance_string("😀\nx\r\n😺\ny").position(), {
    offset: 10,
    line: 4,
    column: 2,
  })
}

///|
test "sep_by returns independent empty arrays" {
  let parser : Parser[Input, Array[Char]] = char('a').sep_by(char(','))
  let input = Input::new("")
  let first = parser.parse(input).unwrap()
  let second = parser.parse(input).unwrap()
  first.push('x')
  @test.assert_eq(second, [])
  @test.assert_eq(parser.parse(input), Ok([]))
}

///|
test "merging nested errors keeps each expected label once" {
  let input = Input::new("")
  let a = ParseError::new(input, "a")
  let b = ParseError::new(input, "b")
  let c = ParseError::new(input, "c")
  @test.assert_eq(a.merge(a.merge(b)).expected(), ["a", "b"])
  @test.assert_eq(a.merge(b).merge(a.merge(c)).expected(), ["a", "b", "c"])
  @test.assert_eq(a.merge(b).merge(b.merge(c)).expected(), ["a", "b", "c"])
  @test.assert_eq(a.merge(a).merge(b).expected(), ["a", "b"])
}

///|
test "choice merges errors like or before stopping on commitment" {
  let first : Parser[Input, Char] = string("#a").then(char('b')).attempt()
  let input = Input::new("#ax")
  for
    (second, expected) in [
      (char('#').then(char('z')), ["'b'"]),
      (string("#a").then(char('z')), ["'b'", "'z'"]),
    ] {
    let result = choice([first, second, pure('!')]).parse_partial(input)
    @test.assert_eq(result, first.or(second).or(pure('!')).parse_partial(input))
    guard result is Err(error) else {
      @test.fail("expected committed parse error")
    }
    @test.assert_eq(error.offset(), 2)
    @test.assert_eq(error.expected(), expected)
    @test.assert_eq(error.is_committed(), true)
  }
}

///|
test "parse commits trailing input errors only after consumption" {
  let input = Input::new("xab").advance('x')
  for
    (parser, offset, committed) in [(char('a'), 2, true), (pure('a'), 1, false)] {
    let result : Result[Char, ParseError] = parser.parse(input)
    @test.assert_eq(result, parser.skip(eof()).parse(input))
    guard result is Err(error) else {
      @test.fail("expected trailing input error")
    }
    @test.assert_eq(error.offset(), offset)
    @test.assert_eq(error.expected(), ["end of input"])
    @test.assert_eq(error.is_committed(), committed)
  }
}

///|
struct TokenCursor {
  index : Int
  source_offset : Int
}

///|
impl @talcparsec.Cursor for TokenCursor with fn cursor(self) {
  self.index
}

///|
impl @talcparsec.Cursor for TokenCursor with fn position(self) {
  { offset: self.source_offset, line: 1, column: self.source_offset + 1, }
}

///|
impl @talcparsec.Cursor for TokenCursor with fn is_at_eof(_self) {
  false
}

///|
test "label compares source offsets for token cursors" {
  let parser : Parser[TokenCursor, Unit] = fail("old")
  let input : TokenCursor = { index: 0, source_offset: 42, }
  guard parser.label("new").run(input) is Err(labeled) else {
    @test.fail("expected failure before token consumption")
  }
  @test.assert_eq(labeled.offset(), 42)
  @test.assert_eq(labeled.expected(), ["new"])
  @test.assert_eq(labeled.is_committed(), false)
  let token = @talcparsec.satisfy_input(
    (input : TokenCursor) => {
      Some(
        (
          (),
          { index: input.index + 1, source_offset: input.source_offset + 3, },
        ),
      )
    },
    "token",
    _ => true,
  )
  guard token.then(parser).label("new").run(input) is Err(error) else {
    @test.fail("expected failure after token consumption")
  }
  @test.assert_eq(error.offset(), 45)
  @test.assert_eq(error.expected(), ["old"])
  @test.assert_eq(error.is_committed(), true)
}

///|
test "character parsing preserves Unicode values and predicate calls" {
  let seen = []
  let parser : Parser[Input, Char] = satisfy("emoji", ch => {
    seen.push(ch)
    ch == '😀'
  })
  let input = Input::new("😀x")
  let rest = input.advance('😀')
  @test.assert_eq(input.next(), Some(('😀', rest)))
  @test.assert_eq(parser.parse_partial(input), Ok(('😀', rest)))
  guard parser.parse_partial(rest) is Err(error) else {
    @test.fail("expected rejected character")
  }
  @test.assert_eq(error.offset(), 2)
  @test.assert_eq(error.expected(), ["emoji"])
  @test.assert_eq(error.is_committed(), false)
  @test.assert_eq(parser.run(rest.advance('x')) is Err(_), true)
  @test.assert_eq(seen, ['😀', 'x'])
  @test.assert_eq(rest.advance('x').next(), None)
  let mapped : Parser[Input, String] = char('😀').string_map(text => {
    "[" + text + "]"
  })
  @test.assert_eq(mapped.parse(Input::new("😀")), Ok("[😀]"))
}

///|
test "skip returns the first value and preserves failure commitment" {
  let parser : Parser[Input, Char] = char('a').skip(char('b'))
  @test.assert_eq(parser.parse(Input::new("ab")), Ok('a'))
  for
    (parser, source, offset, committed) in [
      (parser, "ac", 1, true),
      (parser, "xb", 0, false),
      (pure('x').skip(char('b')), "a", 0, false),
    ] {
    guard parser.parse(Input::new(source)) is Err(error) else {
      @test.fail("expected skip failure")
    }
    @test.assert_eq(error.offset(), offset)
    @test.assert_eq(error.is_committed(), committed)
  }
  @test.assert_eq(
    parser.attempt().or(char('a').skip(char('c'))).parse(Input::new("ac")),
    Ok('a'),
  )
}

///|
test "merging errors preserves its inputs and message precedence" {
  let input = Input::new("")
  let a = ParseError::new(input, "a")
  let b = ParseError::new(input, "b")
  let c = ParseError::new(input, "c")
  let left = a.merge(b)
  let right = b.merge(c).with_commit()
  let merged = left.merge(right)
  @test.assert_eq(merged.expected(), ["a", "b", "c"])
  @test.assert_eq(merged.is_committed(), true)
  @test.assert_eq(left.expected(), ["a", "b"])
  @test.assert_eq(left.is_committed(), false)
  @test.assert_eq(right.expected(), ["b", "c"])
  let message = ParseError::message(input, "first")
    .merge(a.merge(b))
    .merge(ParseError::message(input, "second"))
  @test.assert_eq(message.expected(), ["a", "b"])
  @test.assert_eq(message.message_text(), "first")
}

///|
test "character collection preserves mapped values and repetition failures" {
  for
    (parser, source) in [
      (char('a').map(_ => '😀'), "aa!"),
      (string("ab").map(_ => 'x'), "ababc"),
      (char('a').then(char('b')), "abac"),
      (char('a').then(char('b')).attempt(), "abac"),
      (pure('x'), ""),
      (char('a'), ""),
    ] {
    let parser : Parser[Input, Char] = parser
    let input = Input::new(source)
    @test.assert_eq(
      many_chars(parser).parse_partial(input),
      parser.many().map(chars => String::from_array(chars)).parse_partial(input),
    )
    @test.assert_eq(
      many_chars1(parser).parse_partial(input),
      parser.some().map(chars => String::from_array(chars)).parse_partial(input),
    )
  }
}

///|
test "bulk scanners preserve Unicode and block boundaries" {
  @test.assert_eq(Input::new("").line_starts, [0])
  let skip : Parser[Input, Unit] = @talcparsec.skip_spaces()
  let controls = String::from_array([11, 12].map(cp => cp.to_char().unwrap()))
  for length in [0, 1, 7, 8, 9, 15, 16, 17, 31, 32] {
    let prefix = String::from_array(Array::make(length, ' '))
    let lines = Input::new(prefix + "\n😀\nx\r\n")
    @test.assert_eq(lines.line_starts, [0, length + 1, length + 4, length + 7])
    let whitespace = prefix + "\t\r\n" + controls + "  　"
    let input = Input::new(whitespace + "😀x")
    @test.assert_eq(
      skip.parse_partial(input),
      Ok(((), input.advance_string(whitespace))),
    )
  }
}

///|
test "character sets preserve ASCII boundaries and Unicode membership" {
  let chars = String::from_array(
      [0, 31, 32, 63, 64, 95, 96, 127].map(cp => cp.to_char().unwrap()),
    ) +
    "中😀"
  let included : Parser[Input, Char] = @talcparsec.one_of(chars)
  let excluded : Parser[Input, Char] = @talcparsec.none_of(chars)
  let candidates = [
    ..Array::makei(128, cp => cp.to_char().unwrap()),
    '中',
    '😀',
    '😺',
  ]
  for ch in candidates {
    let input = Input::new(ch.to_string())
    if chars.contains_char(ch) {
      @test.assert_eq(included.parse(input), Ok(ch))
      @test.assert_eq(excluded.parse(input) is Err(_), true)
    } else {
      @test.assert_eq(included.parse(input) is Err(_), true)
      @test.assert_eq(excluded.parse(input), Ok(ch))
    }
  }
}

///|
test "many_until preserves committed terminator failures unless attempted" {
  let body : Parser[Input, Char] = satisfy("character", _ => true)
  let terminator = char('a').then(char('b'))
  let input = Input::new("ac")
  guard body.many_until(terminator).parse(input) is Err(error) else {
    @test.fail("expected committed terminator failure")
  }
  @test.assert_eq(error.offset(), 1)
  @test.assert_eq(error.is_committed(), true)
  @test.assert_eq(
    body.many_until(terminator.attempt()).parse(input),
    Ok(['a', 'c']),
  )
}
