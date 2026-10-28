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
    DOLLAR,//$
    //NEW,
}

struct Token {
    //A slice of the source the token was lexed from, not an owned buffer:
    //one heap allocation per token was ~35% of a compile's allocations.
    //The slice points into its Lexer's `buf` (or `scratch`, for a string
    //literal that had escapes rewritten), so it is valid for as long as
    //that Lexer lives -- the Parser owns it and keeps its tokens. Anything
    //that stores token text beyond the parse (AST names, the formatter's
    //comments, TokenStream) must copy with `.owned()`.
    value: str;
    type: TokenType;
    start: i32;
    end: i32;
    line: i32;
}

impl Token{
    func new(tt: TokenType): Token{
      return Token{"", tt, 0, 0, 0};
    }

    func new(tt: TokenType, val: str): Token{
        return Token{val, tt, 0, 0, 0};
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
        f.print(self.value);
        f.print("', ");
        f.print("type: ");
        self.type.debug(f);
        f.print("}");
    }
}

//A source comment stripped from the token stream and kept for the
//formatter (line: 1-based source line, text includes the // or /* */
//markers, without trailing newline). Lives here, next to the COMMENT
//tokens it comes from -- not in std: Fmt must stay a generic buffer,
//and std cannot name ast types.
struct Comment{
  line: i32;
  text: String;
}