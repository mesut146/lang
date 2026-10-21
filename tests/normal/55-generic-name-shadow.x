//A plain `Node` must not satisfy a generic `Node<i32>` use. Types used to be
//looked up by their bare name, so any non-generic `Node` that had been
//resolved (a local one, or ast's, which the compiler's own modules import)
//answered `Node<i32>` as well: the instantiation then had that type's layout
//(ast::Node is 12 bytes, llist's Node<T> is 24) while std used 24, so the two
//sides of a call disagreed about the struct's size and an -O2 frame wrote over
//its caller's saved registers -- the crash that had been blamed on -O2 codegen
//(doc/todo, "backend at -O2").
import std/llist
import std/io

struct Node{
  line: i32;
  pos: i32;
  id: i32;
}

func main(){
  let a: Node = Node{line: 1, pos: 2, id: 3};
  assert(a.id == 3);
  let n = Node<i32>::new(7);
  assert(n.val == 7);
  let l = LinkedList<i32>::new();
  assert(l.len() == 0);
  print("generic shadow done\n");
}
