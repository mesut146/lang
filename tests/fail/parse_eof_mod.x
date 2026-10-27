// should-fail: unexpected end of input
//The mod-body loop keeps calling parse_item until it sees '}'; at EOF the
//dispatch fell through to "invalid top level decl" with a peek past the end
//(Parser::get's "eof pos=N len=N"). parse_item reports the end of input now.
//The file must end at the open brace (no newline).
mod M{