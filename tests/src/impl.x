impl i32{
  func min(x, y: i32): i32{
    if(x <= y) return x;
    return y;
  }
  func max(x, y: i32): i32{
    if(x >= y) return x;
    return y;
  }
}

func implTest(){
  let x = 5;
  assert x.min(6) == 5;
  assert 5.max(6) == 6;

  print("implTest done\n");
}