import ast/ast
import std/llist
import std/io

func main(){
  //`Node` (ast's non-generic one) is resolved first, so the resolver caches a
  //plain `Node` under its bare name. `Node<i32>` must still resolve to
  //llist's `Node<T>` (24-byte layout) instead of reusing ast::Node (12
  //bytes): the two sides of a call then disagreed about the struct's size and
  //an -O2 backend wrote over its caller's saved registers (doc/todo).
  let a: Node = Node{line: 1, pos: 2, id: 3};
  assert(a.id == 3);
  let n = Node<i32>::new(7);
  assert(n.val == 7);
  let l = LinkedList<i32>::new();
  assert(l.len() == 0);
  print("generic shadow done\n");
}
