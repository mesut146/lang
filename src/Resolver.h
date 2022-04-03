#pragma once

#include "parser/Ast.h"
#include "BaseVisitor.h"
#include <map>
#include <memory>

class RType{
public:
  Unit* unit = nullptr;
  Type* type = nullptr;
  BaseDecl* targetDecl = nullptr;
  Method* targetMethod = nullptr;
  Fragment* targetVar = nullptr;
};

class Scope{
public:
  std::vector<Fragment*> list;
  //~Scope();
  void add(Fragment* f);
  void clear();
  Fragment* find(std::string& name);
};

/*class TypeScope{
public:
  std::vector<BaseDecl*> list;
  
  void add(BaseDecl* f);
  void clear();
  Fragment* find(std::string& name);
};*/

class Resolver : public BaseVisitor<void*, void*>{
public:
     Unit* unit;
     std::map<BaseDecl*, RType*> declMap;
     std::map<Fragment*, RType*> varMap;
     std::map<Type*, RType*> typeMap;
     std::map<Param*, RType*> paramMap;
     std::map<Method*, RType*> methodMap;//return types
     //std::map<VarDecl*, RType*> fieldMap;
     std::map<Expression*, RType*> exprMap;
     std::vector<std::shared_ptr<Scope>> scopes;
     BaseDecl* curDecl = nullptr;
     Method* curMethod = nullptr;
     ArrowFunction* arrow = nullptr;
     //static std::map<Unit*, Resolver> resolverMap;

     Resolver(Unit* unit);
     virtual ~Resolver();
     
     void dump();
     
     std::shared_ptr<Scope> curScope();
     void dropScope();
     
     void init();
     void resolveAll();
     
     RType* param(std::string name);
     RType* field(std::string name);
     RType* local(std::string name);
     Method* method(std::string name);
     RType* find(Type* type, BaseDecl* bd);
     RType* resolveType(Type* type);
     void* visitType(Type* type, void* arg);
     void* visitVarDeclExpr(VarDeclExpr* vd, void* arg);
     void* visitVarDecl(VarDecl* vd, void* arg);
     RType* resolveFrag(Fragment* f);
     
     void* visitTypeDecl(TypeDecl* td, void* arg);
     void* visitEnumDecl(EnumDecl* ed, void* arg);
     void* visitBaseDecl(BaseDecl* bd, void* arg);
     RType* visitCommon(BaseDecl* bd);
     
     void* visitMethod(Method* m, void* arg);
     void* visitParam(Param* p, void* arg);
     void* visitArrowFunction(ArrowFunction* af, void* arg);
     
     RType* resolveScoped(Expression* expr);

     void* visitLiteral(Literal* lit, void* arg) ;
     void* visitInfix(Infix * infix, void* arg);
     void* visitAssign(Assign *as, void* arg);
     void* visitSimpleName(SimpleName *sn, void* arg);
     void* visitQName(QName *sn, void* arg);
     void* visitMethodCall(MethodCall *mc, void* arg);
     void* visitObjExpr(ObjExpr* o, void* arg);
     void* visitFieldAccess(FieldAccess* fa, void* arg);
     void* visitArrayCreation(ArrayCreation *ac, void* arg);
     
};