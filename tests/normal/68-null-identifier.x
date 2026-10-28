// `null` is an ordinary identifier, not a literal.
//
// The lexer used to map `null` to NULL_LIT, but no production accepted it
// (`isLit`/`isName` both excluded it), so `null` could be neither used nor
// declared. The spelling was removed (2026-10-28): the null pointer value is
// `ptr::null<T>()`, which the resolver/emitter implement as an intrinsic.
// A local named `null` is therefore legal like any other identifier.
import std/libc

func main(){
  let null = 7;
  assert(null == 7);
  let p: i8* = ptr::null<i8>();
  assert(is_null(p));
  print("null name ok\n");
}
