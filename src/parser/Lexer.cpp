#include "Lexer.h"
#include <map>

TokenType kw(std::string &s) {
    if (s == "assert") return ASSERT_KW;
    if (s == "class") return CLASS;
    if (s == "enum") return ENUM;
    if (s == "interface") return INTERFACE;
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
    if (s == "long")
        return LONG;
    if (s == "int")
        return INT;
    if (s == "float")
        return FLOAT;
    if (s == "double")
        return DOUBLE;
    if (s == "short")
        return SHORT;
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

Token *Lexer::readNumber() {
    bool dot = false;
    int start = pos;
    pos++;
    char c = peek();
    while (isdigit(c) || c == '.') {
        dot |= (c == '.');
        pos++;
        c = peek();
    }
    return new Token(dot ? FLOAT_LIT : INTEGER_LIT, str(start, pos));
}

Token *Lexer::readIdent() {
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
    return new Token(type, s);
}

Token *Lexer::lineComment() {
    int start = pos;
    pos += 2;
    char c = peek();
    while (c != '\n' && c != '\0') {
        pos++;
        c = peek();
    }
    return new Token(COMMENT, str(start, pos));
}

Token *Lexer::readOp() {
    std::string s = str(pos, pos + 3);

    int off = pos;
    //can be length of 1 to 3
    for (int i = (int) s.length(); i > 0; i--) {
        auto it = ops.find(s);
        if (it != ops.end()) {
            pos += i;
            return new Token(it->second, it->first);
        }
        s.pop_back();
    }
    //never
    throw std::invalid_argument(std::string("readOp() failed with buffer: ") + s);
}

Token *Lexer::next() {
    if (pos == buf.length()) {
        return new Token(EOF_);
    }
    char c = peek();
    if (c == '\0')
        return new Token(EOF_);
    if (c == ' ' || c == '\r' || c == '\n' || c == '\t') {
        pos++;
        if (c == '\n') {
            line++;
        } else if (c == '\r') {
            if (pos < buf.length() && buf[pos] == '\n') {
                line++;
                pos++;
            }
        }
        return next();
    }
    int off = pos;
    Token *token;
    if (isalpha(c) || c == '_') {
        token = readIdent();
    } else if (isdigit(c)) {
        token = readNumber();
    } else if (c == '/') {
        char c2 = buf[pos + 1];
        if (c2 == '/') {
            token = lineComment();
        } else if (c2 == '*') {
            auto it = buf.find("*/", pos + 2);
            if (it != std::string::npos) {
                token = new Token(COMMENT, str(pos, it + 2));
                pos = it + 2;
            } else {
                throw std::runtime_error("unclosed block comment at line " + std::to_string(line));
            }
        } else {
            token = new Token(DIV, str(pos, pos + 1));
            pos++;
        }
    } else if (c == '\'') {
        auto a = pos;
        pos++;
        while (pos < buf.size()) {
            c = read();
            if (c == '\\') {
                pos++;
            } else if (c == '"') {
                break;
            }
        }
        token = new Token(CHAR_LIT, str(a, pos));
    } else if (c == '"') {
        auto a = pos;
        pos++;
        while (pos < buf.size()) {
            c = read();
            if (c == '\\') {
                pos++;
            } else if (c == '"') {
                break;
            }
        }
        token = new Token(STRING_LIT, str(a, pos));
    } else if (ops.find(std::string(1, c)) != ops.end()) {
        token = readOp();
    } else {
        throw std::runtime_error("unexpected char: " + std::string(&c));
    }
    token->start = off;
    token->end = pos;
    token->line = line;
    return token;
}