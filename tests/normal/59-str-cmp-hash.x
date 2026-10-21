//str::cmp inlines the trailing-NUL trim (one len() plus one last-byte load
//instead of two real_len() calls) and str::hash uses an AND where it used a
//64-bit modulo. Both are on every map/set lookup, so pin their exact
//semantics: cmp ignores one trailing NUL and orders by length first, eq rides
//on cmp, and equal strings must hash equally for a large map to round-trip.
import std/io
import std/hashmap

func main(){
  assert("".cmp("") == 0);
  assert("abc".cmp("abc") == 0);
  assert("abc".cmp("abd") < 0);
  assert("abd".cmp("abc") > 0);
  assert("ab".cmp("abc") < 0);
  assert("abc".cmp("ab") > 0);
  //one trailing NUL is not part of the value (C string interop)
  assert("a\0".cmp("a") == 0);
  assert("a".cmp("a\0") == 0);
  assert("".cmp("a") < 0);
  assert("a".cmp("") > 0);
  assert("".eq(""));
  assert("abc".eq("abc"));
  assert(!"abc".eq("abd"));
  assert("a\0".eq("a"));
  //hash stays consistent, and the map grows through reserve/expand
  assert("abc".hash() == "abc".hash());
  assert("abc".hash() != "abd".hash());
  //String keys are owned by the map; a `str` key would point into a temporary
  let keys = List<String>::new();
  let m = HashMap<String, i32>::new(8);
  for(let i = 0;i < 2000;++i){
    let k = format("key{}", i);
    keys.add(k.clone());
    m.insert(k, i);
  }
  for(let i = 0;i < 2000;++i){
    let kp: String* = keys.get(i);
    let hit = m.get(kp);
    assert(hit.is_some());
    assert(*hit.unwrap() == i);
  }
  print("cmp and hash done\n");
}
