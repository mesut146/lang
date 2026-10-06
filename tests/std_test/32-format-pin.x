//pins the print-family output behavior: format() string building with
//{} placeholders over int/str/multiple args, plus printf smoke. These guard
//any future unification of the printf/print/sprintf paths.
func main(){
  let a = format("n={}", 42);
  assert_eq(a.str(), "n=42");
  let b = format("{} + {} = {}", 1, 2, 3);
  assert_eq(b.str(), "1 + 2 = 3");
  let c = format("hi {}", "there");
  assert_eq(c.str(), "hi there");
  let d = format("no placeholders");
  assert_eq(d.str(), "no placeholders");
  printf("pin %d %d\n", 7, 8);
  print("pin done\n");
}
