#include "Parser.h"
#include "Util.h"

std::string *Parser::strLit() {
    auto t = consume(STRING_LIT);
    return new std::string(t->value->begin() + 1, t->value->end() - 1);
}

//name ("as" name)?;
ImportAlias aliased(Parser *p) {
    ImportAlias res;
    res.name = *p->name();
    if (p->is(AS)) {
        p->consume(AS);
        res.as = p->name();
    }
    return res;
}

//"import" importName ("," importName)* "from" STRING_LIT
//"import" "*" ("as" name)? "from" STRING_LIT
ImportStmt *Parser::parseImport() {
    log("parseImport");
    auto res = new ImportStmt;
    consume(IMPORT);
    auto path = qname();
    if (is(LBRACE)) {
        auto sym = new SymbolImport;
        sym->path = path;
        consume(LBRACE);
        sym->entries.push_back(aliased(this));
        while (is(COMMA)) {
            consume(COMMA);
            sym->entries.push_back(aliased(this));
        }
        consume(RBRACE);
        res->sym = sym;
    } else {
        auto normal = new NormalImport;
        normal->path = path;
        if (is(AS)) {
            consume(AS);
            normal->as = name();
        }
        res->normal = normal;
    }
    return res;
}

//type name "?"? ("=" expr)?;
/*FieldDecl *Parser::parseFieldDecl() {
    auto res = new FieldDecl;
    res->type = parseType();
    res->name = *name();
    if (is(QUES)) {
        consume(QUES);
        res->isOptional = true;
    }
    if (is(EQ)) {
        consume(EQ);
        res->expr = parseExpr();
    }
    consume(SEMI);
    return res;
}*/

FieldDecl *parseField(Parser *p) {
    auto res = new FieldDecl;
    res->name = *p->consume(IDENT)->value;
    if (p->is(QUES)) {
        p->consume(QUES);
        res->isOptional = true;
    }
    p->consume(COLON);
    res->type = p->parseType();
    p->consume(SEMI);
    return res;
}

// ("class" | "interface") name typeArgs? (":")? "{" member* "}"
TypeDecl *Parser::parseTypeDecl() {
    auto res = new TypeDecl;
    res->isInterface = pop()->is(INTERFACE);
    res->name = *name();
    if (is(LT)) {
        res->typeArgs = generics();
    }
    log("type decl = " + res->name);
    if (is(COLON)) {
        consume(COLON);
        res->baseTypes.push_back(refType());
        while (is(COMMA)) {
            //interfaces
            res->baseTypes.push_back(refType());
        }
    }
    consume(LBRACE);
    //members
    while (first() != nullptr && !is(RBRACE)) {
        if (is(CLASS)) {
            auto td = parseTypeDecl();
            td->parent = res;
            res->types.push_back(td);
        } else if (is(ENUM)) {
            auto td = parseEnumDecl();
            td->parent = res;
            res->types.push_back(td);
        } else if (is(IDENT)) {
            res->fields.push_back(parseField(this));
        } else if (isMethod()) {
            res->methods.push_back(parseMethod());
        } else {
            throw std::runtime_error("invalid class member: " + first()->print());
        }
    }
    consume(RBRACE);
    return res;
}

EnumEntry *parseEnumEntry(Parser *p) {
    auto res = new EnumEntry;
    res->name = *p->name();
    if (p->is(LPAREN)) {
        p->consume(LPAREN);
        res->params.push_back(p->parseParam(nullptr));
        while (p->is(COMMA)) {
            p->consume(COMMA);
            res->params.push_back(p->parseParam(nullptr));
        }
        p->consume(RPAREN);
    }
    return res;
}

EnumDecl *Parser::parseEnumDecl() {
    auto *res = new EnumDecl;
    res->isEnum = true;
    consume(ENUM);
    res->name = *name();
    log("enum decl = " + res->name);
    if (is(LT)) {
        res->typeArgs = generics();
        consume(GT);
    }
    consume(LBRACE);
    if (!is(RBRACE)) {
        res->cons.push_back(parseEnumEntry(this));
        while (is(COMMA)) {
            consume(COMMA);
            res->cons.push_back(parseEnumEntry(this));
        }
    }
    consume(SEMI);
    while (isMethod()) {
        res->methods.push_back(parseMethod());
    }
    consume(RBRACE);
    return res;
}

bool Parser::isVarDecl() {
    if (is({STATIC}, {LET, CONST_KW})) return true;
    return is({LET, CONST_KW});
}

bool Parser::isMethod() {
    if (is({STATIC}, {FUNC})) return true;
    return is(FUNC);
}

Unit *Parser::parseUnit() {
    auto res = new Unit;

    while (first() != nullptr && is(IMPORT)) {
        res->imports.push_back(parseImport());
    }

    while (first() != nullptr) {
        //top level decl
        if (is({CLASS, INTERFACE})) {
            res->types.push_back(parseTypeDecl());
        } else if (is(ENUM)) {
            res->types.push_back(parseEnumDecl());
        } else if (isVarDecl()) {
            res->stmts.push_back(parseVarDecl());
        } else if (isMethod()) {
            res->methods.push_back(parseMethod());
        } else {
            auto stmt = parseStmt();
            res->stmts.push_back(stmt);
        }
    }
    return res;
}

//type name "?"? ":" type ("=" expr)?
Param *Parser::parseParam(Method *m) {
    auto res = new Param;
    res->method = m;
    res->name = *name();
    log("param = " + res->name);
    if (is(QUES)) {
        consume(QUES);
        res->isOptional = true;
    }
    consume(COLON);
    res->type = parseType();
    if (is(EQ)) {
        consume(EQ);
        res->defVal = parseExpr();
    }
    return res;
}

//(type | void) name generics? "(" params* ")" (block | ";")
Method *Parser::parseMethod() {
    auto *res = new Method;
    if (is(STATIC)) {
        consume(STATIC);
        res->isStatic = true;
    }
    consume(FUNC);
    res->name = *name();
    if (is(LT)) {
        res->typeArgs = generics();
    }

    log("parseMethod = " + res->name);
    consume(LPAREN);
    if (!is(RPAREN)) {
        res->params.push_back(parseParam(res));
        while (is(COMMA)) {
            consume(COMMA);
            res->params.push_back(parseParam(res));
        }
    }
    consume(RPAREN);
    if (is(COLON)) {
        consume(COLON);
        res->type = parseType();
    } else {
        //default is void
        res->type = new Type;
        res->type->name = "void";
    }
    if (is(SEMI)) {
        //interface
        consume(SEMI);
    } else {
        res->body = parseBlock();
    }
    return res;
}

//name (":" type)? ("=" expr)?;
Fragment *frag(Parser *p) {
    auto res = new Fragment;
    res->name = *p->name();
    if (p->is(COLON)) {
        p->consume(COLON);
        res->type = p->parseType();
    }
    if (p->is(EQ)) {
        p->consume(EQ);
        res->rhs = p->parseExpr();
    }
    return res;
}

//("let" | "var") varDeclFrag ("," varDeclFrag)*;
VarDecl *Parser::parseVarDecl() {
    auto res = new VarDecl;
    res->decl = parseVarDeclExpr();
    consume(SEMI);
    return res;
}

//varType varDeclFrag ("," varDeclFrag)*;
VarDeclExpr *Parser::parseVarDeclExpr() {
    auto res = new VarDeclExpr;
    if (is(STATIC)) {
        consume(STATIC);
        res->isStatic = true;
    }
    if (is(CONST_KW)) {
        consume(CONST_KW);
        res->isConst = true;
    } else {
        consume(LET);
    }
    res->list.push_back(frag(this));
    //rest if any
    while (is(COMMA)) {
        consume(COMMA);
        res->list.push_back(frag(this));
    }
    return res;
}