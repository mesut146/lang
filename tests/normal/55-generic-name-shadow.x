//A plain type must not satisfy a generic use of the same name. Types used to be
//looked up by their bare name, so any non-generic `LNode` that had been
//resolved (a local one, or another module's) answered `LNode<i32>` as well:
//the instantiation then had that type's layout while std used its own, so the
//two sides of a call disagreed about the struct's size and an -O2 frame wrote
//over its caller's saved registers -- the crash that had been blamed on -O2
//codegen (doc/todo, "backend at -O2").
import std/llist
import std/io

struct LNode{
  line: i32;
  pos: i32;
  id: i32;
}

func main(){
  let a: LNode = LNode{line: 1, pos: 2, id: 3};
  assert(a.id == 3);
  let n = LNode<i32>::new(7);
  assert(n.val == 7);
  let l = LinkedList<i32>::new();
  assert(l.len() == 0);
  print("generic shadow done\n");
}
