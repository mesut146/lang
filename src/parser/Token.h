#pragma once

#include <stdexcept>
#include <string>
#include <utility>

enum TokenType {
    EOF_,
    IDENT,
    CLASS,
    STRUCT,
    ENUM,
    TRAIT,
    IMPL,
    STATIC,
    TYPE,
    MATCH,
    I8,
    I16,
    I32,
    I64,
    F32,
    F64,
    U8,
    U16,
    U32,
    U64,
    VOID,
    BOOLEAN,
    TRUE,
    FALSE,
    INTEGER_LIT,
    FLOAT_LIT,
    CHAR_LIT,
    STRING_LIT,
    COMMENT,
    IMPORT,
    EXTERN,
    AS,
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
    VIRTUAL,
    NAMESPACE,
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
    DOTDOT,
    LPAREN,
    RPAREN,
    LBRACKET,
    RBRACKET,
    LBRACE,
    RBRACE,
    ARROW,
    HASH,
};

std::string printType(TokenType t);

class Token {
public:
    std::string value;
    TokenType type;
    int start;
    int end;
    int line;

    Token(TokenType t) : type(t) {}

    Token(TokenType t, const std::string &s) : type(t), value(std::move(s)) {}

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
        return "{type: " + printType(type) + ", val: " + value + "}";
    }
};