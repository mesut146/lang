//#derive(Debug)
class BoxSt{
  a: i64;
  b: [i32; 10];
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
  
  let st = BoxSt{7, [9; 10]};
  let b2 = Box::new(st);
  assert b2.get().a == 7;
  assert b2.get().b[9] == 9;
  
  let b3 = BoxEn::B{Box::new(BoxEn::A{11})};

  print("boxText done\n");
}