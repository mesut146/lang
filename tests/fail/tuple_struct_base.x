// should-fail: tuple struct cannot have a base class
//A positional struct's field indices are declaration-relative; a base class
//would put the inherited prefix in front of them while mapType/access assume
//the tuple list is the whole body. The parser rejects the combination instead
//of laying the type out wrong.
struct B{
  a: i32;
}
struct T: B(i32);
func main(){
}
