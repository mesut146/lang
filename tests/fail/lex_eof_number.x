// should-fail: unexpected end of input
//read_number used to peek the character after the last digit without checking,
//so a number that ends the buffer ("... = 1" with no trailing newline) died
//with "index N out of bounds"; with the guard the parser reports the missing
//";" instead. The file must end with the '1' (no newline).
func main(){
  let a = 1