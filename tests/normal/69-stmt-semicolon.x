// A ";" after a block-like statement.
//
// `if`, `if let`, `match`, a bare block, `while` and `for` all end in a body
// block, so their statement form did not consume a trailing ";" (the block
// parser's fast path added the expression as a statement and left the ";" for
// the next iteration, where parse_expr rejected it: "invalid expr ';'").
// The generic statement path already accepted one for expression statements.
import std/it

enum E{
  A,
  B,
}

func pick(e: E): i32{
  if let E::A = e{
    return 1;
  };
  return 2;
}

func main(){
  if(true){
    print("if\n");
  };
  {
    print("block\n");
  };
  let i = 0;
  while (i < 2){
    ++i;
  };
  let arr = [1, 2];
  for j in arr{
    print("for {}\n", j);
  };
  let e = E::A{};
  match e{
    E::A => { print("A\n"); },
    E::B => { print("B\n"); }
  };
  assert(pick(e) == 1);
  //the same statements without the ";" keep working (tail position)
  let t = {
    let n = 3;
    n
  };
  assert(t == 3);
  print("stmt semicolon ok\n");
}
