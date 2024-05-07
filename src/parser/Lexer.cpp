#include "Lexer.h"
#include <map>
#include <optional>
#include <vector>

TokenType kw(std::string &s) {
    if (s == "assert") return ASSERT_KW;
    if (s == "class") return CLASS;
    if (s == "struct") return STRUCT;
    if (s == "enum") return ENUM;
    if (s == "trait") return TRAIT;
    if (s == "impl") return IMPL;
    if (s == "extern") return EXTERN;
    if (s == "virtual") return VIRTUAL;
    if (s == "static") return STATIC;
    if (s == "type") return TYPE;
    if (s == "match") return MATCH;
    if (s == "bool") return BOOLEAN;
    if (s == "true") return TRUE;
    if (s == "false")
        return FALSE;
    if (s == "i8") return I8;
    if (s == "i16") return I16;
    if (s == "i32") return I32;
    if (s == "f32") return F32;
    if (s == "f64") return F64;
    if (s == "null")
        return NULL_LIT;
    if (s == "import")
        return IMPORT;
    if (s == "as")
        return AS;
    if (s == "from")
        return FROM;
    if (s == "return")
        return RETURN;
    if (s == "continue")
        return CONTINUE;
    if (s == "if")
        return IF_KW;
    if (s == "is")
        return IS;
    if (s == "else")
        return ELSE_KW;
    if (s == "for")
        return FOR;
    if (s == "while")
        return WHILE;
    if (s == "do")
        return DO;
    if (s == "break")
        return BREAK;
    if (s == "fn" || s == "func")
        return FUNC;
    if (s == "let")
        return LET;
    if (s == "namespace")
        return NAMESPACE;
    if (s == "new")
        return NEW;
    if (s == "const")
        return CONST_KW;
    if (s == "try")
        return TRY;
    if (s == "catch")
        return CATCH;
    if (s == "throw")
        return THROW;
    if (s == "switch")
        return SWITCH;
    if (s == "case")
        return CASE;
    return EOF_;
}

std::vector<std::string> Lexer::suffixes = {"i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "f32", "f64"};

void eatNum(Lexer &l) {
    while (l.peek() == '_' && isdigit(l.buf[l.pos + 1]) || isdigit(l.peek())) {
        if (l.peek() == '_') {
            l.pos++;
            if (!isdigit(l.peek())) {
                throw std::runtime_error("expected digit got: ");
            }
        }
        l.pos++;
    }
}

std::string trim(const std::string &str) {
    std::string s;
    for (auto c : str) {
        if (c != '_') s.push_back(c);
    }
    return s;
}

bool is_hex(char c) {
    return isdigit(c) || c >= 'a' && c <= 'f' || c >= 'A' && c <= 'F';
}

Token Lexer::readNumber() {
    bool dot = false;
    int start = pos;
    if (peek() == '0' && peek(1) == 'x') {
        pos += 2;
        while (is_hex(peek()) || peek() == '_') {
            pos++;
        }
        for (auto &sf : Lexer::suffixes) {
            if (str(pos, pos + sf.length()) == sf) {
                pos += sf.length();
            }
        }
        return Token(INTEGER_LIT, trim(str(start, pos)));
    }
    pos++;
    eatNum(*this);
    if (peek() == '.' && isdigit(buf[pos + 1])) {
        pos += 2;
        eatNum(*this);
        dot = true;
    }
    auto res = trim(str(start, pos));
    auto suf = pos;
    if (peek() == '_') {
        pos++;
    }
    for (auto &sf : Lexer::suffixes) {
        if (str(pos, pos + sf.length()) == sf) {
            pos += sf.length();
            break;
        }
    }
    if (pos > suf) {
        res += str(suf, pos);
    }
    return Token(dot ? FLOAT_LIT : INTEGER_LIT, res);
}

Token Lexer::readIdent() {
    TokenType type;
    int a = pos;
    pos++;
    char c = peek();
    while (isalpha(c) || c == '_' || isdigit(c)) {
        pos++;
        c = peek();
    }
    std::string s = str(a, pos);
    type = kw(s);
    if (type == EOF_) {
        type = IDENT;
    }
    return Token(type, s);
}

Token Lexer::lineComment() {
    int start = pos;
    pos += 2;
    char c = peek();
    while (c != '\n' && c != '\0') {
        pos++;
        c = peek();
    }
    return Token(COMMENT, str(start, pos));
}

Token Lexer::readOp() {
    std::string s = str(pos, pos + 3);
    //can be length of 1 to 3
    for (int i = (int) s.length(); i > 0; i--) {
        auto it = ops.find(s);
        if (it != ops.end()) {
            pos += i;
            return Token(it->second, it->first);
        }
        s.pop_back();
    }
    //never
    throw std::invalid_argument(std::string("readOp() failed with buffer: ") + s);
}

char checkEscape(char c) {
    if (c == 'n') return '\n';
    if (c == 'r') return '\r';
    if (c == 't') return '\t';
    if (c == '"') return '"';
    if (c == '\'') return '\'';
    if (c == '0') return '\0';
    if (c == '\\') return '\\';
    throw std::runtime_error(std::string("invalid escape: \\") + c);
}

Token Lexer::quoted() {
    char start_ch = read();
    std::string s;
    while (pos < buf.size()) {
        char c = read();
        if (c == '\\') {
            auto c2 = checkEscape(buf[pos]);
            s.append(1, c2);
            pos++;
        } else if (c == start_ch) {
            return Token(start_ch == '"' ? STRING_LIT : CHAR_LIT, s);
        } else {
            s.append(1, c);
        }
    }
    throw std::runtime_error("unterminated char literal " + s + " line: " + std::to_string(line));
}

Token Lexer::next() {
    if (pos == buf.length()) {
        return Token(EOF_);
    }
    char c = peek();
    if (c == '\0')
        return Token(EOF_);
    if (c == ' ' || c == '\r' || c == '\n' || c == '\t') {
        pos++;
        if (c == '\n') {
            line++;
        } else if (c == '\r') {
            line++;
            if (pos < buf.length() && buf[pos] == '\n') {
                pos++;
            }
        }
        return next();
    }
    int start = pos;
    std::optional<Token> token;
    if (isalpha(c) || c == '_') {
        token = readIdent();
    } else if (isdigit(c)) {
        token = readNumber();
    } else if (c == '/') {
        char c2 = buf[pos + 1];
        if (c2 == '/') {
            token = lineComment();
        } else if (c2 == '*') {
            pos += 2;
            while (pos < buf.length()) {
                if (buf[pos] == '*') {
                    pos++;
                    if (pos < buf.length() && buf[pos] == '/') {
                        pos++;
                        token = Token(COMMENT, str(start, pos));
                        break;
                    }
                } else {
                    if (buf[pos] == '\r') {
                        pos++;
                        line++;
                        if (buf[pos] == '\n') {
                            pos++;
                        }
                    } else if (buf[pos] == '\n') {
                        pos++;
                        line++;
                    } else {
                        pos++;
                    }
                }
            }
            if (!token.has_value()) {
                throw std::runtime_error("unclosed block comment at line " + std::to_string(line));
            }
        } else {
            token = readOp();
        }
    } else if (c == '\'' || c == '"') {
        token = quoted();
    } else if (ops.find(std::string(1, c)) != ops.end()) {
        token = readOp();
    } else {
        err("unexpected char: " + std::string(&c));
    }
    token->start = start;
    token->end = pos;
    token->line = line;
    return token.value();
}