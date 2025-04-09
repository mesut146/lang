func parse_test(){
  let x: f64 = f64::parse("3.5");
  assert(x == 3.5);

  let y: f64 = f64::parse("-3.5");
  assert(y == -3.5);
}

func print_test(){
  let str = f64::print(3.1415);
  assert_eq(str.str(), "3.141500");

  let str2 = f64::print(-1.23);
  assert_eq(str2.str(), "-1.230000");

  str.drop();
  str2.drop();
}

func main(){
    parse_test();
    print_test();
}