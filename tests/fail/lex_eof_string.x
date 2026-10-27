// should-fail: lexer error
//A backslash at the very end of the buffer escapes nothing: read_string peeked
//past the end and died with "index N out of bounds". It must report the
//unterminated literal. The file must end with the backslash (no newline).
static s = "abc\