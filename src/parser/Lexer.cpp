#include "Lexer.h"
#include <map>
#include <vector>

TokenType kw(std::string &s) {
    if (s == "assert") return ASSERT_KW;
    if (s == "class") return CLASS;
    if (s == "enum") return ENUM;
    if (s == "trait") return TRAIT;
    if (s == "impl") return IMPL;
    if (s == "extern") return EXTERN;
    if (s == "virtual") return VIRTUAL;
    if (s == "static") return STATIC;
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

Token Lexer::readNumber() {
    bool dot = false;
    int start = pos;
    pos++;
    char c = peek();
    while (isdigit(c) || (c == '.' & isdigit(buf[pos + 1]))) {
        dot |= (c == '.');
        pos++;
        c = peek();
    }
    std::vector<std::string> suffixMap = {"i8", "i16", "i32", "i64", "f32", "f64"};
    for (auto &s : suffixMap) {
        if (str(pos, pos + s.length()) == s) {
            pos += s.length();
            break;
        }
    }
    return Token(dot ? FLOAT_LIT : INTEGER_LIT, str(start, pos));
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
    throw std::runtime_error(std::string("invalid escape: \\") + c);
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
    } else if (c == '\'') {
        pos++;
        while (pos < buf.size()) {
            c = read();
            if (c == '\\') {
                pos++;
            } else if (c == '\'') {
                token = Token(CHAR_LIT, str(start, pos));
                break;
            }
        }
        if (!token) throw std::runtime_error("unterminated char literal");
    } else if (c == '"') {
        std::string s;
        s.append(1, c);
        pos++;
        while (pos < buf.size()) {
            c = read();
            if (c == '\\') {
                auto c2 = checkEscape(buf[pos]);
                s.append(1, c2);
                pos++;
            } else if (c == '"') {
                s.append(1, c);
                break;
            } else {
                s.append(1, c);
            }
        }
        token = Token(STRING_LIT, s);
    } else if (ops.find(std::string(1, c)) != ops.end()) {
        token = readOp();
    } else {
        throw std::runtime_error("unexpected char: " + std::string(&c));
    }
    token->start = start;
    token->end = pos;
    token->line = line;
    return token.value();
}