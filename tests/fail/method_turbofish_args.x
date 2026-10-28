// should-fail: type arg size mismatched
//A method's explicit type arguments must match its type parameters; one
//parameter, two arguments is a diagnostic from the method resolver, not a
//crash.
struct S{
}

impl S{
  func get<T>(self, a: T): T{
    return a;
  }
}

func main(){
  let s = S{};
  let v = s.get<i32, i32>(1);
}
