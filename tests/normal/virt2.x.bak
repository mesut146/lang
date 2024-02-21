class A2;
class B2: A2;
class C2: B2;

impl A{
  virtual func foo(self): str{
    return "A::foo";
  }
}
impl B{
  func foo(self): str{
    return "B::foo";
  }
  virtual func bar(self): str{
    return "B::bar";
  }
}
impl C{
  func foo(self): str{
    return "C::foo";
  }
  func bar(self): str{
    return "C::bar"; 
  }
}

func main(){
  let b = B{.A{}};
  let a = b as A*;
  //assert a.foo().eq("B::foo");
  
  let c = C2{.B{.A{}}};
  let b2 = c as B*;
  let a2 = b2 as A*;
  //assert b2.foo().eq("C::foo");
  //assert b2.bar().eq("C::bar");
  //assert a2.foo().eq("C::foo");
  print("virt2 done");
}