class A{
  x: i32;
}
class B: A;
class C: B;

impl A{
  virtual func foo(self): str{
    return "A::foo";
  }
  virtual func bar(self): str{
    return "A::bar";
  }
}
impl B{
  func foo(self): str{
    return "B::foo";
  }
}
impl C{
  func bar(self): str{
    return "C::bar";
  }
}
func main(){
  /*let a = A{5};
  assert a.foo().eq("A::foo");
  assert a.bar().eq("A::bar");
  
  let b = B{.A{6}};
  let a2 = b as A*;
  //todo base field through derived
  assert a2.x == 6;
  assert b.foo().eq("B::foo");
  assert b.bar().eq("A::bar");
  assert a2.foo().eq("B::foo");
  assert a2.bar().eq("A::bar");
  
  let c = C{.B{.A{7}}};
  let b2 = c as B*;
  let a3 = c as A*;
  assert b2.foo().eq("B::foo");
  assert b2.bar().eq("C::bar");
  assert a3.foo().eq("B::foo");
  assert a3.bar().eq("C::bar");
  
  virtualTest2();*/
}

class A2;
class B2: A2;
class C2: B2;

impl A2{
  virtual func foo(self): str{
    return "A::foo";
  }
}
impl B2{
  func foo(self): str{
    return "B::foo";
  }
  virtual func bar(self): str{
    return "B::bar";
  }
}
impl C2{
  func foo(self): str{
    return "C::foo";
  }
  func bar(self): str{
    return "C::bar"; 
  }
}

func virtualTest2(){
  let b = B2{.A2{}};
  let a = b as A2*;
  assert a.foo().eq("B::foo");
  
  let c = C2{.B2{.A2{}}};
  let b2 = c as B2*;
  let a2 = b2 as A2*;
  assert b2.foo().eq("C::foo");
  assert b2.bar().eq("C::bar");
  assert a2.foo().eq("C::foo");
}