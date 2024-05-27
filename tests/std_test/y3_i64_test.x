func parse_test(){
  let x: i64 = i64::parse("112233");
  assert x == 112233_i64;

  let y: i64 = i64::parse("-112233");
  assert y == -112233_i64;
}

func print_test(){
  let x: i64 = i64::parse("112233");
  let str = i64::print(x);
  print("print_test x={}\n", str);
  assert str.eq("112233");

  let y: i64 = i64::parse("-112233");
  let str2 = i64::print(y);
  print("print_test y={}\n", str2);
  assert str2.eq("-112233");
}

func hex_parse(){
  let x = i64::parse_hex("0xab");
  print("hex_parse x={}\n", x);
  assert x == 171_i64;

  let y = i64::parse_hex("-0xab");
  print("hex_parse y={}\n", y);
  assert y == -171_i64;
}

func hex_print(){
  let x = 0xab;
  let str = i64::print_hex(x);
  print("hex_print str={}\n", str);
  assert str.eq("0xab");

  let y = -0xab;
  let str2 = i64::print_hex(y);
  print("hex_print str2={}\n", str2);
  assert str2.eq("-0xab");
}

func main(){
  parse_test();
  print_test();
  hex_parse();
  hex_print();
  print("i64_test done\n");
}