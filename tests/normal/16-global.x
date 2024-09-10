static x: i32 = 11;

func main(){
  assert(x == 11);
  x = 22;
  assert(x == 22);
}