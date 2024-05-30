func main(){
  let a = 5;
  assert_eq(a, 5);
  test(&a);
  assert_eq(a, 6);
  
  mut(a);
  assert_eq(a, 6);
  
  arr();
  print("auto load done\n");
}

func arr(){
  let arr = [5, 6, 7];
  let p = &arr;
  //auto deref
  assert_eq(p[0], 5);
  assert_eq(p[1], 6);
  arr2(p);
  fa();
}

func arr2(p: [i32; 3]*){
  assert_eq(p[0], 5);
  assert_eq(p[1], 6);
}

class A{
 a: [i32; 3];
}

func fa(){
  let a = A{[10, 20, 30]};
  assert_eq(a.a[0], 10);
}

func test(p: i32*){
  assert_eq(*p, 5);
  *p = 6;
}

func mut(p: i32){
  p = 7;
  assert_eq(p, 7);
}