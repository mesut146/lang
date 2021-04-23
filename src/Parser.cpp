#include "Parser.h"
#include <iostream>

void log(const char* msg){
  std::cout << m << "\n";
}  

ImportStmt Parser::parseImport()
{
  log("parseImport");
  ImportStmt res;
  consume(IMPORT);
  res.s = name();
  Token *t = peek();
  if (t->is(AS))
  {
    consume(AS);
    res.as = name();
  }
  return res;
}

TypeDecl* Parser::parseTypeDecl()
{
  TypeDecl* res = new TypeDecl;
  pop();//class or interface
  res->name = name();
  return res;
}

EnumDecl* Parser::parseEnumDecl()
{
  EnumDecl* res = new EnumDecl;
  consume(ENUM);
  res->name = name();
  return res;
}

Unit Parser::parseUnit()
{
  std::cout<<"unit\n";
  Unit res;
  Token t = *peek();
  if (t.is(IMPORT))
  {
    while (t.is(IMPORT))
    {
      res.imports.push_back(parseImport());
    }
  }
  else if (t.is(CLASS) || t.is(INTERFACE))
  {
    res.types.push_back(parseTypeDecl());
  }
  else if (t.is(ENUM))
  {
    res.types.push_back(parseEnumDecl());
  }
  return res;
}
