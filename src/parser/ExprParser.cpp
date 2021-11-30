#include "ExprParser.h"
#include "Parser.h"


std::vector<Expression *> exprList(Parser *p) {
    std::vector<Expression *> res;
    res.push_back(parseExpr(p));
    while (p->first()->is(COMMA)) {
        p->consume(COMMA);
        res.push_back(parseExpr(p));
    }
    return res;
}

Expression *parsePar(Parser *p) {
    auto *res = new ParExpr;
    p->consume(LPAREN);
    res->expr = parseExpr(p);
    p->consume(RPAREN);
    return res;
}

bool isLit(Token &t) {
    return t.is({FLOAT_LIT, INTEGER_LIT, CHAR_LIT, STRING_LIT, TRUE, FALSE});
}

bool isPrim(Token &t) {
    return t.is({INT, LONG, FLOAT, DOUBLE, CHAR, BYTE});
}

bool isType(Parser *p) {
    Token t = *p->peek();
    if (isPrim(t) || t.is({VOID, LET, VAR})) {
        return true;
    }
    if (t.is(IDENT)) {
        return true;
    }
    return false;
}

Literal *parseLit(Parser *p) {
    Literal *res = new Literal;
    Token t = *p->pop();
    res->val = *t.value;
    res->isFloat = t.is(FLOAT_LIT);
    res->isBool = t.is({TRUE, FALSE});
    res->isInt = t.is(INTEGER_LIT);
    res->isStr = t.is(STRING_LIT);
    res->isChar = t.is(CHAR_LIT);
    return res;
}

//simple or  qualified name
Name *qname(Parser *p) {
    auto *s = new SimpleName;
    s->name = p->consume(IDENT)->value;
    if (p->first()->is(DOT)) {
        Name *cur = s;
        while (p->peek()->is(DOT) && p->peek()->is(IDENT)) {
            p->consume(DOT);
            auto *tmp = new QName;
            tmp->scope = cur;
            tmp->name = *p->consume(IDENT)->value;
            cur = tmp;
        }
        return cur;
    } else {
        return s;
    }
}

Type *parseType(Parser *p) {
    Token t = *p->first();
    if (isPrim(t) || t.is({VOID, LET, VAR})) {
        p->pop();
        auto *s = new SimpleType;
        s->type = t.value;
        return s;
    } else {
        return refType(p);
    }
}

std::vector<Type *> generics(Parser *p) {
    std::vector<Type *> list;
    p->consume(LT);
    list.push_back(parseType(p));
    while (p->first()->is(COMMA)) {
        p->consume(COMMA);
        list.push_back(parseType(p));
    }
    p->consume(GT);
    return list;
}

RefType *refType(Parser *p) {
    auto *res = new RefType;
    res->name = qname(p);
    if (p->first()->is(LT)) {
        res->typeArgs = generics(p);
    }
    return res;
}

Entry parseEntry(Parser *p) {
    Entry e;
    e.key = parseExpr(p);
    p->consume(COLON);
    e.value = parseExpr(p);
    return e;
}

Expression *PRIM(Parser *p) {
    log("parsePrimary " + *p->first()->value);
    if (p->is(LPAREN)) {
        auto res = new ParExpr;
        p->consume(LPAREN);
        res->expr = parseExpr(p);
        p->consume(RPAREN);
        return res;
    } else if (isLit(*p->first())) {
        return parseLit(p);
    } else if (p->is(IDENT)) {
        auto id = p->pop()->value;
        if (p->is(LPAREN)) {
            auto res = new MethodCall;
            res->name = *id;
            p->consume(LPAREN);
            if (!p->is(RPAREN)) {
                res->args = exprList(p);
            }
            p->consume(RPAREN);
            return res;
        } else if (p->is(LBRACE)) {
            auto res = new ObjExpr;
            res->name = *id;
            p->consume(LBRACE);
            res->entries.push_back(parseEntry(p));
            while (p->is(COMMA)) {
                p->consume(COMMA);
                res->entries.push_back(parseEntry(p));
            }
            p->consume(RBRACE);
            return res;
        } else {
            auto *s = new SimpleName;
            s->name = id;
            return s;
        }
    } else if (p->is(LBRACE)) {
        auto res = new AnonyObjExpr;
        p->consume(LBRACE);
        res->entries.push_back(parseEntry(p));
        while (p->is(COMMA)) {
            p->consume(COMMA);
            res->entries.push_back(parseEntry(p));
        }
        p->consume(RBRACE);
        return res;
    } else if (p->is(LBRACKET)) {
        auto res = new ArrayExpr;
        p->consume(LBRACKET);
        if (!p->is(RBRACKET)) {
            res->list = exprList(p);
        }
        p->consume(RBRACKET);
        return res;
    } else {
        throw std::string("invalid primary " + *p->first()->value + " line: " + std::to_string(p->first()->line));
    }
}

//PRIM (dot name ('(' ')')? | [ E ])*
Expression *PRIM2(Parser *p) {
    Expression *lhs = PRIM(p);
    while (p->is({DOT, LBRACKET})) {
        if (p->is(DOT)) {
            p->consume(DOT);
            auto name = p->name();
            if (p->is(LPAREN)) {
                auto res = new MethodCall;
                res->scope = lhs;
                res->name = *name;
                p->consume(LPAREN);
                if (!p->is(RPAREN)) {
                    res->args = exprList(p);
                }
                p->consume(RPAREN);
                lhs = res;
            } else {
                auto res = new FieldAccess;
                res->scope = lhs;
                res->name = *name;
                lhs = res;
            }
        } else {
            auto res = new ArrayAccess;
            res->array = lhs;
            p->consume(LBRACKET);
            res->index = parseExpr(p);
            p->consume(RBRACKET);
            lhs = res;
        }
    }
    return lhs;
}


//expr14 ("++" | "--")* #post
Expression *expr13(Parser *p) {
    Expression *lhs = PRIM2(p);
    while (p->is({PLUSPLUS, MINUSMINUS})) {
        auto res = new Postfix;
        res->op = *p->pop()->value;
        res->expr = lhs;
        lhs = res;
    }
    return lhs;
}

//("+" | "-" | "++" | "--" | "!" | "~" | "(" type ")" expr12) expr #unary
Expression *expr12(Parser *p) {
    if (p->is({PLUS, MINUS, PLUSPLUS, MINUSMINUS, BANG, TILDE})) {
        auto res = new Unary;
        res->op = *p->pop()->value;
        res->expr = expr12(p);
        return res;
    } else if (p->is(LPAREN)) {
        //cast or paren
        //after closig pare there must e idet
        throw std::string("not yet");
    } else {
        return expr13(p);
    }
}

//expr12 ("*" | "/" | "%" expr12)*
Expression *expr11(Parser *p) {
    Expression *lhs = expr12(p);
    while (p->is({MUL, DIV, PERCENT})) {
        auto res = new Infix;
        res->left = lhs;
        res->op = *p->pop()->value;
        res->right = expr12(p);
        lhs = res;
    }
    return lhs;
}

//expr11 ("+" | "-" expr11)*
Expression *expr10(Parser *p) {
    Expression *lhs = expr11(p);
    while (p->is({PLUS, MINUS})) {
        auto res = new Infix;
        res->left = lhs;
        res->op = *p->pop()->value;
        res->right = expr11(p);
        lhs = res;
    }
    return lhs;
}

//expr10 ("<<" | ">" ">" | ">" ">" ">" expr10)*
Expression *expr9(Parser *p) {
    Expression *lhs = expr10(p);
    while (p->is({LTLT, GT})) {
        std::string ops = *p->pop()->value;
        if (ops == ">") {
            ops = ">>";
            p->consume(GT);
            if (p->is(GT)) {
                ops = ">>>";
                p->consume(GT);
            }
        }
        auto res = new Infix;
        res->left = lhs;
        res->op = ops;
        res->right = expr10(p);
        lhs = res;
    }
    return lhs;
}

//expr9 ("<" | ">" | "<=" | ">=" expr9)*
Expression *expr8(Parser *p) {
    Expression *lhs = expr9(p);
    while (p->is({LT, GT, LTEQ, GTEQ})) {
        auto res = new Infix;
        res->left = lhs;
        res->op = *p->pop()->value;
        res->right = expr9(p);
        lhs = res;
    }
    return lhs;
}

//expr8 ("==" | "!=" expr8)*
Expression *expr7(Parser *p) {
    Expression *lhs = expr8(p);
    while (p->is({EQEQ, NOTEQ})) {
        auto res = new Infix;
        res->left = lhs;
        res->op = *p->pop()->value;
        res->right = expr8(p);
        lhs = res;
    }
    return lhs;
}

//expr7 ("&" expr7)*
Expression *expr6(Parser *p) {
    Expression *lhs = expr7(p);
    while (p->is(AND)) {
        auto res = new Infix;
        res->left = lhs;
        res->op = *p->pop()->value;
        res->right = expr7(p);
        lhs = res;
    }
    return lhs;
}

//expr6 ("^" expr6)*
Expression *expr5(Parser *p) {
    Expression *lhs = expr6(p);
    while (p->is(POW)) {
        auto res = new Infix;
        res->left = lhs;
        res->op = *p->pop()->value;
        res->right = expr6(p);
        lhs = res;
    }
    return lhs;
}

//expr5 ("|" expr5)*
Expression *expr4(Parser *p) {
    Expression *lhs = expr5(p);
    while (p->is(OR)) {
        auto res = new Infix;
        res->left = lhs;
        res->op = *p->pop()->value;
        res->right = expr5(p);
        lhs = res;
    }
    return lhs;
}

//expr4 ("&&" expr4)*
Expression *expr3(Parser *p) {
    Expression *lhs = expr4(p);
    while (p->is(ANDAND)) {
        auto res = new Infix;
        res->left = lhs;
        res->op = *p->pop()->value;
        res->right = expr4(p);
    }
    return lhs;
}

//expr3 ("||" expr)*
Expression *expr2(Parser *p) {
    Expression *lhs = expr3(p);
    while (p->is(OROR)) {
        auto res = new Infix;
        res->left = lhs;
        res->op = *p->pop()->value;
        res->right = expr3(p);
        lhs = res;
    }
    return lhs;
}


//ternary
Expression *expr1(Parser *p) {
    Expression *lhs = expr2(p);
    if (p->first()->is(QUES)) {
        Ternary *t = new Ternary;
        t->cond = lhs;
        p->consume(QUES);
        t->thenExpr = parseExpr(p);
        p->consume(COLON);
        t->elseExpr = expr1(p);
        lhs = t;
    }
    return lhs;
}

bool isAssign(std::string &s) {
    return s == "=" || s == "+=" | s == "-=" | s == "*=" | s == "/=" | s == "%=" | s == "&=" | s == "^=" | s == "|=" | s == "<<=" | s == ">>=" | s == ">>>=";
}

//expr1 (op expr)?
Expression *parseExpr(Parser *p) {
    log("parseExpr " + *p->first()->value);
    Token t = *p->first();
    Expression *res = expr1(p);
    if (isAssign(*p->first()->value)) {
        auto assign = new Assign;
        assign->left = res;
        assign->op = *p->pop()->value;
        assign->right = parseExpr(p);
        res = assign;
    }
    return res;
}
