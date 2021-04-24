#include "Parser.h"
#include <iostream>

void log(const char* msg){
  std::cout << msg << "\n";
}

void log(const std::string& msg){
  std::cout << msg << "\n";
}  

ImportStmt Parser::parseImport()
{
  log("parseImport");
  ImportStmt res;
  consume(IMPORT);
  res.file = name();
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

Statement* Parser::parseStmt(){
  
  
}  

Unit Parser::parseUnit()
{
  std::cout<<"unit\n";
  Unit res;
  Token t = *peek();
  
    while (t.is(IMPORT))
    {
      res.imports.push_back(parseImport());
      t=*peek();
    }
  while(1){
    laPos=0;
    t=*peek();
  if (t.is(CLASS) || t.is(INTERFACE))
  {
    res.types.push_back(parseTypeDecl());
  }
  else if (t.is(ENUM))
  {
    res.types.push_back(parseEnumDecl());
  }
  else{
    throw std::string("unexpected " + *t.value);
  }
  }
  return res;
}
