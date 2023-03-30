impl i8{
func test(prm): i32{
  return 55;
}
}

class A{
 a: i32;
}

func test2(p: A){
  p.a = 6;
}

func xx(){
  let x = 5;
}

func main(): i32{
  i8::test(5i8);
  test2(A{8});
  xx();
  return 0;
}