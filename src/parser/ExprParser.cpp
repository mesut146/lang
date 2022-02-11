#include "Parser.h"
#include "Util.h"


ArrowFunction *parseArrow(Parser *p);

std::vector<Expression *> Parser::exprList() {
    std::vector<Expression *> res;
    res.push_back(parseExpr());
    while (is(COMMA)) {
        consume(COMMA);
        res.push_back(parseExpr());
    }
    return res;
}

bool isLit(Token &t) {
    return t.is({FLOAT_LIT, INTEGER_LIT, CHAR_LIT, STRING_LIT, TRUE, FALSE});
}

bool Parser::isPrim(Token &t) {
    return t.is({INT, LONG, FLOAT, DOUBLE, CHAR, BYTE, VOID});
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

//name ("." name)*
Name *Parser::qname() {
    auto *res = new SimpleName(*name());
    if (is(DOT)) {
        Name *cur = res;
        while (is(DOT)) {
            consume(DOT);
            auto *tmp = new QName(cur, *name());
            cur = tmp;
        }
        return cur;
    } else {
        return res;
    }
}

Type *Parser::parseType() {
    Type *res;
    if (isPrim(*first())) {
        auto *s = new SimpleType;
        s->type = pop()->value;
        res = s;
    } else {
        res = refType();
    }
    while (is(LBRACKET)) {
        consume(LBRACKET);
        consume(RBRACKET);
        res->arrayLevel++;
    }
    return res;
}

std::vector<Type *> Parser::generics() {
    std::vector<Type *> list;
    consume(LT);
    list.push_back(parseType());
    while (first()->is(COMMA)) {
        consume(COMMA);
        list.push_back(parseType());
    }
    consume(GT);
    return list;
}

//real type,not prim
// qname generics?
RefType *Parser::refType() {
    auto *res = new RefType;
    res->name = qname();
    if (is(LT)) {
        res->typeArgs = generics();
    }
    return res;
}

Entry parseEntry(Parser *p) {
    //todo key not expr,lit,ident
    Entry e;
    e.key = p->parseExpr();
    p->consume(COLON);
    e.value = p->parseExpr();
    return e;
}

Expression *PRIM(Parser *p) {
    //log("parsePrimary " + *p->first()->value);
    if (p->is(LPAREN)) {
        //ParExpr or arrow function
        for (int i = 1; i < p->tokens.size(); i++) {
            if (i < p->tokens.size() - 1 &&
                p->tokens[i]->is(RPAREN) &&
                p->tokens[i + 1]->is(ARROW)) {
                return parseArrow(p);
            }
        }
        auto res = new ParExpr;
        p->consume(LPAREN);
        res->expr = p->parseExpr();
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
                res->args = p->exprList();
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
            auto *res = new SimpleName(*id);
            return res;
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
            res->list = p->exprList();
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
    while (p->is({DOT, LBRACKET}) || p->is(QUES) && p->tokens[1]->is({DOT, LBRACKET})) {
        bool isOptional = false;
        if (p->is(QUES) && p->tokens[1]->is({DOT, LBRACKET})) {
            p->consume(QUES);
            isOptional = true;
        }
        if (p->is(DOT)) {
            p->consume(DOT);
            auto name = p->name();
            if (p->is(LPAREN)) {
                auto res = new MethodCall;
                res->isOptional = isOptional;
                res->scope = lhs;
                res->name = *name;
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
        Ternary *t = new Ternary;
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

//'(' params? ')' => (block | expr)
ArrowFunction *parseArrow(Parser *p) {
    auto res = new ArrowFunction;
    p->consume(LPAREN);
    if (!p->is(RPAREN)) {
        res->params.push_back(p->parseParam(false, nullptr, res));
        while (p->is(COMMA)) {
            p->consume(COMMA);
            res->params.push_back(p->parseParam(false, nullptr, res));
        }
    }
    p->consume(RPAREN);
    p->consume(ARROW);
    if (p->is(LBRACE)) {
        res->block = p->parseBlock();
    } else {
        res->expr = p->parseExpr();
    }
    return res;
}

/*XmlElement *parseXml(Parser *p) {
    auto res = new XmlElement;
    p->consume(LT);
    res->name = *p->name();
    while (p->is(IDENT)) {
        auto key = p->name();
        auto val = p->strLit();
        res->attributes.push_back(std::make_pair(*key, *val));
    }
    if (p->is(DIV)) {
        p->consume(DIV);
        p->consume(GT);
    } else {
        p->consume(GT);
        while (p->is(LT)) {
            res->children.push_back(parseXml(p));
        }
        p->consume(LT);
    }
    return res;
}*/
