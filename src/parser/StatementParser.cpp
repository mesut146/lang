#include "Parser.h"
#include "Util.h"


std::unique_ptr<Block> Parser::parseBlock() {
    auto res = std::make_unique<Block>();
    consume(LBRACE);
    while (!is(RBRACE)) {
        res->list.push_back(parseStmt());
    }
    consume(RBRACE);
    return res;
}

//destructure enum
std::unique_ptr<IfLetStmt> parseIfLet(Parser *p) {
    auto res = std::make_unique<IfLetStmt>();
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

    res->thenStmt = p->parseBlock();
    if (p->is(ELSE_KW)) {
        p->consume(ELSE_KW);
        res->elseStmt = p->parseStmt();
    }
    return res;
}

std::unique_ptr<IfStmt> parseIf(Parser *p) {
    auto res = std::make_unique<IfStmt>();
    p->consume(IF_KW);
    p->consume(LPAREN);
    res->expr.reset(p->parseExpr());
    p->consume(RPAREN);
    res->thenStmt = p->parseStmt();
    if (p->is(ELSE_KW)) {
        p->consume(ELSE_KW);
        res->elseStmt = p->parseStmt();
    }
    return res;
}

std::unique_ptr<Statement> parseFor(Parser *p) {
    auto res = std::make_unique<ForStmt>();
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
    res->body = p->parseStmt();
    return res;
}

std::unique_ptr<WhileStmt> parseWhile(Parser *p) {
    auto res = std::make_unique<WhileStmt>();
    p->consume(WHILE);
    p->consume(LPAREN);
    res->expr.reset(p->parseExpr());
    p->consume(RPAREN);
    res->body = p->parseBlock();
    return res;
}

std::unique_ptr<DoWhile> parseDoWhile(Parser *p) {
    auto res = std::make_unique<DoWhile>();
    p->consume(DO);
    res->body = p->parseBlock();
    p->consume(WHILE);
    p->consume(LPAREN);
    res->expr.reset(p->parseExpr());
    p->consume(RPAREN);
    p->consume(SEMI);
    return res;
}

std::unique_ptr<Statement> Parser::parseStmt() {
    if (is(ASSERT_KW)) {
        consume(ASSERT_KW);
        auto expr = parseExpr();
        consume(SEMI);
        return std::make_unique<AssertStmt>(expr);
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
        auto ret = std::make_unique<ReturnStmt>();
        consume(RETURN);
        if (!is(SEMI)) {
            ret->expr.reset(parseExpr());
        }
        consume(SEMI);
        return ret;
    } else if (is(CONTINUE)) {
        auto ret = std::make_unique<ContinueStmt>();
        consume(CONTINUE);
        if (!is(SEMI)) {
            ret->label = name();
        }
        consume(SEMI);
        return ret;
    } else if (is(BREAK)) {
        auto ret = std::make_unique<BreakStmt>();
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
            return std::unique_ptr<Statement>(new ExprStmt(e));
        }
        throw std::runtime_error("invalid stmt " + e->print() + " line:" + std::to_string(first()->line));
    }
}
