#pragma once

#include "parser/Ast.h"
#include "BaseVisitor.h"
#include <map>
#include <memory>

class Symbol;
class RType;
class Resolver;

class Symbol{
public:
    Method* m = nullptr;
    Fragment* f = nullptr;
    Param* prm = nullptr;
    BaseDecl* decl = nullptr;
    ImportStmt* imp = nullptr;
    Resolver* resolver;
    
    Symbol(Method* m, Resolver* r): m(m), resolver(r){}
    Symbol(Fragment* f, Resolver* r): f(f), resolver(r){}
    Symbol(Param* prm, Resolver* r): prm(prm), resolver(r){}
    Symbol(BaseDecl* bd, Resolver* r): decl(bd), resolver(r){}
    Symbol(ImportStmt* imp, Resolver* r): imp(imp), resolver(r){}
    
    template <class T>
    RType* resolve(T e){ e->accept(resolver, nullptr); }
};

class RType{
public:
  Unit* unit = nullptr;
  Type* type = nullptr;
  BaseDecl* targetDecl = nullptr;
  Method* targetMethod = nullptr;
  Fragment* targetVar = nullptr;
  bool isImport = false;
  std::vector<Symbol> arr;
  
  RType(){}
  RType(Type* t): type(t){}
};

class Scope{
public:
  std::vector<Fragment*> list;
  //~Scope();
  void add(Fragment* f);
  void clear();
  Fragment* find(std::string& name);
};

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
     bool fromOther = false;
     static std::map<std::string, Resolver*> resolverMap;
     static std::string root;

     Resolver(Unit* unit);
     virtual ~Resolver();
     
     static Resolver* getResolver(std::string path);
     void other(std::string name, std::vector<Symbol> &res);
     std::vector<Symbol> find(std::string& name, bool checkOthers);
     
     void dump();
     
     std::shared_ptr<Scope> curScope();
     void dropScope();
     
     void init();
     void resolveAll();
     
     void param(std::string name, std::vector<Symbol> &res);
     void field(std::string name, std::vector<Symbol> &res);
     void local(std::string name, std::vector<Symbol> &res);
     void method(std::string name, std::vector<Symbol> &res);
     RType* find(Type* type, BaseDecl* bd);
     
     RType* resolveType(Type* type);
     void* visitType(Type* type, void* arg);
     void* visitVarDeclExpr(VarDeclExpr* vd, void* arg);
     void* visitVarDecl(VarDecl* vd, void* arg);
     void* visitFragment(Fragment* f, void* arg);
     
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
     void* visitAsExpr(AsExpr* as, void* arg);
     
};