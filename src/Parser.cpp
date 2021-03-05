#include "Parser.h"

ImportStmt Parser::parseImport()
{
  ImportStmt res;
  consume(IMPORT);
  std::string s = next()->value;
  Token* t = next();
  if(t->is(AS)){
  	std::string alias = next()->value;
  }
  return res;
}

TypeDecl Parser::parseTypeDecl() {
  TypeDecl res;
  return res;
}

EnumDecl Parser::parseEnumDecl(){
  EnumDecl res;
  
  return res;
}

Unit Parser::parseUnit()
{
  Unit res;
  Token t = *next();
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
