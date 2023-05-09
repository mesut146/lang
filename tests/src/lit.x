func main(){
  let a8 = 5i8;
  let a16 = 5i16;
  let a32 = 5i32;
  let a64 = 5i64;
  assert a8 == 5 && a16 == 5 && a32 == 5 && a64 == 5;
  test_unsigned();
  print("literalTest done\n");
}

func test_unsigned(){
  let u: u16 = 65535;
  ++u;
  print("u=%d\n", u);
}