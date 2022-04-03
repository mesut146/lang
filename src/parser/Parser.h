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
    int pos = 0;
    int mark = 0;
    bool isMarked = false;

    Parser(Lexer &lexer) : lexer(lexer) {
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
        if (tokens.size() == 0) return nullptr;
        return tokens[pos];
    }
    
    bool is(TokenType t) {
        return first()->is(t);
    }

    bool is(std::initializer_list<TokenType> t) {
        return first()->is(t);
    }
    
    bool is(std::initializer_list<TokenType> t1, std::initializer_list<TokenType> t2) {
        return tokens[pos]->is(t1) && tokens[pos + 1]->is(t2);
    }

    Token *consume(TokenType tt) {
        Token *t = pop();
        if (t->is(tt)) return t;
        if(!isMarked)
            print_stacktrace();
        throw std::string("unexpected token ") + t->print() + " on line " + std::to_string(t->line) + " was expecting " + std::to_string(tt);
    }
    
    void backup(){
        if(isMarked) throw std::string("alredy marked");
        isMarked = true;
        mark = pos;
    }
    
    void restore(){
        if(!isMarked) throw std::string("not marked");
        pos = mark;
        isMarked = false;
    }    

    std::string *name() {
        if (is({VAR, LET})) {
            return pop()->value;
        }
        return consume(IDENT)->value;
    }

    std::string *strLit();

    Unit* parseUnit();

    ImportStmt parseImport();

    TypeDecl *parseTypeDecl();

    EnumDecl *parseEnumDecl();

    FieldDecl *parseFieldDecl();

    Method *parseMethod();
    bool isMethod();

    Param* parseParam(Method* m);
    Param arrowParam(ArrowFunction* af);

    VarDecl *parseVarDecl();
    bool isVarDecl();

    VarDeclExpr *parseVarDeclExpr();

    Expression *parseExpr();

    std::vector<Expression *> exprList();

    Type *parseType();
    Type* varType();
    Type* refType();

    std::vector<Type *> generics();

    Name *qname();

    bool isPrim(Token &t);

    Statement *parseStmt();

    Block *parseBlock();
};