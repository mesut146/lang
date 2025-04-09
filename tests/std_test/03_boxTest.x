//#derive(Debug)
struct BoxSt{
  a: i64;
  b: [i32; 10];
}

impl Clone for BoxSt{
  func clone(self): BoxSt{
    return BoxSt{self.a, self.b};
  }
}

//#derive(Debug)
enum LinkedList{
  A(a: i32),
  B(a: Box<LinkedList>)
}

impl LinkedList{
  func new(a: i32): LinkedList{
    return LinkedList::A{a};
  }
}

func main(){
  let b = Box::new(5);
  assert(*b.get() == 5);
  let b_clone = b.clone();
  assert(b.unwrap() == 5);
  assert(b_clone.unwrap() == 5);
  
  let b2 = Box::new(BoxSt{7, [9; 10]});
  assert(b2.get().a == 7);
  assert(b2.get().b[9] == 9);
  let cp = b2.clone();
  assert(cp.get().a == 7);
  b2.drop();
  cp.drop();
  
  let b3 = LinkedList::B{Box::new(LinkedList::A{11})};
  b3.drop();
  print("box_text done\n");
}