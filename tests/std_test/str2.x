func parse_test(){
  let x: i64= i64::parse("112233");
  assert x == 112233_i64;
}

func print_test(){
  let x: i64 = i64::parse("112233");
  let str = i64::print(x);
  print("x={}\n", str);
  assert str.eq("112233");
}

func main(){
  parse_test();
  print_test();
  print("str2 done\n");
}