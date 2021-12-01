#pragma once

#include "Ast.h"
#include "Lexer.h"
#include "stacktrace.h"
#include <cstdarg>
#include <iostream>

class Parser {
public:
    Lexer lexer;
    std::vector<Token *> tokens;
    int laPos = 0;
    int line;

    Parser(Lexer &lexer) : lexer(lexer) {
        fill();
    }

    void reset() {
        laPos = 0;
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
        reset();
        Token *t = tokens[0];
        tokens.erase(tokens.begin());
        return t;
    }

    //read a token without consuming
    Token *peek() {
        if (tokens.size() == 0) return nullptr;
        return tokens[laPos++];
    }

    Token *first() {
        if (tokens.size() == 0) return nullptr;
        return tokens[0];
    }
    bool is(TokenType t) {
        return first()->is(t);
    }

    bool is(std::initializer_list<TokenType> t) {
        return first()->is(t);
    }


    Token *consume(TokenType tt) {
        Token *t = pop();
        if (t->is(tt)) return t;
        print_stacktrace();
        throw std::string("unexpected token ") + t->print() + " on line " + std::to_string(t->line) + " was expecting " + std::to_string(tt);
    }

    std::string *name() {
        if (is({VAR, LET, FUNC})) {
            return pop()->value;
        }
        return consume(IDENT)->value;
    }

    Unit parseUnit();

    TypeDecl *parseTypeDecl();

    EnumDecl *parseEnumDecl();

    FieldDecl *parseFieldDecl();

    Method *parseMethod();

    Param parseParam();

    VarDecl *parseVarDecl();

    VarDeclExpr *parseVarDeclExpr();

    Expression *parseExpr();

    Type *parseType();

    std::vector<Type *> generics();

    RefType *refType();

    Name *qname();

    bool isPrim(Token &t);
};