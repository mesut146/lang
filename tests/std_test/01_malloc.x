func malloc_prim(){
  let arr = malloc<i32>(2);
  *ptr::get(arr, 0) = 3;
  *ptr::get(arr, 1) = 5;
  assert(*ptr::get(arr, 0) == 3);
  assert(*ptr::get(arr, 1) == 5);
}

struct Big{
  a: i64;
  b: i64;
}
 
func malloc_struct(){
  let arr = malloc<Big>(2);
  *ptr::get(arr, 0) = Big{5, 25};
  *ptr::get(arr, 1) = Big{6, 36};
  let p1 = ptr::get(arr, 0);
  assert(p1.a == 5);
  assert(p1.b == 25);
  let p2 = ptr::get(arr, 1);
  assert(p2.a == 6);
  assert(p2.b == 36);
}

func main(){
  malloc_prim();
  malloc_struct();
  print("malloc_test done\n");
}