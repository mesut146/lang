//Strings built from a `str` used to be validated byte by byte against a debug
//whitelist that panicked on '@' and on every non-ASCII byte (and cost a pass
//over every byte of every String::new(str)). Plain bytes must survive.
import std/io
import std/string

func main(){
  let at = String::new("@");
  assert(at.len() == 1);
  assert(at.get(0) == '@');
  let utf = String::new("héllo");
  assert(utf.len() == 6);
  assert(utf.eq("héllo"));
  print("string bytes done\n");
}
