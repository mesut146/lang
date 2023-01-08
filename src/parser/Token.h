#pragma once

#include <stdexcept>
#include <string>
#include <utility>

enum TokenType {
    EOF_,
    IDENT,
    CLASS,
    ENUM,
    INTERFACE,
    STATIC,
    I8, //byte
    I16,//short
    I32,//int
    I64,//long
    F32,//float
    F64,//double
    VOID,
    CHAR,
    BYTE,
    INT,
    LONG,
    FLOAT,
    DOUBLE,
    SHORT,
    BOOLEAN,
    TRUE,
    FALSE,
    NULL_LIT,
    INTEGER_LIT,
    FLOAT_LIT,
    CHAR_LIT,
    STRING_LIT,
    COMMENT,
    IMPORT,
    AS,
    ASSERT_KW,
    FROM,
    RETURN,
    BREAK,
    CONTINUE,
    FUNC,
    LET,
    CONST_KW,
    NEW,
    IF_KW,
    IS,
    ELSE_KW,
    FOR,
    WHILE,
    DO,
    SWITCH,
    CASE,
    THROW,
    TRY,
    CATCH,
    EQ,
    PLUS,
    MINUS,
    STAR,
    DIV,
    POW,
    PERCENT,
    BANG,
    TILDE,
    PLUSPLUS,
    MINUSMINUS,
    QUES,
    SEMI,
    COLON,
    COLON2,
    AND,
    OR,
    ANDAND,
    OROR,
    EQEQ,
    NOTEQ,
    PLUSEQ,
    MINUSEQ,
    MULEQ,
    DIVEQ,
    POWEQ,
    PERCENTEQ,
    LTEQ,
    GTEQ,
    LTLTEQ,
    GTGTEQ,
    OREQ,
    ANDEQ,
    LT,
    GT,
    LTLT,
    GTGT,
    COMMA,
    DOT,
    LPAREN,
    RPAREN,
    LBRACKET,
    RBRACKET,
    LBRACE,
    RBRACE,
    ARROW,
    UNSAFE,
};

std::string printType(TokenType t);

class Token {
public:
    std::string *value;
    TokenType type;
    int start;
    int end;
    int line;

    Token(TokenType t) : type(t) {}

    Token(TokenType t, std::string s) : type(t), value(new std::string(std::move(s))) {}

    bool is(TokenType t) const {
        return t == type;
    }

    bool is(std::initializer_list<TokenType> t) const {
        for (auto tt : t) {
            if (tt == type) return true;
        }
        return false;
    }

    std::string print() const {
        return printType(type) + ": " + *value;
    }
};