//regression: array/tuple literals in operand position (index base, field
//scope) reached eval_operand's empty Array/Tuple arms and errored with
//"eval_operand ..." instead of using the visited storage pointer.
func main(){
  assert(([10, 20, 30])[1] == 20);
  assert((10, 20).0 == 10);
  assert((10, 20).1 == 20);
  let t = (1, (2, 3));
  let u = t.1;
  assert(u.0 == 2);
  assert(u.1 == 3);
  print("literal operand done\n");
}
