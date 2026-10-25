//A for-each body that ends with `break` and leaves a live temp behind used
//to emit the loop scope's end-of-scope drops into the already terminated
//block. The verifier then rejected the module ("Basic Block ... does not
//have terminator! label %iflet_next_<line>") and LLVM's AlwaysInliner
//segfaulted on the same IR at -O2. The desugar ends the `while(true)` body
//with the opaque `std::internal_block!(id)`, so Exit reads the body as
//falling through; visit_while now records the real exit (via body_exit) on
//the ownership scope, and end_scope skips the dead drops like it does for a
//plain `while` body that breaks. See src/backend/stmt_emitter.x and
//Own::add_scope(.., exit).
import std/io
import std/string
import std/list

func main(){
  let l = List<String>::new();
  l.add(String::new("a"));
  l.add(String::new("b"));

  //the temp `t` belongs to the loop body: the break's own drop must be the
  //only one emitted on that path
  let s = String::new();
  for x in l{
    let t = format("{}!", x);
    s = t.clone();
    break;
  }
  assert(s.eq("a!"));

  //same shape with an if-let between the temp and the break (the original
  //report came from an if-let chain in std/hashmap)
  let l2 = List<String>::new();
  l2.add(String::new("x"));
  let r = String::new();
  for y in l2{
    let u = format("<{}>", y);
    if let Option<String>::Some(v) = Option<String>::new(u.clone()){
      r = v.clone();
    }
    break;
  }
  assert(r.eq("<x>"));

  //`continue` as the body's last statement is the same terminator shape: the
  //body-local temp is dropped by the continue itself, not after the branch
  let l3 = List<i32>::new();
  l3.add(1);
  l3.add(2);
  let n = 0;
  for z in l3{
    let w = format("[{}]", z);
    assert(w.len() > 2);
    n += 1;
    continue;
  }
  assert(n == 2);
  print("foreach break drop ok\n");
}
