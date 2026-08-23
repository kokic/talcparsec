///|
/// AST types
enum Inline {
  Plain(String)
  Strong(Array[Inline])
  Emph(Array[Inline])
  Code(String)
  Link(Array[Inline], String)
  Image(String, String)
} derive(Eq, Debug)

///|
enum Block {
  Heading(Int, Array[Inline])
  Paragraph(Array[Inline])
  Blockquote(Array[Block])
  UnorderedList(Array[MdListItem])
  OrderedList(Array[MdListItem])
  FencedCode(String?, String)
  ThematicBreak
} derive(Eq, Debug)

///|
struct MdListItem {
  content : Array[Inline]
  children : Array[Block]
} derive(Eq, Debug)

///|
/// Inline parsers
pub let special_chars = "]*_`[!\\"

///|
pub fn delim(c : Char) -> @talc.StringParser[Unit] {
  @talc.char(c).not_followed_by("'\{c}'")
}

///|
pub type InlineParser = @talc.StringParser[Inline]

///|
pub type BlockParser = @talc.StringParser[Block]

///|
pub type SParser = @talc.StringParser[String]

///|
let open_bracket : @talc.StringParser[Char] = @talc.char('[')

///|
let close_bracket : @talc.StringParser[Char] = @talc.char(']')

///|
let escaped : InlineParser = @talc.char('\\')
  .then(@talc.one_of(special_chars))
  .map(c => Plain(c.to_string()))

///|
let code_span : InlineParser = @talc.char('`')
  .then(@talc.many_chars(@talc.none_of("`")))
  .skip(@talc.char('`'))
  .map(c => Code(c))

///|
let link_url : SParser = @talc.char('(')
  .then(@talc.many_chars(@talc.none_of(")")))
  .skip(@talc.char(')'))

///|
fn link() -> InlineParser {
  open_bracket
  .then(delim(']').then(inline()).some())
  .skip(close_bracket)
  .bind(text => link_url.map(url => Link(text, url)))
}

///|
let image : InlineParser = @talc.char('!')
  .then(open_bracket)
  .then(@talc.many_chars(@talc.none_of("]")))
  .skip(close_bracket)
  .bind(alt => link_url.map(url => Image(alt, url)))

///|
fn strong() -> InlineParser {
  let star = @talc.char('*')
  star.then(delim('*').then(inline()).some()).skip(star).map(c => Strong(c))
}

///|
fn emph() -> InlineParser {
  let underline = @talc.char('_')
  underline
  .then(delim('_').then(inline()).some())
  .skip(underline)
  .map(c => Emph(c))
}

///|
let plain_char : InlineParser = {
  let non_special = @talc.none_of(special_chars)
  non_special.bind(c => {
    @talc.many_chars(non_special).map(rest => Plain("\{c}\{rest}"))
  })
}

///|
fn inline() -> InlineParser {
  @talc.delay(() => {
    @talc.choice([
      escaped,
      image,
      link(),
      strong(),
      emph(),
      code_span,
      plain_char,
    ])
  })
}

///|
fn parse_inlines(text : String) -> Result[Array[Inline], @talc.ParseError] {
  inline().some().parse(@talc.Input::new(text))
}

///|
let blank_line : @talc.StringParser[Unit] = {
  let ws_no_nl = @talc.satisfy("non-newline whitespace", c => {
    Char::is_whitespace(c) && c != '\n'
  })
  @talc.many_chars(ws_no_nl).skip(@talc.newline).map(_ => ())
}

///|
let thematic_break : BlockParser = @talc.string("---")
  .then(@talc.char('-').many())
  .skip(@talc.newline)
  .map(_ => ThematicBreak)

///|
let heading : BlockParser = @talc.char('#')
  .some()
  .bind(hashes => {
    @talc.space.bind(_ => {
      @talc.Parser::new(input => {
        let (text, rest) = match @talc.line_content.run(input) {
          Ok(result) => result
          Err(error) => return Err(error)
        }
        let inlines = match parse_inlines(text) {
          Ok(inlines) => inlines
          Err(error) => return Err(error)
        }
        Ok((Heading(hashes.length(), inlines), rest))
      })
    })
  })

///|
let fenced_code : BlockParser = {
  let not_nl = @talc.not_newline
  @talc.string("```")
  .then(@talc.many_chars1(not_nl).optional())
  .skip(@talc.newline)
  .bind(lang => {
    let terminator = @talc.string("```").skip(@talc.newline)
    @talc.rest_of_line
    .many_until(terminator)
    .map(lines => FencedCode(lang, lines.join("")))
  })
}

///|
/// Quote
let quoted_line : SParser = @talc.char('>')
  .then(@talc.space.optional())
  .then(@talc.rest_of_line)

///|
fn blockquote() -> BlockParser {
  quoted_line
  .some()
  .bind(lines => {
    @talc.Parser::new(input => {
      block()
      .some()
      .parse(@talc.Input::new(lines.join("")))
      .map(blocks => (Blockquote(blocks), input))
    })
  })
}

///|
/// Paragraph
let paragraph_line : SParser = blank_line
  .not_followed_by("blank line")
  .then(delim('#'))
  .then(@talc.string("---").not_followed_by("\"---\""))
  .then(@talc.string("```").not_followed_by("\"```\""))
  .then(delim('>'))
  .then(@talc.char('-').then(@talc.space).not_followed_by("'- '"))
  .then(@talc.char('+').then(@talc.space).not_followed_by("'+ '"))
  .then(@talc.rest_of_line)

///|
let paragraph : BlockParser = paragraph_line
  .some()
  .bind(lines => {
    let text = lines.join("").trim_end().to_owned()
    @talc.Parser::new(input => {
      parse_inlines(text).map(inlines => (Paragraph(inlines), input))
    })
  })

///|
/// Lists
fn list_item(marker : Char, indent : Int) -> @talc.StringParser[MdListItem] {
  let istr = String::repeat(" ", indent)
  @talc.string(istr)
  .then(@talc.char(marker))
  .skip(@talc.space)
  .bind(_ => {
    @talc.Parser::new(input => {
      let (text, rest) = match @talc.line_content.run(input) {
        Ok(result) => result
        Err(error) => return Err(error)
      }
      let content = match parse_inlines(text) {
        Ok(content) => content
        Err(error) => return Err(error)
      }
      let subitems = sub_list(indent + 2).many()
      let after_newline = match @talc.newline.run(rest) {
        Ok(pair) => pair.1
        Err(_) => rest
      }
      let (children, rest2) = match subitems.run(after_newline) {
        Ok(result) => result
        Err(error) => return Err(error)
      }
      Ok(({ content, children }, rest2))
    })
  })
}

///|
fn unordered_list_at(indent : Int) -> BlockParser {
  list_item('-', indent).some().map(items => UnorderedList(items))
}

///|
fn ordered_list_at(indent : Int) -> BlockParser {
  list_item('+', indent).some().map(items => OrderedList(items))
}

///|
fn sub_list(indent : Int) -> BlockParser {
  @talc.choice([unordered_list_at(indent), ordered_list_at(indent)])
}

///|
let unordered_list : BlockParser = unordered_list_at(0)

///|
let ordered_list : BlockParser = ordered_list_at(0)

///|
/// Document
fn block() -> BlockParser {
  @talc.choice([
    thematic_break,
    heading,
    fenced_code,
    blockquote(),
    unordered_list,
    ordered_list,
    paragraph,
  ])
}

///|
let block_sep : @talc.StringParser[Array[Unit]] = blank_line.some()

///|
let blanks : @talc.StringParser[Array[Unit]] = blank_line.many()

///|
let document : @talc.StringParser[Array[Block]] = blanks
  .then(block().sep_by(block_sep))
  .skip(blanks)
  .skip(@talc.eof())

///|
test "full document" {
  let markdown =
    #|# Title
    #|
    #|A paragraph with *strong*, _emph_, `code`, a [link](u) and an ![img](i.png).
    #|
    #|---
    #|
    #|> A *quote* with `code`
    #|> in two lines
    #|
    #|```python
    #|print("hello")
    #|```
    #|
    #|- first item
    #|- second with *nested*
    #|  - sub-item
    #|  - another sub
    #|
  @test.assert_eq(
    document.parse(@talc.Input::new(markdown)),
    Ok([
      Heading(1, [Plain("Title")]),
      Paragraph([
        Plain("A paragraph with "),
        Strong([Plain("strong")]),
        Plain(", "),
        Emph([Plain("emph")]),
        Plain(", "),
        Code("code"),
        Plain(", a "),
        Link([Plain("link")], "u"),
        Plain(" and an "),
        Image("img", "i.png"),
        Plain("."),
      ]),
      ThematicBreak,
      Blockquote([
        Paragraph([
          Plain("A "),
          Strong([Plain("quote")]),
          Plain(" with "),
          Code("code"),
          Plain("\nin two lines"),
        ]),
      ]),
      FencedCode(Some("python"), "print(\"hello\")\n"),
      UnorderedList([
        { content: [Plain("first item")], children: [] },
        {
          content: [Plain("second with "), Strong([Plain("nested")])],
          children: [
            UnorderedList([
              { content: [Plain("sub-item")], children: [] },
              { content: [Plain("another sub")], children: [] },
            ]),
          ],
        },
      ]),
    ]),
  )
}

///|
test "escaped character" {
  @test.assert_eq(escaped.parse(@talc.Input::new("\\*")), Ok(Plain("*")))
  @test.assert_eq(escaped.parse(@talc.Input::new("\\\\")), Ok(Plain("\\")))
  match escaped.parse(@talc.Input::new("\\a")) {
    Err(_) => ()
    Ok(_) => @test.fail("expected fail on non-special char")
  }
}

///|
test "code span" {
  @test.assert_eq(code_span.parse(@talc.Input::new("`code`")), Ok(Code("code")))
  @test.assert_eq(code_span.parse(@talc.Input::new("``")), Ok(Code("")))
}

///|
test "strong and emph" {
  @test.assert_eq(
    strong().parse(@talc.Input::new("*bold*")),
    Ok(Strong([Plain("bold")])),
  )
  @test.assert_eq(
    emph().parse(@talc.Input::new("_italic_")),
    Ok(Emph([Plain("italic")])),
  )
  @test.assert_eq(
    strong().parse(@talc.Input::new("*bold _and_ italic*")),
    Ok(Strong([Plain("bold "), Emph([Plain("and")]), Plain(" italic")])),
  )
}

///|
test "link and image" {
  @test.assert_eq(
    link().parse(@talc.Input::new("[text](url)")),
    Ok(Link([Plain("text")], "url")),
  )
  @test.assert_eq(
    image.parse(@talc.Input::new("![alt](img.png)")),
    Ok(Image("alt", "img.png")),
  )
}

///|
test "inline plain text and mixed" {
  @test.assert_eq(parse_inlines("hello"), Ok([Plain("hello")]))
  @test.assert_eq(
    parse_inlines("hello *world*"),
    Ok([Plain("hello "), Strong([Plain("world")])]),
  )
  @test.assert_eq(
    parse_inlines("a `b` c"),
    Ok([Plain("a "), Code("b"), Plain(" c")]),
  )
}

///|
test "thematic break" {
  @test.assert_eq(
    thematic_break.parse(@talc.Input::new("---\n")),
    Ok(ThematicBreak),
  )
  @test.assert_eq(
    thematic_break.parse(@talc.Input::new("--------\n")),
    Ok(ThematicBreak),
  )
}

///|
test "heading" {
  @test.assert_eq(
    heading.skip(@talc.newline).parse(@talc.Input::new("# Title\n")),
    Ok(Heading(1, [Plain("Title")])),
  )
  @test.assert_eq(
    heading.skip(@talc.newline).parse(@talc.Input::new("### Sub *bold*\n")),
    Ok(Heading(3, [Plain("Sub "), Strong([Plain("bold")])])),
  )
}

///|
test "fenced code" {
  @test.assert_eq(
    fenced_code.parse(@talc.Input::new("```\ncode\n```\n")),
    Ok(FencedCode(None, "code\n")),
  )
  @test.assert_eq(
    fenced_code.parse(@talc.Input::new("```\nline1\nline2\n```\n")),
    Ok(FencedCode(None, "line1\nline2\n")),
  )
  @test.assert_eq(
    fenced_code.parse(@talc.Input::new("```rust\nfn main() {}\n```\n")),
    Ok(FencedCode(Some("rust"), "fn main() {}\n")),
  )
}

///|
test "paragraph" {
  @test.assert_eq(
    paragraph.parse(@talc.Input::new("hello world\n")),
    Ok(Paragraph([Plain("hello world")])),
  )
  @test.assert_eq(
    paragraph.parse(@talc.Input::new("hello *world* ok\n")),
    Ok(Paragraph([Plain("hello "), Strong([Plain("world")]), Plain(" ok")])),
  )
}

///|
test "blockquote" {
  @test.assert_eq(
    blockquote().parse(@talc.Input::new("> hello\n> *world*\n")),
    Ok(Blockquote([Paragraph([Plain("hello\n"), Strong([Plain("world")])])])),
  )
}

///|
test "unordered list" {
  @test.assert_eq(
    unordered_list.parse(@talc.Input::new("- one\n- two\n")),
    Ok(
      UnorderedList([
        { content: [Plain("one")], children: [] },
        { content: [Plain("two")], children: [] },
      ]),
    ),
  )
}

///|
test "ordered list" {
  @test.assert_eq(
    ordered_list.parse(@talc.Input::new("+ first\n+ second\n")),
    Ok(
      OrderedList([
        { content: [Plain("first")], children: [] },
        { content: [Plain("second")], children: [] },
      ]),
    ),
  )
}

///|
test "nested list" {
  @test.assert_eq(
    unordered_list.parse(@talc.Input::new("- a\n  - b\n  - c\n")),
    Ok(
      UnorderedList([
        {
          content: [Plain("a")],
          children: [
            UnorderedList([
              { content: [Plain("b")], children: [] },
              { content: [Plain("c")], children: [] },
            ]),
          ],
        },
      ]),
    ),
  )
}

///|
test "document with fenced code and blockquote" {
  let md = "> quote\n\n```\ncode\n```\n"
  @test.assert_eq(
    document.parse(@talc.Input::new(md)),
    Ok([Blockquote([Paragraph([Plain("quote")])]), FencedCode(None, "code\n")]),
  )
}

///|
test "document with thematic break" {
  let md = "a\n\n---\n\nb\n"
  @test.assert_eq(
    document.parse(@talc.Input::new(md)),
    Ok([Paragraph([Plain("a")]), ThematicBreak, Paragraph([Plain("b")])]),
  )
}

///|
test "strict mode: unmatched delimiter fails" {
  match parse_inlines("*unclosed") {
    Err(_) => ()
    Ok(_) => @test.fail("expected fail on unmatched '*'")
  }
}
