#include "Lexer.h"

TokenType op(char c)
{
    switch (c)
    {
    case '=':
        return EQ;
    case '{':
        return LBRACE;
    case '}':
        return RBRACE;
    case '(':
        return LPAREN;
    case ')':
        return RPAREN;
    case ';':
        return SEMI;
    case ',':
        return COMMA;
    case '.':
        return DOT;
    case ':':
        return COLON;
    }
    return EOF2;
}

TokenType kw(std::string &s)
{
    if (s == "class")
        return CLASS;
    if (s == "enum")
        return ENUM;
    if (s == "interface")
        return INTERFACE;
    if (s == "bool")
        return BOOLEAN;
    if (s == "true")
        return TRUE;
    if (s == "false")
        return FALSE;
    if (s == "long")
        return LONG;
    if (s == "int")
        return INT;
    if (s == "float")
        return FLOAT;
    if (s == "double")
        return DOUBLE;
    if (s == "null")
        return NULL_LIT;
    if (s == "import")
        return IMPORT;
    if (s == "as")
        return AS;
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

    return EOF2;
}

Token* Lexer::readNumber()
{
    bool dot = false;
    int a = pos++;
    while (1)
    {
        char c = peek();
        if (!isdigit(c) && c != '.')
        {
            break;
        }
        dot |= (c == '.');
        pos++;
    }
    return new Token(dot ? FLOAT_LIT : INTEGER_LIT, str(a, pos));
}

Token* Lexer::readIdent()
{
    TokenType type;
    int a = pos;
    pos++;
    while (1)
    {
        char c = peek();
        if (!isalpha(c) && c != '_' && !isdigit(c))
        {
            break;
        }
        pos++;
    }
    std::string s = str(a, pos);
    type = kw(s);
    if (type == EOF2)
    {
        type = IDENT;
    }
    return new Token(type, s);
}


Token* Lexer::lineComment()
{
    int a = pos;
    pos += 2;
    while (1)
    {
        char c = peek();
        if (c == '\n' || c == '\0')
        {
            break;
        }
        pos++;
    }
    return new Token(COMMENT, str(a, pos));
}

Token* Lexer::next()
{
    //std::cout<<"read\n";
    TokenType type;
    char c = peek();
    //std::cout << "c="<<c<<"\n";
    if (c == '\0')
        return new Token(EOF2);
    if (c == ' ' || c == '\r' || c == '\n' || c == '\t')
    {
        pos++;
        return next();
    }
    int off = pos;
    type = op(c);
    if (type != EOF2)
    {
        return new Token(type, str(pos, ++pos));
    }
    else if (isalpha(c) || c == '_')
    {
        return readIdent();
    }
    else if (isdigit(c))
    {
        return readNumber();
    }
    else if (c == '/')
    {
        char c2 = buf[pos + 1];
        if (c2 == '/')
        {
            return lineComment();
        }
        else if(c2 == '*'){
        }
        else{
            return new Token(DIV,str(pos,++pos));
        }
    }
    else if (c == '\'')
    {
        int a = ++pos;
        c = read();
        if (c == '\\')
        { //hex
            c = read();
        }
        else
        {
        }
        return new Token(CHAR_LIT, str(a, pos));
    }
    else if (c == '"')
    {
        return new Token(STRING_LIT, eat("\""));
    }
    return new Token(EOF2);
}