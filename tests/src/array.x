func arrayTest(){
  let arr = [5; 3];
  arr[0] = 8;
  arr[2] = 9;
  assert arr[0]==8 && arr[2] == 9;
  
  let arr2 = [3, 7, 55];
  assert arr2[0] == 3 && arr2[1] == 7;
  
  let arr3 = [&arr, &arr2];
  assert (*arr3[0])[0] == 8;
  print("arrayTest done\n");
}