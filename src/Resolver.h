#pragma once

#include "parser/Ast.h"
#include "BaseVisitor.h"
#include <map>

class RType{
public:
  Unit* unit;
  Type* type;
  TypeDecl* targetDecl;
  Method* targetMethod;
  VarDecl* targetVar;
};

class Resolver : public BaseVisitor<void*, void*>{
public:
     Unit& unit;
     std::map<VarDecl*, RType> varMap;
     std::map<Type*, RType> typeMap;
     std::map<Param*, RType> paramMap;
     std::map<Expression*, RType*> exprMap;
     std::vector<VarDecl*> scope;
     static std::map<Unit*, Resolver> resolverMap;

     Resolver(Unit& unit);
     virtual ~Resolver();
     
     void resolveAll();
     
     RType* resolveType(Type* type);
     RType* resolveVar(VarDecl* vd);
     
     void resolveTypeDecl(TypeDecl* td);
     
     void resolveMethod(Method* m);
     
     RType* resolveScoped(Expression* expr, std::vector<VarDecl*> scope);

     void* visitLiteral(Literal* lit, void* arg) ;
     void* visitInfix(Infix * infix, void* arg);
     void* visitAssign(Assign *as, void* arg);
     void* visitSimpleName(SimpleName *sn, void* arg);
     
};