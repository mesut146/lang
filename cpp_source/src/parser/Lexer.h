#pragma once

#include "Token.h"
#include <fstream>
#include <map>
#include <sstream>
#include <system_error>
#include <vector>

class Lexer {
public:
    std::string path;
    std::string buf;
    int pos = 0;
    int line = 1;
    static std::vector<std::string> suffixes;

    explicit Lexer(const std::string &path) : path(path) {
        std::fstream stream;
        stream.open(path, std::fstream::in);
        if (!stream.is_open()) throw std::system_error(errno, std::system_category(), "failed to open " + path);
        std::stringstream ss;
        ss << stream.rdbuf();
        buf = ss.str();
        stream.close();
        init();
    }
    explicit Lexer(const std::string &buf, bool is_buf) : path("<buf>"), buf(buf) {
        init();
    }

    char peek(int la = 0) {
        return buf[pos + la];
    }

    char read() {
        return buf[pos++];
    }

    std::string str(int a, int b) const {
        return buf.substr(a, b - a);
    }

    void err(const std::string &msg) {
        throw std::runtime_error(path + ":" + std::to_string(line) + "\n" + msg);
    }

    Token next();
    Token readNumber();
    Token readIdent();
    Token lineComment();
    Token readOp();
    Token quoted();

    std::map<std::string, TokenType> ops;

    void init() {
        ops["{"] = LBRACE;
        ops["}"] = RBRACE;
        ops["("] = LPAREN;
        ops[")"] = RPAREN;
        ops["["] = LBRACKET;
        ops["]"] = RBRACKET;
        ops["."] = DOT;
        ops[","] = COMMA;
        ops[";"] = SEMI;
        ops[":"] = COLON;
        ops["?"] = QUES;
        ops["!"] = BANG;
        ops["~"] = TILDE;

        ops["+"] = PLUS;
        ops["-"] = MINUS;
        ops["*"] = STAR;
        ops["/"] = DIV;
        ops["^"] = POW;
        ops["%"] = PERCENT;

        ops["++"] = PLUSPLUS;
        ops["--"] = MINUSMINUS;

        ops["="] = EQ;
        ops["=="] = EQEQ;
        ops["+="] = PLUSEQ;
        ops["-="] = MINUSEQ;
        ops["*="] = MULEQ;
        ops["/="] = DIVEQ;
        ops["^="] = POWEQ;
        ops["%="] = PERCENTEQ;
        ops["<<="] = LTLTEQ;
        ops[">>="] = GTGTEQ;
        ops["|="] = OREQ;
        ops["&="] = ANDEQ;
        ops["!="] = NOTEQ;

        ops["<"] = LT;
        ops[">"] = GT;
        ops["<<"] = LTLT;
        //ops[">>"] = GTGT;
        ops["<="] = LTEQ;
        ops[">="] = GTEQ;

        ops["|"] = OR;
        ops["&"] = AND;
        ops["||"] = OROR;
        ops["&&"] = ANDAND;

        ops["=>"] = ARROW;
        ops["::"] = COLON2;
        ops[".."] = DOTDOT;
        ops["#"] = HASH;
    }
};
