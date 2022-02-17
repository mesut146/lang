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

// ("class" | "interface") name typeArgs? (":")? "{" member* "}"
TypeDecl *Parser::parseTypeDecl() {
    auto *res = new TypeDecl;
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
    while (!is(RBRACE)) {
        if (is(CLASS)) {
            res->types.push_back(parseTypeDecl());
            (*res->types.end())->parent = res;
        } else if (is(ENUM)) {
            res->types.push_back(parseEnumDecl());
            (*res->types.end())->parent = res;
        }else if (isVarDecl()) {
            restore();
            res->fields.push_back(parseVarDecl());
        } else if (isMethod()) {
            restore();
            res->methods.push_back(parseMethod());
        }else{
            restore();
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
    res->name = *name();
    log("enum decl = " + res->name);
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

bool Parser::isVarDecl(){
  restore();
  backup = true;
  if(is(IDENT) || isPrim(*first()) || is({VAR, LET})){
    parseType();
    if(!is(IDENT)) return false;
    pop();
    if(is({SEMI, EQ, COMMA})) return true;
  }
  return false;
}

bool Parser::isMethod(){
  restore();
  backup = true;
  if(is(VOID)) return true;
  if(is(IDENT) || isPrim(*first())){
    parseType();
    if(!is(IDENT)) return false;
    pop();
    if(is(LT)) generics();
    if(is(LPAREN)) return true;
  }
  return false;
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
        } else if (isVarDecl()) {
            restore();
            res.stmts.push_back(parseVarDecl());
        } else if (isMethod()) {
            restore();
            res.methods.push_back(parseMethod());
        } else {
            restore();
            auto stmt = parseStmt();
            res.stmts.push_back(stmt);
        }
    }
    return res;
}

//type name "?"? ":" type ("=" expr)?
Param Parser::parseParam(Method* m) {
    Param res;
    res.method = m;
    res.type = parseType();
    res.name = *name();
    log("param = " + res.name);
    if (is(QUES)) {
        consume(QUES);
        res.isOptional = true;
    }
    else if (is(EQ)) {
        consume(EQ);
        res.defVal = parseExpr();
    }
    return res;
}

//(type | void) name generics? "(" params* ")" (block | ";")
Method *Parser::parseMethod() {
    Method *res = new Method;
    if(is(VOID)){
      res->type = new Type;
      res->type->name = new SimpleName("void");
    }else{
      res->type = parseType();
    }
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
    if (is(SEMI)) {
        //interface
        consume(SEMI);
    } else {
        res->body = parseBlock();
    }
    return res;
}

//name ("=" expr)?;
Fragment frag(Parser *p) {
    Fragment res;
    res.name = *p->name();
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
    res->type = t->type;
    res->list = t->list;
    consume(SEMI);
    return res;
}

//varType varDeclFrag ("," varDeclFrag)*;
VarDeclExpr *Parser::parseVarDeclExpr() {
    auto res = new VarDeclExpr;
    res->type = varType();
    res->list.push_back(frag(this));
    //rest if any
    while (is(COMMA)) {
        consume(COMMA);
        res->list.push_back(frag(this));
    }
    return res;
}