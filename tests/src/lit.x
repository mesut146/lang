func main(){
  let a8 = 5i8;
  let a16 = 5i16;
  let a32 = 5i32;
  let a64 = 5i64;
  assert a8 == 5 && a16 == 5 && a32 == 5 && a64 == 5;
  overflow_u8();
  overflow_u16();
  overflow_u32();
  underflow_u8();
  underflow_u16();
  underflow_u32();
  
  let sc = 1_000_000;
  //let dec = 1_000.123_456;
  let hex = 0xA0;
  assert hex == 160;
  print("literalTest done\n");
}

func test(u: u64){
  print("u=%d\n", u);
}

func underflow_u8(){
  let u: u8 = 0;
  u = (u as i16 - 1) as u8;
  assert u == 255;
}

func underflow_u16(){
  let u: u16 = 0;
  u = (u as i32 - 1) as u16;
  assert u == 65535;
}

func underflow_u32(){
  let u: u32 = 0;
  u = (u as i64 - 1) as u32;
  assert u == max_32();
}

func overflow_u8(){
  let u: u8 = 255;
  ++u;
  assert u == 0;
}

func overflow_u16(){
  let u: u16 = 65535;
  ++u;
  assert u == 0;
}

func overflow_u32(){
  let u: u32 = max_32();
  ++u;
  assert u == 0;
}

func max_32(): u32{
  return ((1i64 << 32) - 1i64) as u32;
}
