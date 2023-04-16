class A{
 a: i32;
}
class B{
  b: i64;
}

trait Print{
  func prin(self);
}

impl Print for A{
  func helper(self){
  }
  func prin(self){
    self.helper();
  }
}

impl Print for B{
  func prin(self){
  }
}

func common<T>(obj: T){
  obj.prin();
}

func traitTest(){
  let a = A{5};
  let b = B{6};
  common(a);
  common(b);
  Print::prin(a);
  Print::prin(b);
  print("traitTest done\n");
}