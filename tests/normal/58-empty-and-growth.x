//Empty String/List values now carry a null buffer (no eager allocation) and
//must still behave for len/eq/print/clone, and growth by repeated small
//appends must stay geometric (reserve used to grow by a fixed 10 bytes, so
//building a String in small pieces recopied the whole buffer every ~10 bytes).
import std/io
import std/string
import std/list

func main(){
  let e = String::new();
  assert(e.len() == 0);
  assert(e.empty());
  assert(e.eq(""));
  let ec = e.clone();
  assert(ec.len() == 0);
  print("[{}]\n", e);
  let l = List<i32>::new();
  assert(l.len() == 0);
  assert(l.empty());
  let s = String::new();
  for(let i = 0;i < 1000;++i){
    s.append("ab");
  }
  assert(s.len() == 2000);
  assert(s.substr(0, 4).eq("abab"));
  let li = List<i32>::new();
  for(let i = 0;i < 1000;++i){
    li.add(i);
  }
  assert(li.len() == 1000);
  assert(ptr::deref!(li.get(999)) == 999);
  print("empty and growth done\n");
}
