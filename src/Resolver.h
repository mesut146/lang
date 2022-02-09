#include "Ast.h"
#include "Visitor.h"

class RType{
public:
  Unit* unit;
  Type* type;
  TypeDecl* targetType;
};

class Resolver : public BaseVisitor<RType*, void*>{
public:
     Unit& unit;
     std::map<VarDecl*, RType> varMap;
     std::map<Type*, RType> typeMap;
     std::map<Param*, RType> paramMap;
     static std::map<Unit*, Resolver> resolverMap;

     Resolver(Unit& unit);
     
     void resolveAll();
     
     RType* resolveType(Type* type);
     
     void resolveTypeDecl(TypeDecl* td);
     
     void resolveMethod(Merhod* m);

     RType* visitLiteral(Literal* lit, void* arg) ;

     
};