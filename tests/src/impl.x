impl int{
  func min(x, y: int): int{
    if(x <= y) return x;
    return y;
  }
  func max(x, y: int): int{
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