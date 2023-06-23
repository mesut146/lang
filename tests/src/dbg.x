struct A{
 a: i32;
 b: i64;
}

struct B{
 a: bool;
 b: i16;
}

func bool_test(){
 let a = B{false, 123i16};
 a.a = true;
 let aa = a.a;
}

func main(){
 bool_test();
 let a = A{5, 10};
 let aa = a.a;
 let b = &a;
 let bb = b.b;
 let l = List<i32>::new();
 l.add(55);
}