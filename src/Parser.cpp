#include "Parser.h"
#include <iostream>

bool debug = false;

void log(const char *msg) {
  if (debug)
    std::cout << msg << "\n";
}

void log(const std::string &msg) {
  if (debug)
    std::cout << msg << "\n";
}

Type *parseType(Parser &p);
Method parseMethod(Parser &p, Type *type, RefType *name);
VarDecl *varDecl(Parser &p, Type *type, RefType *nm);
VarDecl *varDecl(Parser &p);
std::vector<Expression *> exprList(Parser &p);


bool isLit(Token t) {
  return t.is({FLOAT_LIT, INTEGER_LIT, CHAR_LIT, STRING_LIT, TRUE, FALSE});
}

bool isPrim(Token &t) {
  return t.is({INT, LONG, FLOAT, DOUBLE, CHAR, BYTE});
}

bool isType(Parser &p) {
  Token t = *p.first();
  if (isPrim(t) || t.is({VOID, LET, VAR})) {
    return true;
  }
  if (t.is(IDENT)) {
    return true;
  }
  return false;
}

Literal *parseLit(Parser &p) {
  Literal *res = new Literal;
  Token t = *p.pop();
  res->val = *t.value;
  res->isFloat = t.is(FLOAT_LIT);
  res->isBool = t.is({TRUE, FALSE});
  res->isInt = t.is(INTEGER_LIT);
  res->isStr = t.is(STRING_LIT);
  res->isChar = t.is(CHAR_LIT);
  return res;
}

//simple or  qualified name
Name *qname(Parser &p) {
  auto *s = new SimpleName;
  s->name = p.consume(IDENT)->value;
  if (p.first()->is(DOT)) {
    Name *cur = s;
    while (p.peek()->is(DOT) && p.peek()->is(IDENT)) {
      p.consume(DOT);
      auto *tmp = new QName;
      tmp->scope = cur;
      tmp->name = p.consume(IDENT)->value;
      cur = tmp;
    }
    return cur;
  } else {
    return s;
  }
}

std::vector<Type *> generics(Parser &p) {
  std::vector<Type *> list;
  p.consume(LT);
  list.push_back(parseType(p));
  while (p.first()->is(COMMA)) {
    p.consume(COMMA);
    list.push_back(parseType(p));
  }
  p.consume(GT);
  return list;
}

RefType *refType(Parser &p) {
  auto *res = new RefType;
  res->name = qname(p);
  if (p.first()->is(LT)) {
    res->typeArgs = generics(p);
  }
  return res;
}

Type *parseType(Parser &p) {
  p.reset();
  Token t = *p.first();
  if (isPrim(t) || t.is({VOID, LET, VAR})) {
    p.pop();
    auto *s = new SimpleType;
    s->type = t.value;
    return s;
  } else {
    return refType(p);
  }
}

Block *parseBlock(Parser &p) {
  Block *res = new Block;
  p.consume(LBRACE);
  while (!p.first()->is(RBRACE)) {
    res->list.push_back(p.parseStmt());
  }
  p.consume(RBRACE);
  return res;
}

IfStmt *parseIf(Parser &p) {
  IfStmt *res = new IfStmt;
  p.consume(IF_KW);
  p.consume(LPAREN);
  res->expr = p.parseExpr();
  p.consume(RPAREN);
  res->thenStmt = p.parseStmt();
  if (p.first()->is(ELSE_KW)) {
    p.consume(ELSE_KW);
    res->elseStmt = p.parseStmt();
  }
  return res;
}

Expression *parsePar(Parser &p) {
  auto *res = new ParExpr;
  p.consume(LPAREN);
  res->expr = p.parseExpr();
  p.consume(RPAREN);
  return res;
}

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
  res->name = name();
  log("type decl = " + *res->name);
  if (peek()->is(LT)) {
    res->baseTypes = generics(*this);
  }
  if (first()->is(COLON)) {
    consume(COLON);
    res->baseTypes.push_back(refType(*this));
    while (peek()->is(COMMA)) {
      res->baseTypes.push_back(refType(*this));
    }
  }
  consume(LBRACE);
  //members
  while (!first()->is(RBRACE)) {
    if (isType(*this)) {
      Type *type = parseType(*this);
      RefType *nm = refType(*this);
      if (first()->is(LPAREN)) {
        res->methods.push_back(parseMethod(*this, type, nm));
      } else {
        res->fields.push_back(varDecl(*this, type, nm));
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

bool isOp(std::string &s) {
  return s == "+" || s == "-" || s == "<=";
}

bool isAssign(std::string &s) {
  return s == "=" || s == "+=" || s == "-=";
}

Expression *Parser::parseExpr() {
  log("parseExpr " + *first()->value);
  Token t = *first();
  //parse primary
  Expression *prim;
  if (isLit(t)) {
    prim = parseLit(*this);
  } else if (t.is(IDENT)) {
    Name *name = qname(*this);
    prim = name;
    if (first()->is(DOT)) {
      consume(DOT);
      //method call,field access
    } else if (first()->is(LPAREN)) {
      consume(LPAREN);
      auto call = new MethodCall;
      call->args = exprList(*this);
      call->name = name->print();
      prim = call;
      consume(RPAREN);
    }
  } else if (t.is({PLUSPLUS, MINUSMINUS, PLUS, MINUS, TILDE, BANG})) {
    auto unary = new Unary;
    unary->op = *pop()->value;
    unary->expr = parseExpr();
    prim = unary;
  } else if (t.is(LPAREN)) {
    prim = parsePar(*this);
  }

  else {
    throw std::string("invalid expr " + *t.value);
  }
  //log("prim =" + prim->print());
  if (isOp(*first()->value)) {
    auto infix = new Infix;
    infix->left = prim;
    infix->op = *pop()->value;
    infix->right = parseExpr();
    prim = infix;
  } else if (first()->is({PLUSPLUS, MINUSMINUS})) {
    auto post = new Postfix;
    post->expr = prim;
    post->op = *pop()->value;
    prim = post;
  } else if (isAssign(*first()->value)) {
    auto assign = new Assign;
    assign->left = prim;
    assign->op = *pop()->value;
    assign->right = parseExpr();
    prim = assign;
  }
  log("expr = " + prim->print());
  return prim;
}

Statement *parseFor(Parser &p) {
  log("forstmt");
  p.consume(FOR);
  p.consume(LPAREN);
  VarDecl *var;
  bool simple = true;
  if (isType(p)) {
    var = varDecl(p);
    if (p.first()->is(SEMI)) {
      //simple for
      simple = true;
    } else {
      //foreach
      simple = false;
    }
  }

  if (simple) {
    p.consume(SEMI);
    auto *res = new ForStmt;
    res->decl = var;
    if (!p.first()->is(SEMI)) {
      res->cond = p.parseExpr();
    }
    p.consume(SEMI);
    if (!p.first()->is(RPAREN)) {
      res->updaters = exprList(p);
    }
    p.consume(RPAREN);
    res->body = p.parseStmt();
    return res;
  } else {
    auto *res = new ForEach;
    res->decl = *var;
    p.consume(COLON);
    res->expr = p.parseExpr();
    p.consume(RPAREN);
    res->body = p.parseStmt();
    return res;
  }
}
std::vector<Expression *> exprList(Parser &p) {
  std::vector<Expression *> res;
  res.push_back(p.parseExpr());
  while (p.first()->is(COMMA)) {
    p.consume(COMMA);
    res.push_back(p.parseExpr());
  }
  return res;
}

Statement *Parser::parseStmt() {
  reset();
  log("parseStmt " + *first()->value);
  Token t = *peek();
  if (t.is(IF_KW)) {
    return parseIf(*this);
  } else if (t.is(FOR)) {
    return parseFor(*this);
  } else if (t.is(IDENT)) {
    Expression *e = parseExpr();
    if (first()->is(SEMI)) {
      consume(SEMI);
      return new ExprStmt(e);
    } else if (first()->is({EQ, PLUSEQ, MINUSEQ, ANDEQ, OREQ, LTLTEQ, GTGTEQ})) {
      auto *as = new Assign;
      as->left = e;
      as->op = *pop()->value;
      consume(SEMI);
      return new ExprStmt(as);
    }
  } else if (t.is(LBRACE)) {
    return parseBlock(*this);
  } else if (isType(*this)) {
    //var decl
    auto decl = varDecl(*this);
    consume(SEMI);
    return new ExprStmt(decl);
  } else if (t.is(RETURN)) {
    auto ret = new ReturnStmt;
    consume(RETURN);
    if (!first()->is(SEMI)) {
      ret->expr = parseExpr();
    }
    consume(SEMI);
    return ret;
  } else if (t.is(CONTINUE)) {
    auto ret = new ContinueStmt;
    consume(CONTINUE);
    if (!first()->is(SEMI)) {
      ret->label = name();
    }
    consume(SEMI);
    return ret;
  } else if (t.is(BREAK)) {
    auto ret = new BreakStmt;
    consume(BREAK);
    if (!first()->is(SEMI)) {
      ret->label = name();
    }
    consume(SEMI);
    return ret;
  }
  throw std::string("invalid stmt " + *t.value);
  return nullptr;
}

Param parseParam(Parser &p) {
  Param prm;
  prm.type = parseType(p);
  prm.name = p.name();
  if (p.first()->is(EQ)) {
    p.consume(EQ);
    prm.defVal = p.parseExpr();
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
  res.body = *parseBlock(p);
  return res;
}

VarDecl *varDecl(Parser &p) {
  auto type = parseType(p);
  auto name = refType(p);
  return varDecl(p, type, name);
}

Fragment frag(Parser &p) {
  std::string name = refType(p)->print();
  Expression *right = nullptr;
  if (p.first()->is(EQ)) {
    p.consume(EQ);
    right = p.parseExpr();
  }
  return Fragment(name, right);
}

VarDecl *varDecl(Parser &p, Type *type, RefType *nm) {
  log("varDecl = " + nm->print());
  VarDecl *res = new VarDecl;
  res->type = type;
  Expression *r = nullptr;
  if (p.first()->is(EQ)) {
    p.consume(EQ);
    r = p.parseExpr();
  }
  //first frag
  res->list.push_back(Fragment(nm->print(), r));
  //rest if any
  while (p.first()->is(COMMA)) {
    p.consume(COMMA);
    res->list.push_back(frag(p));
  }
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
      //stmt,method
      if (isType(*this)) {
        Type *type = parseType(*this);
        RefType *nm = refType(*this);
        if (first()->is(LPAREN)) {
          res.methods.push_back(parseMethod(*this, type, nm));
        } else {
          res.stmts.push_back(new ExprStmt(varDecl(*this, type, nm)));
          consume(SEMI);
        }
      } else {
        res.stmts.push_back(parseStmt());
      }
      //throw std::string("unexpected " + *t->value);
    }
  }
  return res;
}
