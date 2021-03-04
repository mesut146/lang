#include "Parser.h"

ImportStmt parseImport(){
  	
  }
  
  TypeDecl parseTypeDecl(){}

Unit Parser::parseUnit(){
    Unit res;
    Token t=read();
    if(t.is(IMPORT)){
      while(t.is(IMPORT)){
    	res.imports.push_back(parseImport());
      }
    }
    else if(t.is(CLASS)){
    	res.types.push_back(parseTypeDecl());
    }
    return res;
  }
  
  