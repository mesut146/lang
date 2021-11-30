#include "Parser.h"
#include "ExprParser.h"
#include "StatementParser.h"
#include "Util.h"

Method parseMethod(Parser p);

ImportStmt parseImport(Parser &p) {
    log("parseImport");
    ImportStmt res;
    p.consume(IMPORT);
    res.file = p.name();
    if (p.first()->is(AS)) {
        p.consume(AS);
        res.as = p.name();
    }
    return res;
}

TypeDecl *Parser::parseTypeDecl() {
    auto *res = new TypeDecl;
    res->isInterface = pop()->is(INTERFACE);
    auto name = refType(this);
    res->name = name->name->print();
    res->typeArgs = name->typeArgs;
    log("type decl = " + res->name);
    if (first()->is(COLON)) {
        consume(COLON);
        res->baseTypes.push_back(refType(this));
        while (first()->is(COMMA)) {
            res->baseTypes.push_back(refType(this));
        }
    }
    consume(LBRACE);
    //members
    while (!first()->is(RBRACE)) {
        if (first()->is(CLASS)) {
            res->types.push_back(parseTypeDecl());
        } else if (first()->is(ENUM)) {
            res->types.push_back(parseEnumDecl());
        } else if (first()->is({VAR, LET})) {
            res->fields.push_back(parseVarDecl());
        } else if (first()->is(FN)) {
            res->methods.push_back(parseMethod());
        }
    }
    consume(RBRACE);
    return res;
}

EnumDecl *Parser::parseEnumDecl() {
    auto *res = new EnumDecl;
    consume(ENUM);
    res->name = name();
    log("enum decl = " + *res->name);
    consume(LBRACE);
    if (!first()->is(RBRACE)) {
        res->cons.push_back(*name());
        while (first()->is(COMMA)) {
            consume(COMMA);
            res->cons.push_back(*name());
        }
    }
    consume(RBRACE);
    return res;
}

Unit Parser::parseUnit() {
    log("unit");
    Unit res;

    while (first()->is(IMPORT)) {
        res.imports.push_back(parseImport(*this));
    }

    while (first() != nullptr) {
        //top level decl
        //type decl or stmt
        Token *t = first();
        if (t->is(CLASS) || t->is(INTERFACE)) {
            res.types.push_back(parseTypeDecl());
        } else if (t->is(ENUM)) {
            res.types.push_back(parseEnumDecl());
        } else if (t->is({VAR, LET})) {
            res.stmts.push_back(parseVarDecl());
        } else if (t->is(FN)) {
            res.methods.push_back(parseMethod());
        } else {
            auto stmt = parseStmt(this);
            res.stmts.push_back(stmt);
        }
        //throw std::string("unexpected " + *t->value);
    }
    return res;
}

Param parseParam(Parser *p) {
    Param prm;
    prm.type = parseType(p);
    prm.name = p->name();
    if (p->first()->is(EQ)) {
        p->consume(EQ);
        prm.defVal = parseExpr(p);
    }
    return prm;
}

//"fn" name refType "(" param* ")" ":" type block
Method *Parser::parseMethod() {
    consume(FN);
    Method *res = new Method;
    res->name = *name();
    log("parseMethod = " + res->name);
    consume(LPAREN);
    if (!first()->is(RPAREN)) {
        res->params.push_back(parseParam(this));
        while (first()->is(COMMA)) {
            consume(COMMA);
            res->params.push_back(parseParam(this));
        }
    }
    consume(RPAREN);
    consume(COLON);
    res->type = parseType(this);
    if (first()->is(SEMI)) {
        //interface
        consume(SEMI);
    } else {
        res->body = parseBlock(this);
    }
    return res;
}

//name (":" realType)? ("=" expr)?;
Fragment frag(Parser *p) {
    auto name = p->name();
    log("varDecl frag= " + *name);
    Type *type = nullptr;
    if (p->is(COLON)) {
        p->consume(COLON);
        type = parseType(p);
    }
    Expression *right = nullptr;
    if (p->is(EQ)) {
        p->consume(EQ);
        right = parseExpr(p);
    }
    return Fragment(*name, type, right);
}

//("let" | "var") varDeclFrag ("," varDeclFrag)*;
VarDecl *Parser::parseVarDecl() {
    auto res = new VarDecl;
    auto t = parseVarDeclExpr();
    res->isVar = t->isVar;
    res->list = t->list;
    consume(SEMI);
    return res;
}

//("let" | "var") varDeclFrag ("," varDeclFrag)*;
VarDeclExpr *Parser::parseVarDeclExpr() {
    auto pre = pop();//var or let
    log("varDecl");
    auto res = new VarDeclExpr;
    res->isVar = pre->is(VAR);
    res->list.push_back(frag(this));
    //rest if any
    while (is(COMMA)) {
        consume(COMMA);
        res->list.push_back(frag(this));
    }
    return res;
}