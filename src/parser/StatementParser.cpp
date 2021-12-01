#include "StatementParser.h"
#include "ExprParser.h"
#include "Parser.h"
#include "Token.h"
#include "Util.h"


Block *parseBlock(Parser *p) {
    auto res = new Block;
    p->consume(LBRACE);
    while (!p->first()->is(RBRACE)) {
        res->list.push_back(parseStmt(p));
    }
    p->consume(RBRACE);
    return res;
}

IfStmt *parseIf(Parser *p) {
    auto res = new IfStmt;
    p->consume(IF_KW);
    p->consume(LPAREN);
    res->expr = p->parseExpr();
    p->consume(RPAREN);
    res->thenStmt = parseStmt(p);
    if (p->is(ELSE_KW)) {
        p->consume(ELSE_KW);
        res->elseStmt = parseStmt(p);
    }
    return res;
}

Statement *parseFor(Parser *p) {
    p->consume(FOR);
    p->consume(LPAREN);
    VarDeclExpr *var;
    bool normalFor = true;
    if (p->is({VAR, LET})) {
        var = p->parseVarDeclExpr();
        if (p->is(SEMI)) {
            //simple for
            normalFor = true;
        } else {
            //foreach
            normalFor = false;
        }
    }

    if (normalFor) {
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

WhileStmt *parseWhile(Parser *p) {
    auto res = new WhileStmt;
    p->consume(WHILE);
    p->consume(LPAREN);
    res->expr = p->parseExpr();
    p->consume(RPAREN);
    res->body = parseBlock(p);
    return res;
}

DoWhile *parseDoWhile(Parser *p) {
    auto res = new DoWhile;
    p->consume(DO);
    res->body = parseBlock(p);
    p->consume(WHILE);
    p->consume(LPAREN);
    res->expr = p->parseExpr();
    p->consume(RPAREN);
    p->consume(SEMI);
    return res;
}

CatchStmt parseCatch(Parser *p) {
    CatchStmt res;
    p->consume(CATCH);
    p->consume(LPAREN);
    res.param = p->parseParam();
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
    } else if (t.is(WHILE)) {
        return parseWhile(p);
    } else if (t.is(DO)) {
        return parseDoWhile(p);
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
        return p->parseVarDecl();
    } else {
        Expression *e = p->parseExpr();
        if (p->first()->is(SEMI)) {
            p->consume(SEMI);
            return new ExprStmt(e);
        }
        throw std::string("invalid stmt " + e->print() + " line:" + std::to_string(t.line));
    }
}
