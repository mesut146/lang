class Node<T>{
  value: T;
  next: Node<T>*;
}

func makeNode(arr: [i32]): Node<i32>{
  let pos = 0;
  let head = Node<i32>{value: arr[pos++]};
  let cur = &head;
  while(pos < arr.len()){
    cur.next = new Node<int>{value: arr[pos++]};
    cur = cur.next;
  }
  return head;
}

enum Color{
  WHITE,
  BLACK;
}

interface a{
  func calc(): int;
}

func calc(a: int, b: int, carry: int?): int
{
  if(carry){
    return a + b + carry;
  }
  else{
    return a + b;
  }
}

func def(a: int = 0){}

calc(1,2);
calc(1,2,3);
def();
def(5);