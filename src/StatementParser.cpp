#include "StatementParser.h"
#include "ExprParser.h"
#include "Parser.h"
#include "Token.h"
#include "Util.h"


Block *parseBlock(Parser *p) {
    Block *res = new Block;
    p->consume(LBRACE);
    while (!p->first()->is(RBRACE)) {
        res->list.push_back(parseStmt(p));
    }
    p->consume(RBRACE);
    return res;
}

IfStmt *parseIf(Parser *p) {
    IfStmt *res = new IfStmt;
    p->consume(IF_KW);
    p->consume(LPAREN);
    res->expr = parseExpr(p);
    p->consume(RPAREN);
    res->thenStmt = parseStmt(p);
    if (p->first()->is(ELSE_KW)) {
        p->consume(ELSE_KW);
        res->elseStmt = parseStmt(p);
    }
    return res;
}

Statement *parseFor(Parser *p) {
    log("forstmt");
    p->consume(FOR);
    p->consume(LPAREN);
    VarDecl *var;
    bool simple = true;
    if (isType(p)) {
        var = varDecl(p);
        if (p->first()->is(SEMI)) {
            //simple for
            simple = true;
        } else {
            //foreach
            simple = false;
        }
    }

    if (simple) {
        p->consume(SEMI);
        auto *res = new ForStmt;
        res->decl = var;
        if (!p->first()->is(SEMI)) {
            res->cond = parseExpr(p);
        }
        p->consume(SEMI);
        if (!p->first()->is(RPAREN)) {
            res->updaters = exprList(p);
        }
        p->consume(RPAREN);
        res->body = parseStmt(p);
        return res;
    } else {
        auto *res = new ForEach;
        res->decl = *var;
        p->consume(COLON);
        res->expr = parseExpr(p);
        p->consume(RPAREN);
        res->body = parseStmt(p);
        return res;
    }
}

Param parseParam(Parser *p) {
    Param prm;
    prm.type = parseType(p);
    prm.name = p->name();
    if (p->first()->is(EQ)) {
        p->consume(EQ);
        prm.defVal = parseExpr(p);
    }
    return prm;
}

Method *parseMethod(Parser *p, Type *type, RefType *name) {
    log("parseMethod = " + name->print());
    Method *res = new Method;
    res->type = type;
    res->name = name->print();
    p->consume(LPAREN);
    if (!p->first()->is(RPAREN)) {
        res->params.push_back(parseParam(p));
        while (p->first()->is(COMMA)) {
            p->consume(COMMA);
            res->params.push_back(parseParam(p));
        }
    }
    p->consume(RPAREN);
    if (p->first()->is(SEMI)) {
        p->consume(SEMI);
    } else {
        res->body = parseBlock(p);
    }
    return res;
}

Statement *parseStmt(Parser *p) {
    log("parseStmt " + *p->first()->value);
    p->reset();
    Token t = *p->peek();
    if (t.is(IF_KW)) {
        return parseIf(p);
    } else if (t.is(FOR)) {
        return parseFor(p);
    } else if (t.is(LBRACE)) {
        return parseBlock(p);
    } else if (t.is(RETURN)) {
        auto ret = new ReturnStmt;
        p->consume(RETURN);
        if (!p->first()->is(SEMI)) {
            ret->expr = parseExpr(p);
        }
        p->consume(SEMI);
        return ret;
    } else if (t.is(CONTINUE)) {
        auto ret = new ContinueStmt;
        p->consume(CONTINUE);
        if (!p->first()->is(SEMI)) {
            ret->label = p->name();
        }
        p->consume(SEMI);
        return ret;
    } else if (t.is(BREAK)) {
        auto ret = new BreakStmt;
        p->consume(BREAK);
        if (!p->first()->is(SEMI)) {
            ret->label = p->name();
        }
        p->consume(SEMI);
        return ret;
    } else if (isType(p)) {
        //var decl,method decl
        auto type = parseType(p);
        auto r = refType(p);
        if (p->first()->is({EQ, SEMI})) {
            //var decl
            auto var = varDecl(p, type, r);
            p->consume(SEMI);
            return new ExprStmt(var);
        } else if (p->first()->is(LPAREN)) {
            //method decl
            return parseMethod(p, type, r);
        }
    }
    else if (t.is(IDENT)) {
        Expression *e = parseExpr(p);
        if (p->first()->is(SEMI)) {
            p->consume(SEMI);
            return new ExprStmt(e);
        } else if (p->first()->is({EQ, PLUSEQ, MINUSEQ, ANDEQ, OREQ, LTLTEQ, GTGTEQ})) {
            auto *as = new Assign;
            as->left = e;
            as->op = *p->pop()->value;
            p->consume(SEMI);
            return new ExprStmt(as);
        }
    }
    throw std::string("invalid stmt " + *t.value + " line:" + std::to_string(t.line));
}
