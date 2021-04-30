#include "Parser.h"
#include <iostream>

void log(const char *msg) {
  std::cout << msg << "\n";
}

void log(const std::string &msg) {
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
  p.reset();
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
  p.reset();
  std::vector<Type *> list;
  p.consume(LT);
  list.push_back(parseType(p));
  while (p.peek()->is(COMMA)) {
    p.consume(COMMA);
    list.push_back(parseType(p));
  }
  p.consume(GT);
  return list;
}

RefType *refType(Parser &p) {
  p.reset();
  auto *res = new RefType;
  res->name = qname(p);
  if (p.peek()->is(LT)) {
    res->typeArgs = generics(p);
  }
  p.reset();
  return res;
}

Type *parseType(Parser &p) {
  p.reset();
  Token t = *p.peek();
  if (isPrim(t) || t.is({VOID, LET, VAR})) {
    p.pop();
    auto *s = new SimpleType;
    s->type = t.value;
    p.reset();
    return s;
  } else {
    return refType(p);
  }
}

Block* parseBlock(Parser &p) {
  Block* res=new Block;
  p.consume(LBRACE);
  while (!p.first()->is(RBRACE)) {
    res->list.push_back(p.parseStmt());
  }
  p.consume(RBRACE);
  return res;
}

Expression *parsePar(Parser &p) {
  p.reset();
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
  Token *t = p.peek();
  if (t->is(AS)) {
    p.consume(AS);
    res.as = p.name();
  }
  p.reset();
  return res;
}

TypeDecl *Parser::parseTypeDecl() {
  auto *res = new TypeDecl;
  res->isInterface = pop()->is(INTERFACE);
  res->name = name();
  log("type decl " + *res->name);
  if (peek()->is(LT)) {
    res->baseTypes = generics(*this);
  }
  reset();
  if (peek()->is(COLON)) {
    consume(COLON);
    res->baseTypes.push_back(refType(*this));
    while (peek()->is(COMMA)) {
      res->baseTypes.push_back(refType(*this));
    }
  }
  consume(LBRACE);
  //members
  while (!peek()->is(RBRACE)) {
    reset();
    if (isType(*this)) {
      Type *type = parseType(*this);
      RefType *nm = refType(*this);
      if (peek()->is(LPAREN)) {
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
  log("enum decl=" + *res->name);
  consume(LBRACE);
  if(!first()->is(RBRACE)){
    res->cons.push_back(*name());
    while(first()->is(COMMA)){
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
  return s == "+" || s == "-" || s=="<=";
}

bool isAssign(std::string &s) {
  return s == "=" || s == "+=" || s == "-=";
}

Expression *Parser::parseExpr() {
  reset();
  log("parseExpr " + *first()->value);
  Token t = *peek();
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
      auto *call = new MethodCall;
      call->args = exprList(*this);
      call->name = name->print();
      prim = call;
      consume(RPAREN);
    }
  } else if(t.is({PLUSPLUS,MINUSMINUS,PLUS,MINUS,TILDE,BANG})){
      auto* p=new Unary;
      p->op=*pop()->value;
      p->expr=parseExpr();
    }

  else {
    throw std::string("invalid expr " + *t.value);
  }
  log("prim ="+prim->print());
  if (isOp(*first()->value)) {
    Infix *infix = new Infix;
    infix->left = prim;
    infix->op = *pop()->value;
    infix->right = parseExpr();
    prim = infix;
  }
  else if(first()->is({PLUSPLUS, MINUSMINUS})){
    auto* post = new Postfix;
    post->expr = prim;
    post->op = *pop()->value;
    prim = post;
  }else if(isAssign(*first()->value)){
    auto* a=new Assign;
    a->left = prim;
    a->op = *pop()->value;
    a->right = parseExpr();
    prim = a;
  }
  log("expr="+prim->print());
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
  }
  else if (t.is(FOR)) {
    return parseFor(*this);
  }
  else if(t.is(IDENT)){
    Expression* e = parseExpr();
    if(first()->is(SEMI)){
      consume(SEMI);
      return new ExprStmt(e);
    }
    else if(first()->is({EQ,PLUSEQ,MINUSEQ,ANDEQ,OREQ,LTLTEQ,GTGTEQ})){
      auto* as=new Assign;
      as->left = e;
      as->op = *pop()->value;
      consume(SEMI);
      return new ExprStmt(as);
    }
  }
  else if(t.is(LBRACE)){
    return parseBlock(*this);
  }
  throw std::string("invalid stmt "+*t.value);
  return nullptr;
}

IfStmt parseIf(Parser &p) {
  IfStmt res;
  p.consume(IF_KW);
  p.consume(LPAREN);
  res.expr = p.parseExpr();
  p.consume(RPAREN);
  res.thenStmt = p.parseStmt();
  Token t = *p.peek();
  if (t.is(ELSE_KW)) {
    p.consume(ELSE_KW);
    res.elseStmt = p.parseStmt();
  } else {
    p.reset();
  }
  return res;
}

Param parseParam(Parser& p){
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
  p.consume(LPAREN);
  if (!p.first()->is(RPAREN)) {
    res.params.push_back(parseParam(p));
    while(p.first()->is(COMMA)){
      p.consume(COMMA);
      res.params.push_back(parseParam(p));
    }
  }
  p.consume(RPAREN);
  res.body = *parseBlock(p);
  return res;
}

VarDecl *varDecl(Parser &p) {
  VarDecl *res = new VarDecl;
  res->type = parseType(p);
  res->name = refType(p)->print();
  log("varDecl " + res->name);
  if (p.peek()->is(EQ)) {
    p.consume(EQ);
    res->right = p.parseExpr();
  }
  return res;
}
VarDecl *varDecl(Parser &p, Type *type, RefType *nm) {
  VarDecl *res = new VarDecl;
  res->type = type;
  res->name = nm->print();
  log("varDecl " + res->name);
  if (p.first()->is(EQ)) {
    p.consume(EQ);
    res->right = p.parseExpr();
  }
  return res;
}

Unit Parser::parseUnit() {
  log("unit");
  Unit res;

  while (first()->is(IMPORT)) {
    res.imports.push_back(parseImport(*this));
  }
  
  while (first()!=nullptr) {
    //top level decl
    //type decl or stmt
    reset();
    Token *t = peek();
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
          res.stmts.push_back(new ExprStmt(varDecl(*this,type,nm)));
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
