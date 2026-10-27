// should-fail: unexpected end of input
//A lone '/' at the end of the buffer has no second character: the lexer used to
//peek(1) past the end and die with "index N out of bounds" before the parser
//could report the missing operand. The file must end with the '/' (no newline).
func main(){
  let b = 1 /