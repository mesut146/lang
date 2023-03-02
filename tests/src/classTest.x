class Point{
  x: i32;
  y: i32;
}

impl Point{
  func new(a: i32, b: i32): Point{
    return Point{x: a, y: b};
  }

  func getX(self): i32{
    return self.x;
  }
  func getY(self): i32{
    return self.y;
  }
}

class Base{
  x: i32;
}

class Derived: Base{
  y: i32;
}

/*class Derived2: Derived{
  z: i32;
}*/

impl Base{
  virtual func foo(self){
    print("Base::foo x=%d\n", self.x);
  }
}
impl Derived{
  func foo(self){
    print("Derived::foo y=%d\n", self.y);
  }
}

func dyn(b: Base*){
  b.foo();
}

func baseTest(){
  let d = Derived{.Base{x: 10}, y: 5};
  let b = d as Base*;
  assert b.x == 10;
  b.foo();
  d.foo();
}

func classTest2(): i32{
  return 123;
}