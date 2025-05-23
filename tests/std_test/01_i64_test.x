import std/result

func parse_test(){
  let x: i64 = i64::parse("112233").unwrap();
  assert(x == 112233_i64);

  let y: i64 = i64::parse("-112233").unwrap();
  assert(y == -112233_i64);
}

func print_test(){
  let x: i64 = i64::parse("112233").unwrap();
  let str = i64::print(x);
  assert_eq(str.str(), "112233");

  let y: i64 = i64::parse("-112233").unwrap();
  let str2 = i64::print(y);
  assert_eq(str2.str(), "-112233");

  str.drop();
  str2.drop();
}

func hex_parse(){
  let x = i64::parse_hex("0xab").unwrap();
  assert(x == 171_i64);

  let y = i64::parse_hex("-0xab").unwrap();
  assert(y == -171_i64);
}

func hex_print(){
  let x = 0xab;
  let str = i64::print_hex(x);
  assert(str.eq("0xab"));

  let y = -0xab;
  let str2 = i64::print_hex(y);
  assert(str2.eq("-0xab"));
  
  str.drop();
  str2.drop();
}

func main(){
  parse_test();
  print_test();
  hex_parse();
  hex_print();
  print("i64_test done\n");
}