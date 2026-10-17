import std/string

//str::real_len used to do self.get(self.len() - 1), i.e. buf[-1] for an
//empty string: a 1-byte out-of-bounds read before the (0-size) buffer. Any
//String::eq with an empty operand hits it (e.g. a HashMap<String,..> key
//compared against a default-constructed empty key). The gate below is
//valgrind's error exit, so it catches the invalid read (not a leak).
func main(){
  let s = String::new("abc");
  let e = String::new("");
  assert(!s.eq(&e));
  assert(e.eq(&e));
  assert(!e.eq(&s));
  print("empty_streq done\n");
}
