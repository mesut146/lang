// should-fail: unexpected end of input
//An object literal's entry() checks isName(peek()) and then parses the value;
//with the buffer ending at the '{' that peek and the following prim() both
//ran past the token list ("eof pos=N len=N"). They report the end of input
//now. The file must end at the open brace (no newline).
func main(){ let x = Foo{