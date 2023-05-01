impl [i32; 3]{
  func dump(self){
    print("{%d %d %d}\n", self[0], self[1], self[2]);
    print("[");
    for(let i=0;i<3;++i){
      if(i>0) print(", ");
      print("%d.%d", self[i], self[1]);
    }
    print("]\n");
  }
}

func main(){
  let arr = [5; 3];
  print("{%d %d %d}\n", arr[0], arr[1], arr[2]);
  arr.dump();
  assert arr[1] == 5;
  arr[0] = 8;
  arr[2] = 9;
  assert arr[0]==8 && arr[2] == 9;
  
  let arr2 = [3, 7, 55];
  assert arr2[0] == 3 && arr2[1] == 7;
  
  //auto deref
  let ptr = &arr2;
  assert ptr[0] == 3 && ptr[1] == 7;
  
  let arr3 = [&arr, &arr2];
  assert (*arr3[0])[0] == 8;
  print("arrayTest done\n");
  
  sliceTest();
  arr2d();
}

func sliceTest(){
  let arr = [2, 3, 5, 7, 11, 13];
  let slice = arr[2..5];//[5, 7, 11]
  assert slice.len == 3;
  assert slice[0] == 5 && slice[3]==13;
  //mutate original
  slice[0] = 55; //[55, 7 ,11]
  assert slice[0] == 55 && arr[2] == 55;
  //auto deref
  let ptr = &slice;
  assert ptr[0] == 55;
  //slice of slice
  let slice2 = slice[1..3];//[7, 11]
  assert slice2[0] == 7 && slice2[1] == 11;
  print("sliceTest done\n");
}

func arr2d(){
  /*let a1 = [[0; 5]; 10];
  a1[0][0] = 3;
  assert a1[0][0] == 3;
  
  let a2 = [[10, 20], [30, 40]];
  assert a2[0][1]==20 && a2[1][0]==30;
  
  let a3 = [1, 2, 3];
  let a4 = [a3, [10, 20, 30]];
  assert a4[0][0] == 1 && a4[1][2] == 30;*/
  print("arr2d done\n");
  mixed();
}

class A{
  a: [B; 3];
  b: B;
  c: [B]; 
}
class B{
  b: i32;
}
func mixed(){
  let a1 = A{a: [B{1}, B{2}, B{3}], b: B{b: 4}, c: [B{5}][0..1]};
  /*assert a1.arr[0] == 10;
  
  //obj in arr
  let a2 = [B{b: 5}, B{b: 7}];
  assert a2[0].b == 5;*/

  print("mixed done\n");
}

