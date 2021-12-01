#pragma once

#include "Token.h"
#include <fstream>
#include <map>
#include <sstream>

class Lexer {
public:
    std::string buf;
    int pos = 0;
    int line = 1;

    Lexer(const std::string &path) {
        std::fstream stream;
        stream.open(path, std::fstream::in);
        std::stringstream ss;
        ss << stream.rdbuf();
        buf = ss.str();
        stream.close();
        init();
    }

    char peek() {
        return buf[pos];
    }

    char read() {
        return buf[pos++];
    }

    std::string str(int a, int b) {
        return buf.substr(a, b - a);
    }

    std::string eat(std::string end) {
        char c;
        int a;
        return str(a, pos);
    }

    Token *next();
    Token *readNumber();
    Token *readIdent();
    Token *lineComment();
    Token *readOp();

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
        ops[">>"] = GTGT;
        ops["<="] = LTEQ;
        ops[">="] = GTEQ;

        ops["|"] = OR;
        ops["&"] = AND;
        ops["||"] = OROR;
        ops["&&"] = ANDAND;

        ops["=>"] = ARROW;
    }
};
