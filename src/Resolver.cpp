#include "Resolver.h"

Resolver::Resolver(Unit& unit) : unit(unit){}
Resolver::~Resolver() = default;

void normalize(Unit& unit){
  std::vector<Statement*> newList;
  for(Statement* st : unit.stmts){
    auto v = dynamic_cast<VarDecl*>(st);
    if(v == nullptr) continue;
    if(v){
      if(v->list.size() > 1){
      for(Fragment f : v->list){
        VarDecl* vd = new VarDecl;
        vd->isVar = v->isVar;
        vd->list.push_back(f);
        newList.push_back((Statement*)vd);
      }//for
      }//if
      else{
        newList.push_back(st);
      }
    }  
  }  
}

void Resolver::resolveAll(){
  for(BaseDecl* bd : unit.types){
    if(bd->isEnum){
    }else{
      TypeDecl* td = (TypeDecl*)bd;
      resolveTypeDecl(td);
    } 
  }
  for(Method* m : unit.methods){
    resolveMethod(m);
  }
  
  std::vector<VarDecl*> scope;
  for(Statement* st : unit.stmts){
    //scope
    auto v = dynamic_cast<VarDecl*>(st);
    if(v){
      for(Fragment f : v->list){
        if(f.type == nullptr){
        }
        if(f.rhs != nullptr){
          //resolveScoped(f.rhs, scope);
        }
      }  
      scope.push_back(v);
    }  
  }  
  
}  

void Resolver::resolveTypeDecl(TypeDecl* td){}
     
void Resolver::resolveMethod(Method* m){}
     