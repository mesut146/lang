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
    std::vector<Token*> backups;
    bool backup = false;

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
        Token *t = tokens[0];
        tokens.erase(tokens.begin());
        if(backup){
          backups.push_back(t);
        }
        return t;
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
    
    void discard(){
      backup = false;
      backups.clear();
    }
    
    void restore(){
      tokens.insert(tokens.begin(), backups.begin(), backups.end());
      discard();
    }

    std::string *name() {
        if (is({VAR, LET})) {
            return pop()->value;
        }
        return consume(IDENT)->value;
    }

    std::string *strLit();

    Unit parseUnit();

    ImportStmt parseImport();

    TypeDecl *parseTypeDecl();

    EnumDecl *parseEnumDecl();

    FieldDecl *parseFieldDecl();

    Method *parseMethod();
    bool isMethod();

    Param parseParam(Method* m);
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