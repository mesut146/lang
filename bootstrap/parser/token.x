import String

enum TokenType {
    EOF_,
    IDENT,
    CLASS,
    ENUM,
    TRAIT,
    IMPL,
    STATIC,
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
    NULL_LIT,
    INTEGER_LIT,
    FLOAT_LIT,
    CHAR_LIT,
    STRING_LIT,
    COMMENT,
    IMPORT,
    EXTERN,
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
    VIRTUAL,
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
}

func printType(t: TokenType): String{
  return "error type".str();
}

class Token {
    value: String;
    type: TokenType;
    start: i32;
    end: i32;
    line: i32;
}
impl Token{
    func new(t: TokenType): Token{
      return Token::new(t, String::new());
    }

    func new(t: TokenType, s: String): Token{
        return Token{s, t, 0, 0, 0};
    }

   func is(self, t: TokenType): bool {
        return self.type.index == t.index;
    }

    func is(self, t1: TokenType): bool {
        for (auto tt : t) {
            if (tt == type) return true;
        }
        return false;
    }

    func print(self): String {
        return printType(type) + ": " + value;
    }
}