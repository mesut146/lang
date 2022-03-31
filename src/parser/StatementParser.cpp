#include "Parser.h"
#include "Util.h"


Block *Parser::parseBlock() {
    auto res = new Block;
    consume(LBRACE);
    while (!is(RBRACE)) {
        res->list.push_back(parseStmt());
    }
    consume(RBRACE);
    return res;
}

IfStmt *parseIf(Parser *p) {
    auto res = new IfStmt;
    p->consume(IF_KW);
    p->consume(LPAREN);
    res->expr = p->parseExpr();
    p->consume(RPAREN);
    res->thenStmt = p->parseStmt();
    if (p->is(ELSE_KW)) {
        p->consume(ELSE_KW);
        res->elseStmt = p->parseStmt();
    }
    return res;
}

Statement *parseFor(Parser *p) {
    p->consume(FOR);
    p->consume(LPAREN);
    VarDeclExpr *var;
    bool normalFor = true;
    if (p->is({VAR, LET, CONST_KW})) {
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
            res->updaters = p->exprList();
        }
        p->consume(RPAREN);
        res->body = p->parseStmt();
        return res;
    } else {
        auto res = new ForEach;
        res->decl = var;
        p->consume(COLON);
        res->expr = p->parseExpr();
        p->consume(RPAREN);
        res->body = p->parseStmt();
        return res;
    }
}

WhileStmt *parseWhile(Parser *p) {
    auto res = new WhileStmt;
    p->consume(WHILE);
    p->consume(LPAREN);
    res->expr = p->parseExpr();
    p->consume(RPAREN);
    res->body = p->parseBlock();
    return res;
}

DoWhile *parseDoWhile(Parser *p) {
    auto res = new DoWhile;
    p->consume(DO);
    res->body = p->parseBlock();
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
    Param prm;
    prm.type = p->refType();
    prm.name = *p->name();
    res.param = prm;
    p->consume(RPAREN);
    res.block =  p->parseBlock();
    return res;
}


Statement *Parser::parseStmt() {
    log("parseStmt " + *first()->value);
    Token t = *first();
    if (t.is(IF_KW)) {
        return parseIf(this);
    } else if (t.is(FOR)) {
        return parseFor(this);
    } else if (t.is(WHILE)) {
        return parseWhile(this);
    } else if (t.is(DO)) {
        return parseDoWhile(this);
    } else if (t.is(LBRACE)) {
        return parseBlock();
    } else if (t.is(RETURN)) {
        auto ret = new ReturnStmt;
        consume(RETURN);
        if (!is(SEMI)) {
            ret->expr = parseExpr();
        }
        consume(SEMI);
        return ret;
    } else if (t.is(CONTINUE)) {
        auto ret = new ContinueStmt;
        consume(CONTINUE);
        if (!is(SEMI)) {
            ret->label = name();
        }
        consume(SEMI);
        return ret;
    } else if (t.is(BREAK)) {
        auto ret = new BreakStmt;
        consume(BREAK);
        if (!first()->is(SEMI)) {
            ret->label = name();
        }
        consume(SEMI);
        return ret;
    } else if (t.is(TRY)) {
        auto res = new TryStmt;
        consume(TRY);
        res->block = parseBlock();
        while (is(CATCH)) {
            res->catches.push_back(parseCatch(this));
        }
        return res;
    } else if (t.is(THROW)) {
        auto res = new ThrowStmt;
        consume(THROW);
        res->expr = parseExpr();
        consume(SEMI);
        return res;
    } else if (t.is({VAR, LET, CONST_KW})) {
        return parseVarDecl();
    } else {
        Expression *e = parseExpr();
        if (is(SEMI)) {
            consume(SEMI);
            return new ExprStmt(e);
        }
        throw std::string("invalid stmt " + e->print() + " line:" + std::to_string(t.line));
    }
}
