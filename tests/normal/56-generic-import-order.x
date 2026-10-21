import ast/ast
import std/llist
import std/io

func main(){
  //No plain `Node` is used first, so this goes through the import lookup
  //rather than the resolver's type cache: with type arguments present the
  //lookup has to prefer the generic `Node<T>` (llist) over ast's non-generic
  //`Node`, i.e. import order must not decide the layout of `Node<T>`.
  let n = Node<i32>::new(11);
  assert(n.val == 11);
  print("generic order done\n");
}
