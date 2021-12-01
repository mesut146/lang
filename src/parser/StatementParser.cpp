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
    res->expr = p->parseExpr();
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
    VarDeclExpr *var;
    bool simple = true;
    if (isType(p)) {
        var = p->parseVarDeclExpr();
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
        auto res = new ForStmt;
        res->decl = var;
        if (!p->first()->is(SEMI)) {
            res->cond = p->parseExpr();
        }
        p->consume(SEMI);
        if (!p->first()->is(RPAREN)) {
            res->updaters = exprList(p);
        }
        p->consume(RPAREN);
        res->body = parseStmt(p);
        return res;
    } else {
        auto res = new ForEach;
        res->decl = var;
        p->consume(COLON);
        res->expr = p->parseExpr();
        p->consume(RPAREN);
        res->body = parseStmt(p);
        return res;
    }
}

CatchStmt parseCatch(Parser *p) {
    CatchStmt res;
    p->consume(CATCH);
    p->consume(LPAREN);

    p->consume(RPAREN);
    res.block = parseBlock(p);
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
            ret->expr = p->parseExpr();
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
    } else if (t.is(TRY)) {
        auto res = new TryStmt;
        p->consume(TRY);
        res->block = parseBlock(p);
        while (p->is(CATCH)) {
            res->catches.push_back(parseCatch(p));
        }
        return res;
    } else if (t.is(THROW)) {
        auto res = new ThrowStmt;
        p->consume(THROW);
        res->expr = p->parseExpr();
        p->consume(SEMI);
        return res;
    } else if (t.is({VAR, LET})) {
        //var decl
        auto var = p->parseVarDecl();
        return var;
    } else {
        Expression *e = p->parseExpr();
        if (p->first()->is(SEMI)) {
            p->consume(SEMI);
            return new ExprStmt(e);
        }
        throw std::string("invalid stmt " + e->print() + " line:" + std::to_string(t.line));
    }
    throw std::string("invalid stmt " + *t.value + " line:" + std::to_string(t.line));
}
