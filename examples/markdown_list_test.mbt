///|
enum Token {
  Bullet
  ListText(String)
  Newline
  Indent
  Dedent
} derive(Eq, Debug)

///|
suberror LayoutError {
  InconsistentIndentation
  ExpectedListMarker
  ExpectedListItemText
  ExpectedToken(expected~ : String, offset~ : Int)
} derive(Eq, Debug)

///|
struct TokenInput {
  tokens : Array[Token]
  offset : Int
}

///|
fn TokenInput::peek(self : TokenInput) -> Token? {
  self.tokens.get(self.offset)
}

///|
fn TokenInput::advance(self : TokenInput) -> TokenInput {
  { tokens: self.tokens, offset: self.offset + 1 }
}

///|
enum ListItem {
  Item(String, Array[ListItem])
} derive(Eq, Debug)

///|
fn tokenize_markdown_list(source : String) -> Array[Token] raise LayoutError {
  let tokens = Array::new()
  let indents = [0]
  for raw_line in source.split("\n") {
    let line = raw_line.trim_end()
    guard !line.is_empty() else { continue }
    let content = line.trim_start()
    let indentation = line.length() - content.length()
    let mut current_indentation = indents.last().unwrap()
    if indentation > current_indentation {
      indents.push(indentation)
      tokens.push(Indent)
    } else {
      while indentation < current_indentation {
        ignore(indents.pop())
        tokens.push(Dedent)
        current_indentation = indents.last().unwrap()
      }
      guard indentation == current_indentation else {
        raise InconsistentIndentation
      }
    }
    guard content.has_prefix("- ") else { raise ExpectedListMarker }
    let text = content.sub(start=2).to_owned()
    guard !text.is_empty() else { raise ExpectedListItemText }
    tokens.push(Bullet)
    tokens.push(ListText(text))
    tokens.push(Newline)
  }
  while indents.length() > 1 {
    ignore(indents.pop())
    tokens.push(Dedent)
  }
  tokens
}

///|
fn[T] token_error(input : TokenInput, expected : String) -> T raise LayoutError {
  raise ExpectedToken(expected~, offset=input.offset)
}

///|
fn parse_list_items(
  input : TokenInput,
) -> (Array[ListItem], TokenInput) raise LayoutError {
  let items = Array::new()
  let mut rest = input
  while rest.peek() is Some(Bullet) {
    let (item, next) = parse_list_item(rest)
    items.push(item)
    rest = next
  }
  guard !items.is_empty() else { token_error(input, "list item") }
  (items, rest)
}

///|
fn parse_list_item(
  input : TokenInput,
) -> (ListItem, TokenInput) raise LayoutError {
  guard input.peek() is Some(Bullet) else { token_error(input, "'-'") }
  let rest = input.advance()
  guard rest.peek() is Some(ListText(text)) else {
    token_error(rest, "list-item text")
  }
  let rest = rest.advance()
  guard rest.peek() is Some(Newline) else { token_error(rest, "newline") }
  let rest = rest.advance()
  let (children, rest) = match rest.peek() {
    Some(Indent) => {
      let (items, after_children) = parse_list_items(rest.advance())
      guard after_children.peek() is Some(Dedent) else {
        token_error(after_children, "dedent")
      }
      (items, after_children.advance())
    }
    _ => ([], rest)
  }
  (Item(text, children), rest)
}

///|
fn parse_markdown_list(
  tokens : Array[Token],
) -> Array[ListItem] raise LayoutError {
  let input = { tokens, offset: 0 }
  let (items, rest) = parse_list_items(input)
  guard rest.peek() is None else { token_error(rest, "end of token stream") }
  items
}

///|
test "lex Markdown list indentation into virtual tokens" {
  let source =
    #|- groceries
    #|  - fruit
    #|- chores
  @test.assert_eq(tokenize_markdown_list(source), [
    Bullet,
    ListText("groceries"),
    Newline,
    Indent,
    Bullet,
    ListText("fruit"),
    Newline,
    Dedent,
    Bullet,
    ListText("chores"),
    Newline,
  ])
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
  @test.assert_eq(parse_markdown_list(tokenize_markdown_list(source)), [
    Item("groceries", [
      Item("fruit", [Item("apples", []), Item("pears", [])]),
      Item("vegetables", []),
    ]),
    Item("chores", [Item("laundry", [])]),
  ])
}
