func main(){
  sized();
  elems();
  deref();
  ptr();  
  sliceTest();
  arr2d();
  print("arrayTest done\n");
}

impl [i32]{
  func dump(self){
    print("[");
    for(let i = 0;i < self.len();++i){
      if(i > 0) print(", ");
      print("%d=%d", i, self[i]);
    }
    print("]\n");
  }  
}

func sized(){
  let arr = [5; 3];
  assert arr[0] == 5 && arr[1] == 5 && arr[2] == 5;
  arr[0] = 8;
  arr[2] = 9;
  assert arr[0] == 8 && arr[1] == 5 && arr[2] == 9;
}

func elems(){
  let arr = [3, 7, 11];
  //assert Fmt::str(arr[0..3]).str().eq("[3, 7, 11]");
  assert arr[0] == 3 && arr[1] == 7 && arr[2] == 11;
}

func deref(){
  //auto deref
  let arr = [10, 20, 30];
  let ptr = &arr;
  assert ptr[0] == 10 && ptr[1] == 20;
}

func ptr(){
  let arr = [5, 6, 7];
  let arr2 = [50, 60, 70];
  let arr3 = [&arr, &arr2];
  assert (arr3[0])[0] == 5;
}

func sliceTest(){
  let arr = [2, 3, 5, 7, 11, 13];
  let slice = arr[2..5];//[5, 7, 11]
  /*assert slice.len() == 3;
  slice.dump();
  assert slice[0] == 5 && slice[3] == 13;
  //mutate original
  slice[0] = 55; //[55, 7 ,11]
  assert slice[0] == 55 && arr[2] == 55;
  //auto deref
  let ptr = &slice;
  assert ptr[0] == 55;*/
  //slice of slice
  let slice2 = slice[1..3];//[7, 11]
  print("slice2[0]=%d\n", slice2[0]);
  assert slice2[0] == 7 && slice2[1] == 11;
  //multi alloc
  assert [1_i16, 2, 3][1..2][1] == 3;
  print("sliceTest done\n");
}

func arr2d_cons(){
  //inner allocated first then memcpy
  let a1 = [[52; 5]; 10];
  assert a1[0][0] == 52 && a1[9][4] == 52;
  a1[0][0] = 3;
  assert a1[0][0] == 3;
}

func arr2d_elems(){
  let a2 = [[10, 20], [30, 40]];
  assert a2[0][1]==20 && a2[1][0]==30;
}

func arr2d_copy(){
  let a3 = [1, 2, 3];
  let a4 = [a3, [10, 20, 30]];
  assert a4[0][0] == 1 && a4[1][2] == 30;
}

func arr2d(){
  arr2d_cons();
  arr2d_elems();
  arr2d_copy();
  print("arr2d done\n");
  mixed();
}

class A{
  a: [B; 3];
  b: [B]; 
}
class B{
  b: i32;
}
func mixed(){
  let a1 = A{a: [B{10}, B{20}, B{30}], b: [B{5}][0..1]};
  assert a1.a[0].b == 10;
  assert a1.b[0].b == 5;
  
  //obj in arr
  let a2 = [B{b: 5}, B{b: 7}];
  assert a2[0].b == 5;

  print("mixed done\n");
}

