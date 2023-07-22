//#derive(Debug)
class BoxSt{
  a: i64;
  b: [i32; 10];
}

impl Clone for BoxSt{
  func clone(self): BoxSt{
    return BoxSt{self.a, self.b};
  }
}

#derive(Debug)
enum BoxEn{
  A(a: i32),
  B(a: Box<BoxEn>)
}

func main(){
  let b = Box::new(5);
  //assert *b.get() == 5;
  assert b.unwrap() == 5;
  assert b.clone().unwrap() == 5;
  
  let b2 = Box::new(BoxSt{7, [9; 10]});
  assert b2.get().a == 7;
  assert b2.get().b[9] == 9;
  let cp = b2.clone();
  assert cp.get().a == 7;
  
  let b3 = BoxEn::B{Box::new(BoxEn::A{11})};
  auto_load_test();
  print("boxText done\n");
}


struct A{
  a: i32;
}

enum En{
  A,
  B(a: A*)
}

func auto_load_test(){
  let a = get_load();
  assert a.a == 10;

  let a2 = get_load2();
  assert a2.a == 20;
}

func get_load(): A{
  let a = malloc<A>(1);
  *a = A{a: 10};
  return *a;
}

func get_load2(): A{
  let a = malloc<A>(1);
  *a = A{a: 20};
  let b = En::B{a};
  if let En::B(a_ptr) = (b){
    return *a_ptr;
  }
  panic("");
}