#include "Ast.h"
#include "Visitor.h"

class RType{
public:
  Unit* unit;
  Type* type;
};


RType* resolve(std::string& dir, Expr* expr);

class Resolver : public BaseVisitor<RType*, void*>{


};