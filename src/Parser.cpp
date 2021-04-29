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

//simple or  qualified name
Name* qname(Parser& p){
  SimpleName *s = new SimpleName;
  s->name = p.consume(IDENT)->value;
  if(p.peek()->is(DOT)){
    Name* cur = s;
    while(p.peek()->is(DOT)){
      p.consume(DOT);
      QName *tmp=new QName;
      tmp->scope=cur;
      tmp->name=p.consume(IDENT)->value;
      cur = tmp;
    }
    return cur;
  }
  else{
     return s;
  }
}

bool isPrim(Token& t){
  return t.is({INT,LONG,FLOAT,DOUBLE,CHAR,BYTE});
}

Type *parseType(Parser& p){
  Token t=*p.peek();
  if(isPrim(t) || t.is({VOID,LET,VAR})){
    SimpleType* s=new SimpleType;
    s->type = p.name();
    return s;
  }
  else{
    RefType* res=new RefType;
    res->name = qname(p);
    if(p.peek()->is(LT)){
      p.consume(LT);
      res->typeArgs.push_back(parseType(p));
      while(p.peek()->is(DOT)){
        p.consume(DOT);
        res->typeArgs.push_back(parseType(p));
      }
      p.consume(GT);
    }
    return res;
  }
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
  return res;
}

TypeDecl *Parser::parseTypeDecl()
{
  TypeDecl *res = new TypeDecl;
  pop(); //class or interface
  res->name = name();
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
  return nullptr;
}

Statement* Parser::parseStmt()
{
  Token t = *peek();
  if (t.is(IF_KW))
  {
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

Block parseBlock(Parser& p){
  Block res;
  p.consume(LBRACE);
  while(!p.peek()->is(RBRACE)){
    p.reset();
    res.list.push_back(p.parseStmt());
  }
  p.consume(RBRACE);
  return res;
}

Method parseMethod(Parser& p){
  Method res;
  res.type = parseType(p);
  res.name=p.name();
  p.consume(LPAREN);
  while(1){
    Token t=*p.peek();
    if(t.is(LBRACE)){
      res.body=parseBlock(p);
    }
    else{
      Param prm;
      res.params.push_back(prm);
      prm.type=parseType(p);
      prm.name=p.name();
      t=*p.peek();
      if(t.is(EQ)){
        prm.defVal=p.parseExpr();
      }
    }
  }
  return res;  
}



bool isType(Parser& p){
  Token t=*p.peek();
  if(isPrim(t) || t.is({VOID,LET,VAR})){return true;}
  if(t.is(IDENT)){
    return true;
  }
  return false;
}

Unit Parser::parseUnit()
{
  std::cout << "unit\n";
  Unit res;
  Token t = *peek();

  while (t.is(IMPORT))
  {
    res.imports.push_back(parseImport(*this));
    t = *peek();
  }
  while (1)
  {
    //top level decl
    //type decl or stmt
    reset();
    t = *peek();
    if (t.is(CLASS) || t.is(INTERFACE))
    {
      res.types.push_back(parseTypeDecl());
    }
    else if (t.is(ENUM))
    {
      res.types.push_back(parseEnumDecl());
    }
    else
    {
      //stmt,method
      if(isType(*this)){
        Type *type=parseType(*this);
        
      }
      peek();peek();
      if(peek()->is(LPAREN)){
        res.methods.push_back(parseMethod(*this));
      }
      else{
        reset();
        res.stmts.push_back(parseStmt());
      }
      throw std::string("unexpected " + *t.value);
    }
  }
  return res;
}
