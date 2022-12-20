#pragma once

#include "Ast.h"
#include "Lexer.h"
#include <cstdarg>
#include <iostream>

class Parser {
public:
    Lexer lexer;
    std::vector<Token *> tokens;
    int pos = 0;
    int mark = 0;
    bool isMarked = false;

    explicit Parser(Lexer &lexer) : lexer(lexer) {
        fill();
    }

    void fill() {
        while (true) {
            Token *t = lexer.next();
            if (t->is(EOF_))
                return;
            if (t->is(COMMENT))
                continue;
            tokens.push_back(t);
        }
    }

    Token *pop() {
        Token *t = tokens[pos];
        pos++;
        return t;
    }

    Token *first() {
        if (tokens.empty() || pos >= tokens.size()) return nullptr;
        return tokens[pos];
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
        return tokens[pos]->is(t1) && tokens[pos + 1]->is(t2);
    }

    Token *consume(TokenType tt) {
        Token *t = pop();
        if (t->is(tt)) return t;
        if (!isMarked) {
        }
        throw std::runtime_error("unexpected token " + t->print() + " on line " + std::to_string(t->line) + " was expecting " + printType(tt));
    }

    void backup() {
        if (isMarked) throw std::runtime_error("already marked");
        isMarked = true;
        mark = pos;
    }

    void restore() {
        if (!isMarked) throw std::runtime_error("not marked");
        pos = mark;
        isMarked = false;
    }

    std::string *name() {
        if(is(FROM)){
            return consume(FROM)->value;
        }
        return consume(IDENT)->value;
    }

    std::string *strLit();

    Unit *parseUnit();

    ImportStmt *parseImport();

    TypeDecl *parseTypeDecl();

    EnumDecl *parseEnumDecl();

    Method *parseMethod();
    bool isMethod();

    Param *parseParam(Method *m);

    VarDecl *parseVarDecl();
    bool isVarDecl();

    VarDeclExpr *parseVarDeclExpr();

    Expression *parseExpr();

    std::vector<Expression *> exprList();

    Type *parseType();
    Type *refType();

    std::vector<Type *> generics();

    Name *qname();

    static bool isPrim(Token &t);

    Statement *parseStmt();

    Block *parseBlock();
};