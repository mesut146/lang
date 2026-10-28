// Unary "~" (bitwise complement).
//
// TILDE was a token with no unary production, so `~x` was a parse error
// ("invalid expr '~'"). The emitter already had the instruction (xor with -1)
// and the resolver treated it as an integer unary; only the parser production
// and an integer-only guard were missing.
func main(){
  let x = 5;
  assert(~x == -6);
  assert(~~x == 5);
  //unsigned: the complement is taken at the value's own width
  let u: u8 = 0;
  assert(~u == 255);
  //binds tighter than infix operators
  assert(~x + 1 == -5);
  assert((~x + 1) * 2 == -10);
  let y = ~x;
  assert(y == -6);
  print("unary tilde ok\n");
}
