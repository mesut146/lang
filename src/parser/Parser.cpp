#include "Parser.h"
#include "Util.h"

std::string *Parser::strLit() {
    auto t = consume(STRING_LIT);
    return new std::string(t->value->begin() + 1, t->value->end() - 1);
}

//name ("as" name)?;
NamedImport namedImport(Parser *p) {
    NamedImport res;
    res.name = *p->name();
    if (p->is(AS)) {
        p->consume(AS);
        res.as = p->name();
    }
    return res;
}

//"import" importName ("," importName)* "from" STRING_LIT
//"import" "*" ("as" name)? "from" STRING_LIT
ImportStmt Parser::parseImport() {
    log("parseImport");
    ImportStmt res;
    consume(IMPORT);
    if (is(STAR)) {
        consume(STAR);
        res.isStar = true;
        if (is(AS)) {
            consume(AS);
            res.as = name();
        }
    } else {
        res.isStar = false;
        res.namedImports.push_back(namedImport(this));
        while (is(COMMA)) {
            consume(COMMA);
            res.namedImports.push_back(namedImport(this));
        }
    }
    consume(FROM);
    res.from = *strLit();
    return res;
}

//name ":" type ("=" expr)?;
FieldDecl *Parser::parseFieldDecl() {
    auto res = new FieldDecl;
    res->name = *name();
    if (is(QUES)) {
        consume(QUES);
        res->isOptional = true;
    }
    if (is(COLON)) {
        consume(COLON);
        res->type = parseType();
    }
    if (is(EQ)) {
        consume(EQ);
        res->expr = parseExpr();
    }
    consume(SEMI);
    return res;
}

// ("class" | "interface") name typeArgs? (":")? "{" member* "}"
TypeDecl *Parser::parseTypeDecl() {
    auto *res = new TypeDecl;
    res->isInterface = pop()->is(INTERFACE);
    res->name = *name();
    if (is(LT)) {
        res->typeArgs = generics();
    }
    log("type decl = " + res->name);
    if (first()->is(COLON)) {
        consume(COLON);
        res->baseTypes.push_back(refType());
        while (first()->is(COMMA)) {
            res->baseTypes.push_back(refType());
        }
    }
    consume(LBRACE);
    //members
    while (!first()->is(RBRACE)) {
        if (first()->is(CLASS)) {
            res->types.push_back(parseTypeDecl());
        } else if (first()->is(ENUM)) {
            res->types.push_back(parseEnumDecl());
        } else if (first()->is(FUNC)) {
            res->methods.push_back(parseMethod());
        } else if (is(IDENT)) {
            res->fields.push_back(parseFieldDecl());
        } else {
            throw std::string("invalid class member: " + *first()->value);
        }
    }
    consume(RBRACE);
    return res;
}

EnumDecl *Parser::parseEnumDecl() {
    auto *res = new EnumDecl;
    res->isEnum = true;
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
    Unit res;

    while (first() != nullptr && is(IMPORT)) {
        res.imports.push_back(parseImport());
    }

    while (first() != nullptr) {
        //top level decl
        if (is({CLASS, INTERFACE})) {
            res.types.push_back(parseTypeDecl());
        } else if (is(ENUM)) {
            res.types.push_back(parseEnumDecl());
        } else if (is({VAR, LET})) {
            res.stmts.push_back(parseVarDecl());
        } else if (is(FUNC)) {
            res.methods.push_back(parseMethod());
        } else {
            auto stmt = parseStmt();
            res.stmts.push_back(stmt);
        }
    }
    return res;
}

//name "?"? ":" type ("=" expr)?
Param Parser::parseParam(bool requireType, Method* m, ArrowFunction* af) {
    Param res;
    res.method = m;
    res.arrow = af;
    res.name = *name();
    log("param = " + res.name);
    if (is(QUES)) {
        consume(QUES);
        res.isOptional = true;
    }
    if (requireType || is(COLON)) {
        consume(COLON);
        res.type = parseType();
    }

    if (is(EQ)) {
        consume(EQ);
        res.defVal = parseExpr();
    }
    return res;
}

//"func" name "(" params* ")" (":" type)? (block | ";")
Method *Parser::parseMethod() {
    consume(FUNC);
    Method *res = new Method;
    res->name = *name();
    if (is(LT)) {
        res->typeArgs = generics();
    }

    log("parseMethod = " + res->name);
    consume(LPAREN);
    if (!first()->is(RPAREN)) {
        res->params.push_back(parseParam(true, res, nullptr));
        while (first()->is(COMMA)) {
            consume(COMMA);
            res->params.push_back(parseParam(true, res, nullptr));
        }
    }
    consume(RPAREN);
    //can be auto type
    if (is(COLON)) {
        consume(COLON);
        res->type = parseType();
    }
    if (first()->is(SEMI)) {
        //interface
        consume(SEMI);
    } else {
        res->body = parseBlock();
    }
    return res;
}

//name (":" realType)? ("=" expr)?;
Fragment frag(Parser *p) {
    Fragment res;
    res.name = *p->name();
    if (p->is(COLON)) {
        p->consume(COLON);
        res.type = p->parseType();
    }
    if (p->is(EQ)) {
        p->consume(EQ);
        res.rhs = p->parseExpr();
    }
    return res;
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
    auto res = new VarDeclExpr;
    if (is(VAR)) {
        consume(VAR);
        res->isVar = true;
    } else {
        consume(LET);
        res->isVar = false;
    }
    res->list.push_back(frag(this));
    //rest if any
    while (is(COMMA)) {
        consume(COMMA);
        res->list.push_back(frag(this));
    }
    return res;
}