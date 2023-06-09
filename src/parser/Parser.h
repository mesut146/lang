#pragma once

#include "Ast.h"
#include "Lexer.h"
#include <cstdarg>
#include <iostream>

template<class R>
class Result {
public:
    R result;
    std::exception *err = nullptr;

    R unwrap() {
        if (err) throw *err;
        return result;
    }
};

class Parser {
public:
    Lexer &lexer;
    std::vector<Token> tokens;
    int pos = 0;
    int mark = 0;
    bool isMarked = false;
    Unit *unit;

    explicit Parser(Lexer &lexer) : lexer(lexer) {
        fill();
    }

    void fill() {
        while (true) {
            auto t = lexer.next();
            if (t.is(EOF_))
                return;
            if (t.is(COMMENT))
                continue;
            tokens.push_back(t);
        }
    }

    Token &pop() {
        auto &t = tokens[pos];
        pos++;
        return t;
    }

    Token *first() {
        if (tokens.empty() || pos >= tokens.size()) return nullptr;
        return &tokens[pos];
    }

    bool is(TokenType t) {
        if (first() == nullptr) return false;
        return first()->is(t);
    }

    bool is(std::initializer_list<TokenType> t) {
        if (first() == nullptr) return false;
        return first()->is(t);
    }

    bool is(std::initializer_list<TokenType> t1, std::initializer_list<TokenType> t2) {
        if (first() == nullptr || pos + 1 >= tokens.size()) return false;
        return tokens[pos].is(t1) && tokens[pos + 1].is(t2);
    }

    Result<Token *> consume2(TokenType tt) {
        auto &t = pop();
        if (t.is(tt)) return {&t, nullptr};
        return {nullptr, new std::runtime_error("unexpected token " + t.print() + " on line " + std::to_string(t.line) + " was expecting " + printType(tt))};
    }

    Token &consume(TokenType tt) {
        auto &t = pop();
        if (t.is(tt)) return t;
        throw std::runtime_error(lexer.path + "\nunexpected token " + t.print() + " on line " + std::to_string(t.line) + " was expecting " + printType(tt));
    }

    void backup() {
        if (isMarked) {
            throw std::runtime_error("already marked");
        }
        isMarked = true;
        mark = pos;
    }

    void restore() {
        if (!isMarked) throw std::runtime_error("not marked");
        pos = mark;
        isMarked = false;
    }

    std::string name() {
        if (is({IDENT, FROM, NEW, IS, AS, TYPE})) {
            return pop().value;
        }
        return consume(IDENT).value;
    }

    std::string strLit();

    std::shared_ptr<Unit> parseUnit();

    std::unique_ptr<StructDecl> parseTypeDecl();

    std::unique_ptr<EnumDecl> parseEnumDecl();

    Method parseMethod();
    bool isMethod();

    Param parseParam();

    std::unique_ptr<VarDecl> parseVarDecl();
    bool isVarDecl();

    VarDeclExpr *parseVarDeclExpr();

    Expression *parseExpr();

    std::vector<Expression *> exprList();

    Type parseType();

    std::vector<Type> generics();

    std::vector<Type> type_params();

    static bool isPrim(Token &t);

    std::unique_ptr<Statement> parseStmt();
    std::unique_ptr<Statement> parseStmt2();

    std::unique_ptr<Block> parseBlock();
};