func main(){
   let arr = malloc<i32>(10);
   arr[0] = 3;
   arr[1] = 5;
   assert arr[0] == 3 && arr[1] == 5;
   mallocTest2();
   print("mallocTest done\n");
}

class Big{
  a: i64;
  b: i64;
}

func mallocTest2(){
   let arr = malloc<Big>(2);
   arr[0] = Big{5, 25};
   arr[1] = Big{6, 36};
   assert arr[0].a == 5 && arr[0].b == 25;
   assert arr[1].a == 6 && arr[1].b == 36;
}