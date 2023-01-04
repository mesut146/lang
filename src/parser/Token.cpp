#include "Token.h"

#define TOKEN_CASE(label) \
    case label:           \
        return #label;

std::string printType(TokenType t) {
    switch (t) {
        TOKEN_CASE(ASSERT_KW)
        TOKEN_CASE(CLASS)
        TOKEN_CASE(NEW)
        TOKEN_CASE(LET)
        TOKEN_CASE(RETURN)
        TOKEN_CASE(FROM)
        TOKEN_CASE(IS)

        TOKEN_CASE(BOOLEAN)
        TOKEN_CASE(INT)
        TOKEN_CASE(LONG)
        TOKEN_CASE(BYTE)
        TOKEN_CASE(CHAR)
        TOKEN_CASE(SHORT)
        TOKEN_CASE(FLOAT)
        TOKEN_CASE(DOUBLE)
        TOKEN_CASE(I8)
        TOKEN_CASE(I16)
        TOKEN_CASE(I32)
        TOKEN_CASE(I64)
        TOKEN_CASE(F32)
        TOKEN_CASE(F64)
        TOKEN_CASE(VOID)

        TOKEN_CASE(DOT)
        TOKEN_CASE(SEMI)
        TOKEN_CASE(LBRACKET)
        TOKEN_CASE(RBRACKET)
        TOKEN_CASE(COMMA)
        TOKEN_CASE(COLON)
        TOKEN_CASE(COLON2)
        TOKEN_CASE(LBRACE)
        TOKEN_CASE(RBRACE)
        TOKEN_CASE(LPAREN)
        TOKEN_CASE(RPAREN)
        TOKEN_CASE(QUES)

        TOKEN_CASE(BANG)
        TOKEN_CASE(TILDE)
        TOKEN_CASE(LT)
        TOKEN_CASE(GT)
        TOKEN_CASE(EQEQ)
        TOKEN_CASE(GTEQ)
        TOKEN_CASE(LTEQ)
        TOKEN_CASE(LTLTEQ)
        TOKEN_CASE(GTGTEQ)
        TOKEN_CASE(NOTEQ)
        TOKEN_CASE(ANDAND)
        TOKEN_CASE(OROR)

        TOKEN_CASE(PLUSPLUS)
        TOKEN_CASE(MINUSMINUS)

        TOKEN_CASE(EQ)
        TOKEN_CASE(PLUSEQ)
        TOKEN_CASE(MINUSEQ)
        TOKEN_CASE(MULEQ)
        TOKEN_CASE(DIVEQ)
        TOKEN_CASE(PERCENTEQ)
        TOKEN_CASE(POWEQ)

        TOKEN_CASE(PLUS)
        TOKEN_CASE(MINUS)
        TOKEN_CASE(STAR)
        TOKEN_CASE(DIV)
        TOKEN_CASE(PERCENT)
        TOKEN_CASE(POW)
        TOKEN_CASE(AND)
        TOKEN_CASE(OR)

        TOKEN_CASE(IDENT)

        default:
            break;
    }
    return "error type(" + std::to_string(t) + ")";
}