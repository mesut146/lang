#include "Parser.h"
#include "Util.h"


std::unique_ptr<Block> Parser::parseBlock() {
    auto res = std::make_unique<Block>();
    res->line = first()->line;
    consume(LBRACE);
    while (!is(RBRACE)) {
        auto line = first()->line;
        res->list.push_back(parseStmt());
        res->list.back()->line = line;
    }
    consume(RBRACE);
    return res;
}

ArgBind parse_bind(Parser *p) {
    int line = p->first()->line;
    auto name = p->name();
    auto res = ArgBind(name);
    res.line = line;
    res.id = ++Node::last_id;
    if (p->is(STAR)) {
        p->pop();
        res.ptr = true;
    }
    return res;
}

//destructure enum
std::unique_ptr<IfLetStmt> parseIfLet(Parser *p) {
    auto res = std::make_unique<IfLetStmt>();
    p->consume(IF_KW);
    p->consume(LET);
    res->type = p->parseType();
    if (p->is(LPAREN)) {
        p->consume(LPAREN);
        res->args.push_back(parse_bind(p));
        while (p->is(COMMA)) {
            p->consume(COMMA);
            res->args.push_back(parse_bind(p));
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
    if (!p->is(SEMI)) {
        auto var = p->parseVarDeclExpr();
        res->decl.reset(var);
    }
    p->consume(SEMI);
    if (!p->is(SEMI)) {
        res->cond.reset(p->parseExpr());
    }
    p->consume(SEMI);
    if (!p->is(RPAREN)) {
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
    res->line = p->first()->line;
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
    int line = first()->line;
    auto res = parseStmt2();
    res->line = line;
    res->id = ++Node::last_id;
    return res;
}
std::unique_ptr<Statement> Parser::parseStmt2() {
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
        throw std::runtime_error("missing semicolon " + e->print() + " line:" + std::to_string(first()->line));
    }
}
