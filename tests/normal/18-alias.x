type c_char = i8;
type a = c_char;

func main(){
  let x: c_char = 5_i8;
  let x2 = 10 as a;
  print("alias done\n");
}
