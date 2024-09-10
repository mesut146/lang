func main(){
  let a = 5;
  assert(a == 5);
  test(&a);
  assert(a == 6);
  
  mut(a);
  assert(a ==  6);
  
  arr();
  print("auto load done\n");
}

func arr(){
  let arr = [5, 6, 7];
  let p = &arr;
  //auto deref
  assert(p[0] ==  5);
  assert(p[1] ==  6);
  arr2(p);
  fa();
}

func arr2(p: [i32; 3]*){
  assert(p[0] ==  5);
  assert(p[1] ==  6);
}

struct A{
 a: [i32; 3];
}

func fa(){
  let a = A{[10, 20, 30]};
  assert(a.a[0] ==  10);
}

func test(p: i32*){
  assert(*p ==  5);
  *p = 6;
}

func mut(p: i32){
  p = 7;
  assert(p ==  7);
}