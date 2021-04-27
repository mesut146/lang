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

Expression *parseExpr(Parser &p)
{
}

Statement *parseStmt(Parser &p)
{
  Token t = *p.peek();
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
  res.expr = parseExpr(p);
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

Method parseMethod(Parser& p){
  Method res;
  res.type = parseType(p);
  res.name=p.name();
  consume(LPAREN);
  while(1){
    Token t=peek();
    if(t.is(LBRACE)){
      res.body=parseBlock(p);
      break;
    }
    else{
      Param prm;
      res.params.push_back(prm);
      prm.type=parseType(p);
      prm.name=p.name();
      t=*peek();
      if(t.is(EQ)){
        prm.defVal=p.parseExpr();
      }
      else if(t.is(QUES)){
        prm.isDefault=true;
      }
    }
  }
  return res;  
}  

Unit Parser::parseUnit()
{
  std::cout << "unit\n";
  Unit res;
  Token t = *peek();

  while (t.is(IMPORT))
  {
    res.imports.push_back(parseImport());
    t = *peek();
  }
  while (1)
  {
    laPos = 0;
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
      peek();peek();
      if(peek()->is(LPAREN)){
        res.methods.push_back(parseMethod(this));
      }
      else{
        reset();
        res.stmts.push_back(parseStmt(this));
      }
      throw std::string("unexpected " + *t.value);
    }
  }
  return res;
}
