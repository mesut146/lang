func arrayTest(){
  let arr = [5; 3];
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
  let slice = arr[2..5];
  assert slice[0] == 5 && slice[3]==13;
  //mutate original
  slice[0] = 55;
  assert slice[0] == 55 && arr[2] == 55;
  //auto deref
  let ptr = &slice;
  assert ptr[0] == 55;
  print("sliceTest done\n");
}

func arr2d(){
  let a1 = [[0; 5]; 10];
  a1[0][0] = 3;
  assert a1[0][0] == 3;
  
  let a2 = [[10, 20], [30, 40]];
  assert a2[0][1]==20 && a2[1][0]==30;
  
  let a3 = [1, 2, 3];
  let a4 = [a3, [10, 20, 30]];
  assert a4[0][0] == 1 && a4[1][2] == 30;
  print("arr2d done\n");
  arr_in_obj();
}

class A{
  arr: [int; 3];
}
class B{
  b: int;
}
func arr_in_obj(){
  let a1 = A{arr: [10, 11, 12]};
  assert a1.arr[0] == 10;
  
  //obj in arr
  let a2 = [B{b: 5}, B{b: 7}];
  assert a2[0].b == 5;
}

func pp(){
  let a = new B{b: 5};
  //let b = 6;
  let ptr = &a;
  //ptr = &b;
}
