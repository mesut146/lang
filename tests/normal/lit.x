func main(){
  let a8 = 8i8;
  let a16 = 16i16;
  let a32 = 32i32;
  let a64 = 64i64;
  assert(a8 == 8);
  assert(a16 == 16);
  assert(a32 == 32);
  //print("a64=%d\n", a64);
  assert(a64 == 64);
  overflow_u8();
  overflow_u16();
  overflow_u32();
  underflow_u8();
  underflow_u16();
  underflow_u32();
  
  let sc = 1_000_000;
  //let dec = 1_000.123_456;
  let hex = 0xA0;
  assert(hex == 160);
  print("literalTest done\n");
}

func underflow_u8(){
  //let neg = -1;
  //let neg = 255;
  //let u: u8 = neg as u8;
  let u: u8 = 255u8;
  //print("%d\n", u);
  assert(u == 255);
}

func underflow_u16(){
  let u: u16 = 0;
  u = (u as i32 - 1) as u16;
  assert(u == 65535);
}

func underflow_u32(){
  let u: u32 = 0;
  u = (u as i64 - 1) as u32;
  assert(u == max_32());
}

func overflow_u8(){
  let u: u8 = 255;
  ++u;
  assert(u == 0);
}

func overflow_u16(){
  let u: u16 = 65535;
  ++u;
  assert(u == 0);
}

func overflow_u32(){
  let u: u32 = max_32();
  ++u;
  assert(u == 0);
}

func max_32(): u32{
  return ((1i64 << 32) - 1i64) as u32;
}
