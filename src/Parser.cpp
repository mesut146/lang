#include "Parser.h"
#include <iostream>

void log(const char *msg)
{
  std::cout << msg << "\n";
}

void log(const std::string &msg)
{
  std::cout << msg << "\n";
}

Type *parseType(Parser &p);
Method parseMethod(Parser &p, Type *type, RefType *name);
VarDecl *varDecl(Parser &p, Type *type, RefType *nm);

bool isLit(Token t)
{
  return t.is({FLOAT_LIT, INTEGER_LIT, CHAR_LIT, STRING_LIT, TRUE, FALSE});
}

bool isPrim(Token &t)
{
  return t.is({INT, LONG, FLOAT, DOUBLE, CHAR, BYTE});
}

bool isType(Parser &p)
{
  Token t = *p.peek();
  if (isPrim(t) || t.is({VOID, LET, VAR}))
  {
    return true;
  }
  if (t.is(IDENT))
  {
    return true;
  }
  return false;
}

Literal *parseLit(Parser &p)
{
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
Name *qname(Parser &p)
{
  SimpleName *s = new SimpleName;
  s->name = p.consume(IDENT)->value;
  if (p.peek()->is(DOT))
  {
    Name *cur = s;
    while (p.peek()->is(DOT))
    {
      p.consume(DOT);
      QName *tmp = new QName;
      tmp->scope = cur;
      tmp->name = p.consume(IDENT)->value;
      cur = tmp;
    }
    return cur;
  }
  else
  {
    return s;
  }
}

std::vector<Type *> generics(Parser &p)
{
  p.reset();
  std::vector<Type *> list;
  p.consume(LT);
  list.push_back(parseType(p));
  while (p.peek()->is(COMMA))
  {
    p.consume(COMMA);
    list.push_back(parseType(p));
  }
  p.consume(GT);
  return list;
}

RefType *refType(Parser &p)
{
  p.reset();
  RefType *res = new RefType;
  res->name = qname(p);
  if (p.peek()->is(LT))
  {
    res->typeArgs = generics(p);
  }
  p.reset();
  return res;
}

Type *parseType(Parser &p)
{
  p.reset();
  Token t = *p.peek();
  if (isPrim(t) || t.is({VOID, LET, VAR}))
  {
    p.pop();
    SimpleType *s = new SimpleType;
    s->type = t.value;
    p.reset();
    return s;
  }
  else
  {
    return refType(p);
  }
}

Expression *parsePar(Parser &p)
{
  p.reset();
  ParExpr *res = new ParExpr;
  p.consume(LPAREN);
  res->expr = p.parseExpr();
  p.consume(RPAREN);
  return res;
}

ImportStmt parseImport(Parser &p)
{
  log("parseImport");
  ImportStmt res;
  p.consume(IMPORT);
  res.file = p.name();
  Token *t = p.peek();
  if (t->is(AS))
  {
    p.consume(AS);
    res.as = p.name();
  }
  p.reset();
  return res;
}

TypeDecl *Parser::parseTypeDecl()
{
  TypeDecl *res = new TypeDecl;
  res->isInterface = pop()->is(INTERFACE);
  res->name = name();
  log("type decl " + *res->name);
  if (peek()->is(LT))
  {
    res->baseTypes = generics(*this);
  }
  reset();
  if (peek()->is(COLON))
  {
    consume(COLON);
    res->baseTypes.push_back(refType(*this));
    while (peek()->is(COMMA))
    {
      res->baseTypes.push_back(refType(*this));
    }
  }
  consume(LBRACE);
  //members
  while (!peek()->is(RBRACE))
  {
    reset();
    if (isType(*this))
    {
      Type *type = parseType(*this);
      RefType *nm = refType(*this);
      if (peek()->is(LPAREN))
      {
        res->methods.push_back(parseMethod(*this, type, nm));
      }
      else
      {
        res->fields.push_back(varDecl(*this, type, nm));
        consume(SEMI);
      }
    }
    else
    {
    }
  }
  consume(RBRACE);
  return res;
}

EnumDecl *Parser::parseEnumDecl()
{
  EnumDecl *res = new EnumDecl;
  consume(ENUM);
  res->name = name();
  return res;
}

Expression *Parser::parseExpr()
{
  log("parseExpr");
  Token t = *peek();
  if (isLit(t))
  {
    return parseLit(*this);
  }
  else
  {
    throw std::string("invalid expr " + *t.value);
  }
  return nullptr;
}

Statement *parseFor(Parser &p)
{
  p.consume(FOR);
  Token t = *p.peek();
  if (isType(p))
  {
    Type *type = parseType(p);
  }

  if (t.is(SEMI))
  {
    p.consume(SEMI);
  }
}

Statement *Parser::parseStmt()
{
  reset();
  log("parseStmt");
  Token t = *peek();
  if (t.is(IF_KW))
  {
  }
  else if (t.is(FOR))
  {
    return parseFor(*this);
  }
  return nullptr;
}

IfStmt parseIf(Parser &p)
{
  IfStmt res;
  p.consume(IF_KW);
  p.consume(LPAREN);
  res.expr = p.parseExpr();
  p.consume(RPAREN);
  res.thenStmt = p.parseStmt();
  Token t = *p.peek();
  if (t.is(ELSE_KW))
  {
    p.consume(ELSE_KW);
    res.elseStmt = p.parseStmt();
  }
  else
  {
    p.reset();
  }
  return res;
}

Block parseBlock(Parser &p)
{
  Block res;
  p.consume(LBRACE);
  while (!p.peek()->is(RBRACE))
  {
    res.list.push_back(p.parseStmt());
  }
  p.consume(RBRACE);
  return res;
}

Method parseMethod(Parser &p, Type *type, RefType *name)
{
  Method res;
  res.type = type;
  res.name = name->print();
  p.consume(LPAREN);
  while (1)
  {
    Token t = *p.peek();
    if (t.is(RPAREN))
    {
      p.consume(RPAREN);
      break;
    }
    Param prm;
    res.params.push_back(prm);
    prm.type = parseType(p);
    prm.name = p.name();
    t = *p.peek();
    if (t.is(EQ))
    {
      prm.defVal = p.parseExpr();
    }
  }
  res.body = parseBlock(p);
  return res;
}

VarDecl *varDecl(Parser &p, Type *type, RefType *nm)
{
  VarDecl *res = new VarDecl;
  res->type = type;
  res->name = nm->print();
  log("varDecl " + res->name);
  if (p.peek()->is(EQ))
  {
    p.consume(EQ);
    res->right = p.parseExpr();
  }
  return res;
}

Unit Parser::parseUnit()
{
  log("unit");
  Unit res;
  Token *t = peek();

  while (t->is(IMPORT))
  {
    res.imports.push_back(parseImport(*this));
    t = peek();
  }
  while (1)
  {
    //top level decl
    //type decl or stmt
    reset();
    t = peek();
    if (t == nullptr)
      break;
    if (t->is(CLASS) || t->is(INTERFACE))
    {
      res.types.push_back(parseTypeDecl());
    }
    else if (t->is(ENUM))
    {
      res.types.push_back(parseEnumDecl());
    }
    else
    {
      //stmt,method
      if (isType(*this))
      {
        Type *type = parseType(*this);
        RefType *nm = refType(*this);
        reset();
        if (peek()->is(LPAREN))
        {
          res.methods.push_back(parseMethod(*this, type, nm));
        }
        else
        {
          reset();
          ExprStmt *e = new ExprStmt;
          e->expr = varDecl(*this, type, nm);
          consume(SEMI);
          res.stmts.push_back(e);
        }
      }
      else
      {
        reset();
        res.stmts.push_back(parseStmt());
      }
      //throw std::string("unexpected " + *t->value);
    }
  }
  return res;
}
