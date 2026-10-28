// Method turbofish: `x.f<i32>(a)`.
//
// The postfix `.` branch took a name and only looked for `(`; `<...>` fell
// through to the comparison level, so `s.get<i32>(5)` parsed as
// `(s.get) < i32 > (5)` and failed with "invalid field S.get". Free functions
// already worked because prim parses a whole type (isTypeArg lookahead) before
// the argument list.
struct S{
  n: i32;
}

impl S{
  func get<T>(self, a: T): T{
    return a;
  }
  func id(self, a: i32): i32{
    return a + self.n;
  }
}

func main(){
  let s = S{10};
  assert(s.get<i32>(5) == 5);
  assert(s.get<i64>(9i64) == 9i64);
  //inference still applies when no type args are given
  assert(s.get(7) == 7);
  assert(s.id(2) == 12);
  //`<` after a field/method name stays a comparison (the lookahead requires
  //the closing ">" to sit right before "(")
  let v = s.id(2);
  assert(v < 20);
  assert(v > 3);
  print("method turbofish ok\n");
}
