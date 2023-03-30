class A{
 a: i32;
}
class B{
  b: i64;
}

trait Print{
  func prin(self);
  //func aa(self);
}

impl Print for A{
  func helper(self){
    print("a=%d\n", self.a);
  }
  func prin(self){
    print("a=%d\n", self.a);
    self.helper();
  }
}

impl Print for B{
  func prin(self){
    print("a=%lld\n", self.b);
  }
}

func prin<T>(obj: T){
  obj.prin();
}

func traitTest(){
  prin(A{5});
  prin(B{6});
  //prin(5);
  print("traitTest done\n");
}