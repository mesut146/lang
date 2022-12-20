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

//destructure enum
IfLetStmt *parseIfLet(Parser *p) {
    auto res = new IfLetStmt;
    p->consume(IF_KW);
    p->consume(LET);
    res->type = p->parseType();
    if (p->is(LPAREN)) {
        p->consume(LPAREN);
        res->args.push_back(*p->name());
        while (p->is(COMMA)) {
            p->consume(COMMA);
            res->args.push_back(*p->name());
        }
        p->consume(RPAREN);
    }
    p->consume(EQ);
    //need lparen to distinguish from objExpr
    p->consume(LPAREN);
    res->rhs = p->parseExpr();
    p->consume(RPAREN);

    res->thenStmt = p->parseBlock();
    if (p->is(ELSE_KW)) {
        p->consume(ELSE_KW);
        res->elseStmt = p->parseStmt();
    }
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

bool isForEach(Parser *p) {
    int pos = p->pos;
    if (p->is({LET, CONST_KW})) pos++;
    if (!p->tokens[pos++]->is(IDENT)) return false;
    return p->tokens[pos]->is(COLON);
}

Statement *parseFor(Parser *p) {
    p->consume(FOR);
    p->consume(LPAREN);
    VarDeclExpr *var;
    bool normalFor;
    if (isForEach(p)) {
        var = new VarDeclExpr;
        if (p->is({LET, CONST_KW})) p->pop();
        auto f = new Fragment;
        f->name = *p->name();
        var->list.push_back(f);
        normalFor = false;
    } else {
        var = p->parseVarDeclExpr();
        normalFor = true;
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


Statement *Parser::parseStmt() {
    log("parseStmt " + *first()->value);
    if (is(IF_KW)) {
        if (is({IF_KW}, {LET})) {
            return parseIfLet(this);
        }
        return parseIf(this);
    } else if (is(FOR)) {
        return parseFor(this);
    } else if (is(WHILE)) {
        return parseWhile(this);
    } else if (is(DO)) {
        return parseDoWhile(this);
    } else if (is(LBRACE)) {
        return parseBlock();
    } else if (is(RETURN)) {
        auto ret = new ReturnStmt;
        consume(RETURN);
        if (!is(SEMI)) {
            ret->expr = parseExpr();
        }
        consume(SEMI);
        return ret;
    } else if (is(CONTINUE)) {
        auto ret = new ContinueStmt;
        consume(CONTINUE);
        if (!is(SEMI)) {
            ret->label = name();
        }
        consume(SEMI);
        return ret;
    } else if (is(BREAK)) {
        auto ret = new BreakStmt;
        consume(BREAK);
        if (!is(SEMI)) {
            ret->label = name();
        }
        consume(SEMI);
        return ret;
    } else if (isVarDecl()) {
        return parseVarDecl();
    } else {
        auto *e = parseExpr();
        if (is(SEMI)) {
            consume(SEMI);
            return new ExprStmt(e);
        }
        throw std::runtime_error("invalid stmt " + e->print() + " line:" + std::to_string(first()->line));
    }
}
