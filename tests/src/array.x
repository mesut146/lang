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
  let arr = [[0; 5]; 10];
  arr[0][0] = 3;
  assert arr[0][0] == 3;
  let a1 = [1, 2, 3];
  let arr2 = [a1];
  assert arr2[0][0] == 1;
  print("arr2d done\n");
}

func arrr3(){
  let arr2 = [[1, 2, 3]];

}