#include "Parser.h"
#include "Util.h"


Block *Parser::parseBlock() {
    auto res = new Block;
    consume(LBRACE);
    while (!is(RBRACE)) {
        res->list.push_back(std::unique_ptr<Statement>(parseStmt()));
    }
    consume(RBRACE);
    return res;
}

//destructure enum
IfLetStmt *parseIfLet(Parser *p) {
    auto res = new IfLetStmt;
    p->consume(IF_KW);
    p->consume(LET);
    res->type.reset(p->parseType());
    if (p->is(LPAREN)) {
        p->consume(LPAREN);
        res->args.push_back(p->name());
        while (p->is(COMMA)) {
            p->consume(COMMA);
            res->args.push_back(p->name());
        }
        p->consume(RPAREN);
    }
    p->consume(EQ);
    //need lparen to distinguish from objExpr
    p->consume(LPAREN);
    res->rhs.reset(p->parseExpr());
    p->consume(RPAREN);

    res->thenStmt.reset(p->parseBlock());
    if (p->is(ELSE_KW)) {
        p->consume(ELSE_KW);
        res->elseStmt.reset(p->parseStmt());
    }
    return res;
}

IfStmt *parseIf(Parser *p) {
    auto res = new IfStmt;
    p->consume(IF_KW);
    p->consume(LPAREN);
    res->expr.reset(p->parseExpr());
    p->consume(RPAREN);
    res->thenStmt.reset(p->parseStmt());
    if (p->is(ELSE_KW)) {
        p->consume(ELSE_KW);
        res->elseStmt.reset(p->parseStmt());
    }
    return res;
}

Statement *parseFor(Parser *p) {
    auto res = new ForStmt;
    p->consume(FOR);
    p->consume(LPAREN);
    auto var = p->parseVarDeclExpr();
    p->consume(SEMI);
    res->decl = var;
    if (!p->first()->is(SEMI)) {
        res->cond.reset(p->parseExpr());
    }
    p->consume(SEMI);
    if (!p->first()->is(RPAREN)) {
        auto list = p->exprList();
        for (auto e : list) {
            res->updaters.push_back(std::unique_ptr<Expression>(e));
        }
    }
    p->consume(RPAREN);
    res->body.reset(p->parseStmt());
    return res;
}

WhileStmt *parseWhile(Parser *p) {
    auto res = new WhileStmt;
    p->consume(WHILE);
    p->consume(LPAREN);
    res->expr.reset(p->parseExpr());
    p->consume(RPAREN);
    res->body.reset(p->parseBlock());
    return res;
}

DoWhile *parseDoWhile(Parser *p) {
    auto res = new DoWhile;
    p->consume(DO);
    res->body.reset(p->parseBlock());
    p->consume(WHILE);
    p->consume(LPAREN);
    res->expr.reset(p->parseExpr());
    p->consume(RPAREN);
    p->consume(SEMI);
    return res;
}

Statement *Parser::parseStmt() {
    if (is(ASSERT_KW)) {
        consume(ASSERT_KW);
        auto expr = parseExpr();
        auto res = new AssertStmt(expr);
        consume(SEMI);
        return res;
    }
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
            ret->expr.reset(parseExpr());
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
        auto e = parseExpr();
        if (is(SEMI)) {
            consume(SEMI);
            return new ExprStmt(e);
        }
        throw std::runtime_error("invalid stmt " + e->print() + " line:" + std::to_string(first()->line));
    }
}
