///|
enum Token {
  Bullet
  ListText(String)
  Newline
  Indent
  Dedent
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
fn tokenize_markdown_list(source : String) -> Result[Array[Token], String] {
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
        return Err("inconsistent indentation")
      }
    }
    guard content.has_prefix("- ") else {
      return Err("expected an unordered-list marker")
    }
    let text = content.sub(start=2).to_owned()
    guard !text.is_empty() else { return Err("expected list-item text") }
    tokens.push(Bullet)
    tokens.push(ListText(text))
    tokens.push(Newline)
  }
  while indents.length() > 1 {
    ignore(indents.pop())
    tokens.push(Dedent)
  }
  Ok(tokens)
}

///|
fn token_error(input : TokenInput, expected : String) -> String {
  "expected " + expected + " at token " + input.offset.to_string()
}

///|
fn parse_list_items(
  input : TokenInput,
) -> Result[(Array[ListItem], TokenInput), String] {
  let items = Array::new()
  let mut rest = input
  while rest.peek() is Some(Bullet) {
    match parse_list_item(rest) {
      Ok((item, next)) => {
        items.push(item)
        rest = next
      }
      Err(error) => return Err(error)
    }
  }
  guard !items.is_empty() else { return Err(token_error(input, "list item")) }
  Ok((items, rest))
}

///|
fn parse_list_item(
  input : TokenInput,
) -> Result[(ListItem, TokenInput), String] {
  let rest = match input.peek() {
    Some(Bullet) => input.advance()
    _ => return Err(token_error(input, "'-'"))
  }
  let text = match rest.peek() {
    Some(ListText(text)) => text
    _ => return Err(token_error(rest, "list-item text"))
  }
  let rest = rest.advance()
  let rest = match rest.peek() {
    Some(Newline) => rest.advance()
    _ => return Err(token_error(rest, "newline"))
  }
  let (children, rest) = match rest.peek() {
    Some(Indent) =>
      match parse_list_items(rest.advance()) {
        Ok((items, after_children)) =>
          match after_children.peek() {
            Some(Dedent) => (items, after_children.advance())
            _ => return Err(token_error(after_children, "dedent"))
          }
        Err(error) => return Err(error)
      }
    _ => ([], rest)
  }
  Ok((Item(text, children), rest))
}

///|
fn parse_markdown_list(
  tokens : Array[Token],
) -> Result[Array[ListItem], String] {
  let input = { tokens, offset: 0 }
  match parse_list_items(input) {
    Ok((items, rest)) =>
      if rest.peek() is None {
        Ok(items)
      } else {
        Err(token_error(rest, "end of token stream"))
      }
    Err(error) => Err(error)
  }
}

///|
test "lex Markdown list indentation into virtual tokens" {
  @test.assert_eq(
    tokenize_markdown_list(
      (
        #|- groceries
        #|  - fruit
        #|- chores
      ),
    ),
    Ok([
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
    ]),
  )
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
  let result = tokenize_markdown_list(source).bind(parse_markdown_list)
  @test.assert_eq(
    result,
    Ok([
      Item("groceries", [
        Item("fruit", [Item("apples", []), Item("pears", [])]),
        Item("vegetables", []),
      ]),
      Item("chores", [Item("laundry", [])]),
    ]),
  )
}
