#include "ExprParser.h"
#include "Parser.h"
#include "Token.h"

bool isOp(std::string &s) {
    return s == "+" || s == "-" || s == "<=";
}

bool isAssign(std::string &s) {
    return s == "=" || s == "+=" || s == "-=";
}

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

bool isLit(Token t) {
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

Expression *primary(Parser *p) {
    log("parsePrimary " + *p->first()->value);
    Token t = *p->first();
    Expression *prim;
    if (isLit(t)) {
        prim = parseLit(p);
    } else if (t.is({PLUSPLUS, MINUSMINUS, PLUS, MINUS, TILDE, BANG})) {
        auto unary = new Unary;
        unary->op = *p->pop()->value;
        unary->expr = parseExpr(p);
        prim = unary;
    } else if (t.is(LPAREN)) {
        prim = parsePar(p);
    } else if (t.is(IDENT)) {
        Name *name = qname(p);
        prim = name;
        if (p->first()->is(DOT)) {
            p->consume(DOT);
            //method call,field access
        } else if (p->first()->is(LPAREN)) {
            p->consume(LPAREN);
            auto call = new MethodCall;
            if (!p->first()->is(RPAREN)) {
                call->args = exprList(p);
            }
            if (auto nm = dynamic_cast<QName *>(name)) {
                call->name = nm->name;
                call->scope = nm->scope;
            } else {
                call->name = name->print();
            }
            prim = call;
            p->consume(RPAREN);
        }
    } else {
        throw std::string("invalid expr " + *t.value + " line: " + std::to_string(t.line));
    }
    return prim;
}

Expression *parseExpr(Parser *p) {
    log("parseExpr " + *p->first()->value);
    Token t = *p->first();
    //parse primary
    Expression *prim = primary(p);

    //log("prim =" + prim->print());
    if (isOp(*p->first()->value)) {
        auto infix = new Infix;
        infix->left = prim;
        infix->op = *p->pop()->value;
        infix->right = parseExpr(p);
        prim = infix;
    } else if (p->first()->is({PLUSPLUS, MINUSMINUS})) {
        auto post = new Postfix;
        post->expr = prim;
        post->op = *p->pop()->value;
        prim = post;
    } else if (isAssign(*p->first()->value)) {
        auto assign = new Assign;
        assign->left = prim;
        assign->op = *p->pop()->value;
        assign->right = parseExpr(p);
        prim = assign;
    }
    log("expr = " + prim->print());
    return prim;
}

VarDecl *varDecl(Parser *p) {
    auto type = parseType(p);
    auto name = refType(p);
    return varDecl(p, type, name);
}

Fragment frag(Parser *p) {
    std::string name = refType(p)->print();
    Expression *right = nullptr;
    if (p->first()->is(EQ)) {
        p->consume(EQ);
        right = parseExpr(p);
    }
    return Fragment(name, right);
}

VarDecl *varDecl(Parser *p, Type *type, RefType *nm) {
    log("varDecl = " + nm->print());
    VarDecl *res = new VarDecl;
    res->type = type;
    Expression *r = nullptr;
    if (p->first()->is(EQ)) {
        p->consume(EQ);
        r = parseExpr(p);
    }
    //first frag
    res->list.push_back(Fragment(nm->print(), r));
    //rest if any
    while (p->first()->is(COMMA)) {
        p->consume(COMMA);
        res->list.push_back(frag(p));
    }
    return res;
}