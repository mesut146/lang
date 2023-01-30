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
  func prin(self){
    print("a=%d\n", self.a);
  }
}

impl Print for B{
  func prin(self){
    print("a=%d\n", self.b);
  }
}

func prin<T>(obj: T){
  obj.prin();
}

func traitTest(){
  prin(A{5});
  prin(B{6});
}