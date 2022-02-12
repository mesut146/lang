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
  Fragment* targetVar;
};

class Scope{
public:
  std::vector<Fragment*> list;
  
  void add(Fragment* f);
  void clear();
  Fragment* find(std::string& name);
};

class Resolver : public BaseVisitor<void*, void*>{
public:
     Unit& unit;
     std::map<Fragment*, RType*> varMap;
     std::map<Type*, RType*> typeMap;
     std::map<Param*, RType*> paramMap;
     std::map<Method*, RType*> methodMap;//return types
     std::map<FieldDecl*, RType*> fieldMap;
     std::map<Expression*, RType*> exprMap;
     std::vector<Scope*> scopes;
     TypeDecl* curClass = nullptr;
     Method* curMethod = nullptr;
     static std::map<Unit*, Resolver> resolverMap;

     Resolver(Unit& unit);
     virtual ~Resolver();
     
     void dump();
     
     Scope* curScope();
     void dropScope();
     
     void resolveAll();
     
     RType* resolveType(Type* type);
     void resolveVar(VarDecl* vd);
     RType* resolveFrag(Fragment* f);
     
     RType* visitTypeDecl(TypeDecl* td);
     void* visitFieldDecl(FieldDecl* fd, void* arg);
     //void* visitEnumDecl(EnumDecl* ed, void* arg);
     
     void* visitMethod(Method* m, void* arg);
     RType* visitParam(Param& p);
     
     RType* resolveScoped(Expression* expr);

     void* visitLiteral(Literal* lit, void* arg) ;
     void* visitInfix(Infix * infix, void* arg);
     void* visitAssign(Assign *as, void* arg);
     void* visitSimpleName(SimpleName *sn, void* arg);
     void* visitQName(QName *sn, void* arg);
     void* visitMethodCall(MethodCall *mc, void* arg);
     void* visitObjExpr(ObjExpr* o, void* arg);
     
};