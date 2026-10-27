// should-fail: lexer error
//The unclosed-comment error asks for the line it ended on, which is one past
//the last line when the comment ends with a newline: get_line panicked with
//"not possible" instead of the lexer reporting the unclosed comment.
/*x
