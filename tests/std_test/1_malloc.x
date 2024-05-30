func main(){
   let arr = malloc<i32>(2);
   *ptr::get(arr, 0) = 3;
   *ptr::get(arr, 1) = 5;
   assert(*ptr::get(arr, 0) == 3 && *ptr::get(arr, 1) == 5);
   mallocTest2();
   print("malloc_test done\n");
}

class Big{
  a: i64;
  b: i64;
}

func mallocTest2(){
   let arr = malloc<Big>(2);
   *ptr::get(arr, 0) = Big{5, 25};
   *ptr::get(arr, 1) = Big{6, 36};
   assert(ptr::get(arr, 0).a == 5 && ptr::get(arr, 0).b == 25);
   assert(ptr::get(arr, 1).a == 6 && ptr::get(arr, 1).b == 36);
}