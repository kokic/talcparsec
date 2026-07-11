///|
pub fn[T] array_cons(tail : Array[T], head : T) -> Array[T] {
  Array::new(capacity=tail.length() + 1)..push(head)..append(tail)
}
