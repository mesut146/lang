import std/libc

/*func iterTest(list: List<i32>*){
  let it = list.iter();
  assert it.has();
  let n1 = it.next();
  assert n1.unwrap() == 10;
  let n2 = it.next();
  assert n2.unwrap() == 20;
}*/

class LA{
  a: i8;
  b: i64;
}

func listStruct(){
  let list = List<LA>::new();
  list.add(LA{5i8, 10});
  list.add(LA{10i8, 20});
  let v1 = list.last(1);
  assert v1.a == 5 && v1.b == 10;
  let v2 = list.last();
  assert v2.a == 10 && v2.b == 20;
}

class LB{
 a: str;
 b: i32;
}

func listStruct2(){
  let list = List<LB>::new();
  list.add(LB{"foo", 10});
  list.add(LB{"bar", 20});
  let v1 = list.get_ptr(0);
  let v2 = list.get_ptr(1);
  print("v1.b={}\n", v1.b);
  print("v2.b={}\n", v2.b);
  assert v1.b == 10;
  assert v2.b == 20;
}

class Align{
  a: i8;
  b: i16;
  c: i64;
}


func listAlign(){
  let arr = malloc<Align>(10);
  let e1 = Align{1i8, 2i16, 3};
  let e2 = Align{4i8, 5i16, 6};
  let e3 = Align{10i8, 20i16, 30};
  *ptr::get(arr, 0) = e1;
  free(arr as i8*);
}

func listptr(){
  let a = 10;
  let b = 20;
  let list = List<i32*>::new(2);
  list.add(&a);
  list.add(&b);
  assert **list.get_ptr(0) == 10;
  let a2 = *list.get_ptr(0);
  assert *a2 == 10;

  assert *list.get(1) == 20;
}

func listptr_struct(){
  let a = LA{5i8, 10};
  let b = LA{20i8, 30};
  let list = List<LA*>::new(2);
  list.add(&a);
  list.add(&b);

  assert (*list.get_ptr(0)).b == 10;
  let a2 = *list.get_ptr(0);
  assert a2.a == 5;
  assert a2.b == 10;
}

func main(){
  let list = List<i32>::new(2);
  list.add(10);
  list.add(20);
  list.add(30);//trigger expand
  assert *list.get_ptr(0) == 10;
  assert *list.get_ptr(1) == 20;
  assert *list.get_ptr(2) == 30;
  //list.get_ptr(3); //will panic
  let x1 = 20, x2 = 30, x3 = 40;
  assert list.indexOf(&x1) == 1;
  assert list.contains(&x2) && !list.contains(&x3);
  let s = list.slice(1, 3);
  assert s.len() == 2 && s[0] == 20;
  //iterTest(&list);
  list.remove(1);
  listStruct();
  //listStruct2();
  listAlign();
  listptr();
  listptr_struct();
  print("listTest done\n");
}