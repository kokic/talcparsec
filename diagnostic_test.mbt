///|
/// Generic error combinator usable with any `E : Commit + CanMerge`.
fn[E : @talcparsec.Commit + @talcparsec.CanMerge] commit_then_merge(
  first : E,
  second : E,
) -> E {
  guard !@talcparsec.Commit::is_committed(first) else { first }
  @talcparsec.CanMerge::merge(first, second)
}

///|
test "trait-based generic error handling" {
  let err_a = ParseError::new(Input::new("x"), "a")
  let err_b = ParseError::new(Input::new("y"), "b")
  let committed = ParseError::new(Input::new("x"), "a").with_commit()
  let r1 = commit_then_merge(committed, err_b)
  @test.assert_eq(@talcparsec.Commit::is_committed(r1), true)
  let r2 = commit_then_merge(err_a, err_b)
  @test.assert_eq(@talcparsec.Positioned::error_offset(r2), 0)
}
