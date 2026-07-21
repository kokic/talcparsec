///|
enum Token {
  Item(String)
  Indent
  Dedent
} derive(Eq, Debug)

///|
struct LocatedToken {
  token : Token
  position : @talcparsec.Position
} derive(Eq, Debug)

///|
struct LexedTokens {
  tokens : Array[LocatedToken]
  eof_position : @talcparsec.Position
}

///|
struct ListLine {
  indentation : Int
  text : String
  position : @talcparsec.Position
} derive(Eq, Debug)

///|
struct ScannedLines {
  lines : Array[ListLine]
  eof_position : @talcparsec.Position
}

///|
suberror LayoutError {
  InconsistentIndentation
  ExpectedListMarker
  ExpectedListItemText
} derive(Eq, Debug)

///|
struct TokenInput {
  tokens : Array[LocatedToken]
  offset : Int
  eof_position : @talcparsec.Position
}

///|
fn TokenInput::new(tokens : LexedTokens) -> TokenInput {
  { tokens: tokens.tokens, offset: 0, eof_position: tokens.eof_position }
}

///|
fn TokenInput::next(self : TokenInput) -> (LocatedToken, TokenInput)? {
  match self.tokens.get(self.offset) {
    Some(token) => Some((token, { ..self, offset: self.offset + 1 }))
    None => None
  }
}

///|
impl @talcparsec.Cursor for TokenInput with fn cursor(self) {
  self.offset
}

///|
impl @talcparsec.Cursor for TokenInput with fn position(self) {
  match self.tokens.get(self.offset) {
    Some(token) => token.position
    None => self.eof_position
  }
}

///|
impl @talcparsec.Cursor for TokenInput with fn is_at_eof(self) {
  self.offset >= self.tokens.length()
}

///|
enum ListItem {
  Item(String, Array[ListItem])
} derive(Eq, Debug)

///|
fn source_position(
  offset : Int,
  line : Int,
  column : Int,
) -> @talcparsec.Position {
  { offset, line, column }
}

///|
fn parse_line_content(content : StringView) -> String raise LayoutError {
  guard content.has_prefix("- ") else { raise ExpectedListMarker }
  let text = content.sub(start=2).to_owned()
  guard !text.is_empty() else { raise ExpectedListItemText }
  text
}

///|
fn adjust_indentation(
  indents : Array[Int],
  indentation : Int,
  position : @talcparsec.Position,
  tokens : Array[LocatedToken],
) -> Unit raise LayoutError {
  let mut current = indents.last().unwrap()
  if indentation > current {
    indents.push(indentation)
    tokens.push({ token: Indent, position })
  } else {
    while indentation < current {
      ignore(indents.pop())
      tokens.push({ token: Dedent, position })
      current = indents.last().unwrap()
    }
    guard indentation == current else { raise InconsistentIndentation }
  }
}

///|
fn close_remaining_indents(
  indents : Array[Int],
  tokens : Array[LocatedToken],
  eof_position : @talcparsec.Position,
) -> Unit {
  while indents.length() > 1 {
    ignore(indents.pop())
    tokens.push({ token: Dedent, position: eof_position })
  }
}

///|
fn scan_list_line(
  raw_line : StringView,
  line_start : @talcparsec.Input,
) -> ListLine? raise LayoutError {
  let line = raw_line.trim_end()
  guard !line.is_empty() else { None }
  let content = line.trim_start(chars=" ")
  let indentation = line.length() - content.length()
  let text = parse_line_content(content)
  Some({
    indentation,
    text,
    position: source_position(
      line_start.offset() + indentation,
      line_start.line(),
      indentation + 1,
    ),
  })
}

///|
fn advance_source_line(
  input : @talcparsec.Input,
  raw_line : StringView,
  has_newline : Bool,
) -> @talcparsec.Input {
  let input = input.advance_string(raw_line.to_owned())
  guard has_newline else { input }
  input.advance_string("\n")
}

///|
fn scan_markdown_list(source : String) -> ScannedLines raise LayoutError {
  let scanned_lines = Array::new()
  let raw_lines = source.split("\n").to_array()
  let mut input = @talcparsec.Input::new(source)
  for index in 0..<raw_lines.length() {
    let raw_line = raw_lines[index]
    guard scan_list_line(raw_line, input) is Some(line) else {  }
    scanned_lines.push(line)
    input = advance_source_line(input, raw_line, index + 1 < raw_lines.length())
  }
  { lines: scanned_lines, eof_position: input.position() }
}

///|
fn apply_layout(lines : ScannedLines) -> LexedTokens raise LayoutError {
  let tokens = Array::new(capacity=lines.lines.length())
  let indents = [0]
  for line in lines.lines {
    adjust_indentation(indents, line.indentation, line.position, tokens)
    tokens.push({ token: Item(line.text), position: line.position })
  }
  close_remaining_indents(indents, tokens, lines.eof_position)
  { tokens, eof_position: lines.eof_position }
}

///|
fn tokenize_markdown_list(source : String) -> LexedTokens raise LayoutError {
  apply_layout(scan_markdown_list(source))
}

///|
type TokenParser[T] = @talcparsec.Parser[TokenInput, T]

///|
fn layout_token(
  expected : String,
  predicate : (Token) -> Bool,
) -> TokenParser[Token] {
  @talcparsec.satisfy_input(TokenInput::next, expected, token => {
    predicate(token.token)
  }).map(token => token.token)
}

///|
fn item_parser() -> TokenParser[String] {
  layout_token("list item", token => token is Item(_)).map(token => {
    match token {
      Item(text) => text
      _ => ""
    }
  })
}

///|
fn indent_parser() -> TokenParser[Unit] {
  layout_token("indent", token => token is Indent).map(_ => ())
}

///|
fn dedent_parser() -> TokenParser[Unit] {
  layout_token("dedent", token => token is Dedent).map(_ => ())
}

///|
fn nested_list_parser() -> TokenParser[Array[ListItem]] {
  @talcparsec.delay(list_parser).between(indent_parser(), dedent_parser())
}

///|
fn list_item_parser() -> TokenParser[ListItem] {
  item_parser().bind(text => {
    nested_list_parser()
    .optional()
    .map(children => Item(text, children.unwrap_or([])))
  })
}

///|
fn list_parser() -> TokenParser[Array[ListItem]] {
  @talcparsec.delay(list_item_parser).some()
}

///|
fn parse_markdown_list(
  tokens : LexedTokens,
) -> Result[Array[ListItem], @talcparsec.ParseError] {
  list_parser().skip(@talcparsec.eof()).parse(TokenInput::new(tokens))
}

///|
test "scan Markdown list lines before applying layout" {
  let source =
    #|- groceries
    #|  - fruit
  @test.assert_eq(scan_markdown_list(source).lines, [
    { indentation: 0, text: "groceries", position: source_position(0, 1, 1) },
    { indentation: 2, text: "fruit", position: source_position(14, 2, 3) },
  ])
}

///|
test "apply indentation as virtual tokens" {
  let source =
    #|- groceries
    #|  - fruit
    #|- chores
  let tokens = tokenize_markdown_list(source)
  @test.assert_eq(tokens.tokens.map(token => token.token), [
    Item("groceries"),
    Indent,
    Item("fruit"),
    Dedent,
    Item("chores"),
  ])
}

///|
test "blank lines do not affect layout" {
  let source =
    #|- groceries
    #|
    #|  - fruit
    #|
    #|- chores
  @test.assert_eq(
    tokenize_markdown_list(source).tokens.map(token => token.token),
    [Item("groceries"), Indent, Item("fruit"), Dedent, Item("chores")],
  )
}

///|
test "one line can close multiple layout contexts" {
  let source =
    #|- groceries
    #|  - fruit
    #|    - apples
    #|- chores
  @test.assert_eq(
    tokenize_markdown_list(source).tokens.map(token => token.token),
    [
      Item("groceries"),
      Indent,
      Item("fruit"),
      Indent,
      Item("apples"),
      Dedent,
      Dedent,
      Item("chores"),
    ],
  )
}

///|
test "reject indentation that does not match an enclosing level" {
  @test.assert_raise(() => {
    tokenize_markdown_list("- groceries\n  - fruit\n - vegetables")
  })
}

///|
test "only spaces are accepted as indentation" {
  @test.assert_raise(() => tokenize_markdown_list("- groceries\n\t- fruit"))
}

///|
test "parse nested Markdown unordered list from tokens" {
  let source =
    #|- groceries
    #|  - fruit
    #|    - apples
    #|    - pears
    #|  - vegetables
    #|- chores
    #|  - laundry
  @test.assert_eq(
    parse_markdown_list(tokenize_markdown_list(source)),
    Ok([
      Item("groceries", [
        Item("fruit", [Item("apples", []), Item("pears", [])]),
        Item("vegetables", []),
      ]),
      Item("chores", [Item("laundry", [])]),
    ]),
  )
}

///|
test "token parser reports lexer positions" {
  let tokens = {
    tokens: [{ token: Indent, position: source_position(4, 2, 3) }],
    eof_position: source_position(6, 2, 5),
  }
  match parse_markdown_list(tokens) {
    Err(error) => {
      @test.assert_eq(error.offset(), 4)
      @test.assert_eq(error.line(), 2)
      @test.assert_eq(error.column(), 3)
      @test.assert_eq(error.expected(), ["list item"])
    }
    Ok(_) => @test.fail("expected a token parser error")
  }
}
