#pragma once

#include "parser/Ast.h"
#include "BaseVisitor.h"
#include <map>

class RType{
public:
  Unit* unit;
  Type* type;
  TypeDecl* targetType;
  Method* targetMethod;
};

class Resolver : public BaseVisitor<void*, void*>{
public:
     Unit& unit;
     std::map<VarDecl*, RType> varMap;
     std::map<Type*, RType> typeMap;
     std::map<Param*, RType> paramMap;
     static std::map<Unit*, Resolver> resolverMap;

     Resolver(Unit& unit);
     virtual ~Resolver();
     
     void resolveAll();
     
     RType* resolveType(Type* type);
     
     void resolveTypeDecl(TypeDecl* td);
     
     void resolveMethod(Method* m);

     //RType* visitLiteral(Literal* lit, void* arg) ;

     
};