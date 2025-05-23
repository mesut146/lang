#derive(Debug)
enum TokenType {
    EOF_,
    IDENT,
    STRUCT,
    ENUM,
    TRAIT,
    IMPL,
    STATIC,
    TYPE,
    MOD,
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
    RETURN,
    BREAK,
    CONTINUE,
    FUNC,
    LET,
    CONST,
    IF,
    IS,
    ELSE,
    FOR,
    WHILE,
    DO,
    MATCH,
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
    COLON2,//::
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
    ARROW,//=>
    HASH,
    //NEW,
}

struct Token {
    value: String;
    type: TokenType;
    start: i32;
    end: i32;
    line: i32;
}

impl Token{
    func new(tt: TokenType): Token{
      return Token::new(tt, String::new());
    }

    func new(tt: TokenType, val: String): Token{
        return Token{val, tt, 0, 0, 0};
    }
    
    func new(tt: TokenType, val: str): Token{
        return Token{String::new(val), tt, 0, 0, 0};
    }

   func is(self, tt: TokenType): bool {
        return self.type is tt;
    }

    func is(self, arr: [TokenType]): bool {
        for (let i = 0;i < arr.len();++i) {
            if (self.type is arr[i]) return true;
        }
        return false;
    }

    func print(self): String {
        return Fmt::str(self);
    }
}

impl Debug for Token{
    func debug(self, f: Fmt*){
        f.print("Token{");
        f.print("line: ");
        self.line.debug(f);
        f.print(", ");
        f.print("value: '");
        f.print(&self.value);
        f.print("', ");
        f.print("type: ");
        self.type.debug(f);
        f.print("}");
    }
}