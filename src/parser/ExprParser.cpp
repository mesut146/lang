#pragma clang diagnostic push
#pragma ide diagnostic ignored "misc-no-recursion"
#include "Parser.h"
#include "Util.h"


std::vector<Expression *> Parser::exprList() {
    std::vector<Expression *> res;
    res.push_back(parseExpr());
    while (is(COMMA)) {
        consume(COMMA);
        res.push_back(parseExpr());
    }
    return res;
}

bool isLit(Token *t) {
    return t->is({FLOAT_LIT, INTEGER_LIT, CHAR_LIT, STRING_LIT, TRUE, FALSE});
}

bool Parser::isPrim(Token &t) {
    return t.is({BOOLEAN, INT, LONG, FLOAT, DOUBLE, CHAR, BYTE, VOID});
}

Literal *parseLit(Parser *p) {
    auto *res = new Literal;
    Token t = *p->pop();
    res->val = *t.value;
    res->isFloat = t.is(FLOAT_LIT);
    res->isBool = t.is({TRUE, FALSE});
    res->isInt = t.is(INTEGER_LIT);
    res->isStr = t.is(STRING_LIT);
    res->isChar = t.is(CHAR_LIT);
    return res;
}

bool isTypeArg(Parser *p, TokenType next) {
    p->backup();
    try {
        p->generics();
        p->consume(next);
        p->restore();
        return true;
    } catch (...) {}
    p->restore();
    return false;
}

//name ("." name)*
Name *Parser::qname() {
    Name *res = new SimpleName(*name());
    while (is({DOT}, {IDENT})) {
        consume(DOT);
        res = new QName(res, *name());
    }
    return res;
}

Type *Parser::refType() {
    Type *res = new Type;
    res->name = *consume(IDENT)->value;
    while (is({DOT, LT})) {
        if (is(LT)) {
            res->typeArgs = generics();
        } else {
            consume(DOT);
            auto tmp = new Type;
            tmp->name = *consume(IDENT)->value;
            tmp->scope = res;
            res = tmp;
        }
    }
    return res;
}

Type *Parser::parseType() {
    auto res = new Type;
    if (isPrim(*first())) {
        res->name = *pop()->value;
    } else {
        res->name = *consume(IDENT)->value;
        while (is({COLON2, LT})) {
            if (is(LT)) {
                res->typeArgs = generics();
            } else {
                consume(COLON2);
                auto tmp = new Type;
                tmp->name = *consume(IDENT)->value;
                tmp->scope = res;
                res = tmp;
            }
        }
    }
    while (is(LBRACKET)) {
        consume(LBRACKET);
        if (!is(RBRACKET)) {
            res->dims.push_back(parseExpr());
        } else {
            res->dims.push_back(nullptr);
        }
        consume(RBRACKET);
    }
    while (is(STAR) || is(QUES)) {
        if (is(STAR)) {
            consume(STAR);
            auto tmp = new PointerType;
            tmp->type = res;
            res = tmp;
        } else if (is(QUES)) {
            consume(QUES);
            auto tmp = new OptionType;
            tmp->type = res;
            res = tmp;
        }
    }
    return res;
}

std::vector<Type *> Parser::generics() {
    std::vector<Type *> list;
    consume(LT);
    list.push_back(parseType());
    while (is(COMMA)) {
        consume(COMMA);
        list.push_back(parseType());
    }
    consume(GT);
    return list;
}

Entry parseEntry(Parser *p) {
    Entry e{};
    if (p->is({IDENT}, {COLON})) {
        e.key = *p->consume(IDENT)->value;
        p->consume(COLON);
        e.value = p->parseExpr();
    } else {
        //single expr
        e.value = p->parseExpr();
    }
    return e;
}

MapEntry parseMapEntry(Parser *p) {
    //lit,ident
    MapEntry e{};
    if (p->is(IDENT)) {
        e.key = new SimpleName(*p->consume(IDENT)->value);
    } else if (isLit(p->first())) {
        e.key = parseLit(p);
    }
    p->consume(COLON);
    e.value = p->parseExpr();
    return e;
}

bool isObj(Parser *p) {
    p->backup();
    try {
        if (!p->is(IDENT)) {
            p->restore();
            return false;
        }
        p->parseType();
        if (p->is(LBRACE)) {
            p->restore();
            return true;
        }
    } catch (...) {}
    p->restore();
    return false;
}

Expression *makeObj(Parser *p, bool isPointer, Type *type) {
    auto res = new ObjExpr;
    res->isPointer = isPointer;
    res->type = type;
    p->consume(LBRACE);
    res->entries.push_back(parseEntry(p));
    while (p->is(COMMA)) {
        p->consume(COMMA);
        res->entries.push_back(parseEntry(p));
    }
    //todo check entry keys for mix
    p->consume(RBRACE);
    return res;
}

Expression *makeObj(Parser *p, bool isPointer) {
    return makeObj(p, isPointer, p->parseType());
}

Expression *makeAlloc(Parser *p) {
    p->consume(NEW);
    auto type = p->parseType();
    if (type->isArray()) {
        auto res = new ArrayCreation;
        res->type = type;

        return res;
    }
    return makeObj(p, true, type);
}

Expression *parseCall(Parser *p, std::string name) {
    auto res = new MethodCall;
    res->name = name;
    if (p->is(LT)) {
        res->typeArgs = p->generics();
    }
    p->consume(LPAREN);
    if (!p->is(RPAREN)) {
        res->args = p->exprList();
    }
    p->consume(RPAREN);
    return res;
}

//"(" expr ")" | arrow | literal | objCreation | arrayCreation | name | mc
Expression *PRIM(Parser *p) {
    //log("parsePrimary " + *p->first()->value);
    if (p->is(LPAREN)) {
        //ParExpr
        auto res = new ParExpr;
        p->consume(LPAREN);
        res->expr = p->parseExpr();
        p->consume(RPAREN);
        return res;
    } else if (isLit(p->first())) {
        return parseLit(p);
    } else if (p->is(NEW)) {
        return makeAlloc(p);
    } else if (isObj(p)) {
        return makeObj(p, false);
    } else if(p->is({IDENT},{COLON2})){
        auto t = p->parseType();
        if(p->is(LPAREN)){
            auto res = new MethodCall;
            res->scope = t->scope;
            res->name = t->name;
            if (p->is(LT)) {
                res->typeArgs = p->generics();
            }
            p->consume(LPAREN);
            if (!p->is(RPAREN)) {
                res->args = p->exprList();
            }
            p->consume(RPAREN);
            return res;
        }else{
            //static field access, or enum variant
            /*auto res = new FieldAccess;
            res->scope=t->scope;
            res->name=t->name;*/
            return t;
        }
    } 
    else if (p->is({IDENT, FROM})) {
        auto id = p->pop()->value;
        if (p->is(LPAREN) || isTypeArg(p, LPAREN)) {
            auto res = new MethodCall;
            res->name = *id;
            if (p->is(LT)) {
                res->typeArgs = p->generics();
            }
            p->consume(LPAREN);
            if (!p->is(RPAREN)) {
                res->args = p->exprList();
            }
            p->consume(RPAREN);
            return res;
        } else {
            auto *res = new SimpleName(*id);
            return res;
        }
    }else if (p->is(LBRACE)) {
        auto res = new MapExpr;
        p->consume(LBRACE);
        res->entries.push_back(parseMapEntry(p));
        while (p->is(COMMA)) {
            p->consume(COMMA);
            res->entries.push_back(parseMapEntry(p));
        }
        p->consume(RBRACE);
        return res;
    } else if (p->is(LBRACKET)) {
        auto res = new ArrayExpr;
        p->consume(LBRACKET);
        if (!p->is(RBRACKET)) {
            res->list = p->exprList();
        }
        p->consume(RBRACKET);
        return res;
    } else if (p->is(FUNC)) {
        auto res = new ArrayCreation;
        res->type = p->parseType();
        while (p->is(LBRACKET)) {
            p->pop();
            res->dims.push_back(p->parseExpr());
            p->consume(RBRACKET);
        }
        return res;
    } else {
        throw std::runtime_error("invalid primary " + *p->first()->value + " line: " + std::to_string(p->first()->line));
    }
}

//PRIM ('.' name ('(' args? ')')? | [ E ])*
Expression *PRIM2(Parser *p) {
    Expression *lhs = PRIM(p);
    while (p->is({DOT, LBRACKET}) || p->is({QUES}, {DOT, LBRACKET})) {
        bool isOptional = false;
        if (p->is({QUES}, {DOT, LBRACKET})) {
            p->consume(QUES);
            isOptional = true;
        }
        if (p->is(DOT)) {
            p->consume(DOT);
            auto name = p->name();
            if (p->is(LPAREN) || isTypeArg(p, LPAREN)) {
                auto res = new MethodCall;
                res->isOptional = isOptional;
                res->scope = lhs;
                res->name = *name;
                if (p->is(LT)) {
                    res->typeArgs = p->generics();
                }
                p->consume(LPAREN);
                if (!p->is(RPAREN)) {
                    res->args = p->exprList();
                }
                p->consume(RPAREN);
                lhs = res;
            } else {
                auto res = new FieldAccess;
                res->isOptional = isOptional;
                res->scope = lhs;
                res->name = *name;
                lhs = res;
            }
        } else {
            auto res = new ArrayAccess;
            res->isOptional = isOptional;
            res->array = lhs;
            p->consume(LBRACKET);
            res->index = p->parseExpr();
            p->consume(RBRACKET);
            lhs = res;
        }
    }
    if (p->is(BANG)) {
        p->consume(BANG);
        auto res = new UnwrapExpr;
        res->expr = lhs;
        return res;
    }
    return lhs;
}
Expression *parseLhs(Parser *p);

RefExpr *parseRef(Parser *p) {
    p->consume(AND);
    auto expr = parseLhs(p);
    if (dynamic_cast<Name *>(expr) || dynamic_cast<FieldAccess *>(expr) || dynamic_cast<ArrayAccess *>(expr) || dynamic_cast<MethodCall *>(expr) || dynamic_cast<ObjExpr *>(expr)) {
        return new RefExpr(expr);
    }
    throw std::runtime_error("cannot take reference of " + expr->print());
}

DerefExpr *parseDeref(Parser *p) {
    p->consume(STAR);
    auto expr = parseLhs(p);
    if (dynamic_cast<Name *>(expr) ||
        dynamic_cast<FieldAccess *>(expr) ||
        dynamic_cast<MethodCall *>(expr) ||
        dynamic_cast<ParExpr *>(expr) ||
        dynamic_cast<DerefExpr *>(expr)) {
        return new DerefExpr(expr);
    }
    throw std::runtime_error("cannot dereference " + expr->print());
}

Expression *parseLhs(Parser *p) {
    if (p->is(AND)) {
        return parseRef(p);
    } else if (p->is(STAR)) {
        return parseDeref(p);
    }
    return PRIM2(p);
}

//expr ("as" type)?
Expression *asExpr(Parser *p) {
    Expression *lhs = parseLhs(p);
    if (p->is(AS)) {
        auto res = new AsExpr;
        res->expr = lhs;
        p->consume(AS);
        res->type = p->parseType();
        lhs = res;
    }
    return lhs;
}

//expr14 ("++" | "--")* #post
Expression *expr13(Parser *p) {
    Expression *lhs = asExpr(p);
    while (p->is({PLUSPLUS, MINUSMINUS})) {
        auto res = new Postfix;
        res->op = *p->pop()->value;
        res->expr = lhs;
        lhs = res;
    }
    return lhs;
}

//("+" | "-" | "++" | "--" | "!" | "~") expr #unary
Expression *expr12(Parser *p) {
    if (p->is({PLUS, MINUS, PLUSPLUS, MINUSMINUS, BANG, TILDE})) {
        auto res = new Unary;
        res->op = *p->pop()->value;
        res->expr = expr12(p);
        return res;
    } else {
        return expr13(p);
    }
}

//expr12 ("*" | "/" | "%" expr12)*
Expression *expr11(Parser *p) {
    Expression *lhs = expr12(p);
    while (p->is({STAR, DIV, PERCENT})) {
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
    if (p->is(QUES)) {
        auto *t = new Ternary;
        t->cond = lhs;
        p->consume(QUES);
        t->thenExpr = p->parseExpr();
        p->consume(COLON);
        t->elseExpr = expr1(p);
        lhs = t;
    }
    return lhs;
}

bool isAssign(std::string &s) {
    return s == "=" || s == "+=" | s == "-=" | s == "*=" | s == "/=" | s == "%=" | s == "&=" | s == "^=" | s == "|=" | s == "<<=" | s == ">>=" | s == ">>>=";
}

//expr1 (assignOp expr)?
Expression *Parser::parseExpr() {
    log("parseExpr " + *first()->value);
    Expression *res = expr1(this);
    if (isAssign(*first()->value)) {
        auto assign = new Assign;
        assign->left = res;
        assign->op = *pop()->value;
        assign->right = parseExpr();
        res = assign;
    }
    log("expr=" + res->print());
    return res;
}


#pragma clang diagnostic pop