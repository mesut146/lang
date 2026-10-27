// should-fail: unexpected end of input
//Parser::name (attributes, items, binds, field access) tested isName(peek())
//on an empty buffer, and `use` reads a name directly: both indexed past the
//token list ("eof pos=N len=N"). They report the end of input now.
//The file must end at the keyword (no newline).
use