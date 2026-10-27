// should-fail: unexpected end of input
//The block dispatch looks ahead with is(IF, LET), i.e. peek(1): a buffer that
//ends with the `if` keyword made that lookahead index past the token list
//("eof pos=N len=N"). get() hands out a synthetic EOF token past the end, so
//the lookahead fails and consume() reports the missing '('. The file must end
//at the keyword (no newline).
func main(){ if