impl int{
  func min(x, y: int): int{
    if(x <= y) return x;
    return y;
  }

}

func implTest(){
  let x = 5;
  let m = x.min(6);
}