// should-fail: lexer error
//checkEscape returns the invalid-escape message as a Result, but read_string
//unwrapped it: the error surfaced as "unwrap on empty Result" from result.x
//instead of a lexer diagnostic (which is what the "lexer error" header marks).
static s = "a\q";
func main(){}
