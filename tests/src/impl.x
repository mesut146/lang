import List
import String
import str//todo str is imported incorrectly from String

impl i32{
  func MIN(): i32{ return -2147483648; }
  func MAX(): i32{ return 2147483647; }

  func min(x, y: i32): i32{
    if(x <= y) return x;
    return y;
  }
  func max(x, y: i32): i32{
    if(x >= y) return x;
    return y;
  }
  func abs(x): i32{
    if(x >= 0) return x;
    return -x;
  }
  func generic_sum<T>(x, y: T): T{
    return x + y;
  }
  func generic_other<T>(x: T): T{
    return x;
  }

  func str_size(self): i32{
    if(self==0) return 1;
    let x = self;
    let res = 0;
    while(x > 0){
      x /= 10;
      res+=1;
    }
    return res;
  }

  func str(self): String{
    let x = self;
    let len = self.str_size() + 1;
    let list = List<i8>::new(len);
    list.count = len - 1;
    let i = len - 1;
    list.set(i, 0i8);
    i -= 1;
    while(x > 0){
      let c = x % 10;
      list.set(i, (c + '0') as i8);
      i -= 1;
      x = x / 10;
    }
    return String{list};
  }
}

class A<T>{
  a: T;
}

impl A<T>{
  func get(self): T{
    return self.a;
  }
  func add(a: i32, b: i32): i32{
    return a + b;
  }
}

impl [i32]{
   func test(self){}
}

impl [i32; 3]{}

func implTest(){
  let x = 5;
  assert x.min(6) == 5;
  assert 5.max(6) == 6;
  assert (-5).abs() == 5;
  assert 5.generic_sum(6i64) == 11;
  assert i32::generic_other(5) == 5;
  assert i32::min(5, 6) == 5;
  let s = 345.str();
  s.dump();
  let s2=s.str();
  s2.dump();
  assert s2.eq("345");

  assert A<i32>{a: 5}.get() == 5;
  assert A<i64>{a: 5}.get() == 5;
  //non member generic
  assert A<i32>::add(5, 6) == 11;
  assert A<i64>::add(5, 6) == 11;

  [1, 2, 3][0..3].test();
  print("implTest done\n");
}