//Path::strip_dir is the lexical half of the panic-path default
//(Context::panic_path): drop a directory prefix at a whole-component
//boundary and keep the rest without its leading `/`, so a panic says
//`src/a.x` instead of the checkout's absolute path. Pinned edge cases:
//`/a/b` must not strip from `/a/bc`, a relative path and an unrelated
//absolute path stay as given, the root keeps its remainder relative, and a
//path equal to the dir becomes `.`.
import std/fs

func main(){
  assert(Path::strip_dir("/home/u/proj/src/a.x", "/home/u/proj").eq("src/a.x"));
  assert(Path::strip_dir("/home/u/proj/src/a.x", "/home").eq("u/proj/src/a.x"));
  //no partial component match
  assert(Path::strip_dir("/home/u/projc/a.x", "/home/u/proj").eq("/home/u/projc/a.x"));
  //relative or unrelated paths are untouched
  assert(Path::strip_dir("src/a.x", "/home/u/proj").eq("src/a.x"));
  assert(Path::strip_dir("/other/a.x", "/home/u/proj").eq("/other/a.x"));
  //dir == path, empty dir, and the root
  assert(Path::strip_dir("/home/u/proj", "/home/u/proj").eq("."));
  assert(Path::strip_dir("/home/u/proj/a.x", "").eq("/home/u/proj/a.x"));
  assert(Path::strip_dir("/a/b", "/").eq("a/b"));
  print("path strip dir ok\n");
}
