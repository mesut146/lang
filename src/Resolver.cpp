#include "Ast.h"
#include "Resolver.h"


Resolver::Resolver(Unit& unit) : unit(unit){}

void Resolver::resolveAll(){
  for(BaseDecl* bd : unit.types){
    if(bd->isEnum){
    }else{
      TypeDecl* td = (TypeDecl*)bd;
      resolveTypeDecl(td);
    } 
  }
  for(Method* m : methods){
    resolveMethod(m);
  }
  
  for(Stmt* st : stmts){
    //scope
  }  
  
}  

     