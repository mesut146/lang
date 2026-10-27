// should-fail: unexpected end of input
//Parser::popv (used for import segments, method names, type names, let
//variables) peeked past the end when the buffer stopped right after the
//keyword: "eof pos=N len=N" from Parser::get. It reports the end of input now.
//The file must end at the keyword (no newline).
import