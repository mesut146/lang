#include "Parser.h"
#include "ExprParser.h"
#include "StatementParser.h"
#include "Util.h"
#include <iostream>


Method parseMethod(Parser &p, Type *type, RefType *name);

ImportStmt parseImport(Parser &p) {
  log("parseImport");
  ImportStmt res{};
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
    if (isType(this)) {
      auto type = parseType(this);
      RefType *nm = refType(this);
      if (first()->is(LPAREN)) {
        res->methods.push_back(parseMethod(*this, type, nm));
      } else {
        res->fields.push_back(varDecl(this, type, nm));
        consume(SEMI);
      }
    } else {
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

MethodCall simpleCall(Parser &p, Expression *scope) {
  MethodCall res;
  return res;
}


Param parseParam(Parser &p) {
  Param prm;
  prm.type = parseType(&p);
  prm.name = p.name();
  if (p.first()->is(EQ)) {
    p.consume(EQ);
    prm.defVal = parseExpr(&p);
  }
  return prm;
}

Method parseMethod(Parser &p, Type *type, RefType *name) {
  Method res;
  res.type = type;
  res.name = name->print();
  log("parseMethod = " + name->print());
  p.consume(LPAREN);
  if (!p.first()->is(RPAREN)) {
    res.params.push_back(parseParam(p));
    while (p.first()->is(COMMA)) {
      p.consume(COMMA);
      res.params.push_back(parseParam(p));
    }
  }
  p.consume(RPAREN);
  res.body = *parseBlock(&p);
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
    } else {
      auto stmt = parseStmt(this);
      if (auto r = dynamic_cast<Method *>(stmt)) {
        res.methods.push_back(*r);
      } else {
        res.stmts.push_back(stmt);
      }
    }
    //throw std::string("unexpected " + *t->value);
  }
  return res;
}
