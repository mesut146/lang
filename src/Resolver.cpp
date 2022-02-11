#include "Resolver.h"
#include <iostream>

Resolver::Resolver(Unit& unit) : unit(unit){}
Resolver::~Resolver() = default;

RType* makeSimple(const std::string& name){
  SimpleType* st = new SimpleType;
  st->type = new std::string(name);
  RType* res = new RType;
  res->type = st;
  return res;
}

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
  
  for(Statement* st : unit.stmts){
    //scope
    auto v = dynamic_cast<VarDecl*>(st);
    if(v){
      for(Fragment f : v->list){
        if(f.type == nullptr){
        }
        if(f.rhs != nullptr){
          resolveScoped(f.rhs, globals);
        }
      }  
      globals.push_back(v);
    }  
  }//for
  
  for(BaseDecl* bd : unit.types){
    if(bd->isEnum){
    }else{
      TypeDecl* td = dynamic_cast<TypeDecl*>(bd);
      resolveTypeDecl(td);
    } 
  }
  for(Method* m : unit.methods){
    visitMethod(m, nullptr);
  }
  
 
  
}

RType* Resolver::resolveScoped(Expression* expr, std::vector<VarDecl*> scope){
  this->scope = scope;
  return (RType*)expr->accept(this, nullptr);
}

void Resolver::resolveTypeDecl(TypeDecl* td){}
     
void* Resolver::visitMethod(Method* m, void* arg){
  RType* res;
  if(m->type != nullptr){
    res = (RType*)m->type->accept(this, m);
  }
  else{
    //infer from return statement
    for(Statement* st:m->body->list){
      auto ret = dynamic_cast<ReturnStmt*>(st);
      if(ret){
        if(ret->expr == nullptr){
          res = makeSimple("void");
        }else{
          res = (RType*)ret->expr->accept(this, ret);
        }
        //todo multiple return compatibility
      }
    }
    if(res == nullptr){
      //no return, so void
      res = makeSimple("void");
    }
  }
  return res;
}

void* Resolver::visitAssign(Assign * as, void* arg){
  RType* t1 = (RType*)as->left->accept(this, as);
  RType* t2 = (RType*)as->right->accept(this, as);
  //return t1 because t2 is going to be autocast to t1 ultimately
  return t1;
}


void* Resolver::visitInfix(Infix * infix, void* arg){
  std::cout << "visitInfix = " << infix->print() << "\n";
  RType* t1 = (RType*)infix->left->accept(this, infix);
  RType* t2 = (RType*)infix->right->accept(this, infix);
  if(t1->type->isVoid() || t2->type->isVoid()){
    throw std::string("operation on void type");
  }
  if(infix->op == "+" && (t1->type->isString() || t2->type->isString())){
    //string concat
    auto res = new RType;
    auto ref = new RefType;
    res->type = ref;
    return res;
  }

  if(t1->type->isPrim()){
    if(t2->type->isPrim()){
      SimpleType* s1 = (SimpleType*)t1->type;
      SimpleType* s2 = (SimpleType*)t2->type;
      if(*s1->type == *s2->type){
        return makeSimple(*s1->type);
      }
      std::string arr[] = {"double", "float", "long", "int", "short", "char", "byte", "bool"};
      if(*s1->type == "double" || *s2->type == "double"){
        return makeSimple("double");
      }
      if(*s1->type == "float" || *s2->type == "float"){
        return makeSimple("float");
      }
      if(*s1->type == "long" || *s2->type == "long"){
        return makeSimple("long");
      }
      if(*s1->type == "int" || *s2->type == "int"){
        return makeSimple("int");
      }
      if(*s1->type == "short" || *s2->type == "short"){
        return makeSimple("short");
      }
      if(*s1->type == "char" || *s2->type == "char"){
        return makeSimple("char");
      }
      if(*s1->type == "byte" || *s2->type == "byte"){
        return makeSimple("byte");
      }
      if(*s1->type == "bool" || *s2->type == "bool"){
        return makeSimple("bool");
      }
    }else{
    }
  }
  else {
    
  }
}

RType* Resolver::resolveType(Type* type){
  RType* res = new RType;
  if(type->isPrim() || type->isVoid()){
    res->type = type;
  }
  else if(type->isString()){
    auto ref = new RefType;
    ref->name = new QName(new SimpleName("core"), "string");
    res->type = ref;
  }else {
    throw std::string("todo resolveType");
  }
  
  return res;
}

RType* Resolver::resolveVar(VarDecl* vd){
  Fragment f = vd->list.at(0);
  if(f.type != nullptr){
    return resolveType(f.type);
  }
  else{
    if(f.rhs == nullptr){
      throw std::string("can not infer var type because rhs is absent");
    }
    return resolveScoped(f.rhs, std::vector<VarDecl*>());//todo scope
  }
}  

void* Resolver::visitSimpleName(SimpleName *sn, void* arg){
  //check for local variable
  for(VarDecl* vd : scope){
    for(Fragment f : vd->list){
      if(f.name == sn->name){
        std::cout << "local var\n";
        RType *res = resolveVar(vd);
        res->targetVar = vd;
        exprMap[sn] = res;
        return res;
      }
    }
  }
  //check for global variable
  for(VarDecl* vd : globals){
    for(Fragment f : vd->list){
      if(f.name == sn->name){
        std::cout << "global var\n";
        RType *res = resolveVar(vd);
        res->targetVar = vd;
        exprMap[sn] = res;
        return res;
      }
    }
  }
  throw std::string("unknown identifier: ") + sn->name;
}

void* Resolver::visitLiteral(Literal *lit, void* arg){
  RType* res = new RType;
  
  if(lit->isStr){
    auto ref = new RefType;
    ref->name = new QName(new SimpleName("core"), "string");
    res->type = ref;
  }else{
    SimpleType* st = new SimpleType;
    res->type = st;
    if(lit->isBool){
      st->type = new std::string("bool");
    }else  if(lit->isFloat){
      st->type = new std::string("float");
    }else  if(lit->isInt){
      st->type = new std::string("int");
    }else  if(lit->isChar){
      st->type == new std::string("char");
    }
  }
  return res;
}

RType* Resolver::visitParam(Param& p){
  if(p.method != nullptr){
    return resolveType(p.type);
  }
  else{
    throw std::string("todo arrow param type");
  }
}

bool isSame(RType* rt1, RType* rt2){
  Type* t1 = rt1->type;
  Type* t2 = rt2->type;
  return t1->print() == t2->print();
}

bool isSame(Resolver* r, MethodCall* mc, Method* m){
  if(mc->name != m->name) return false;
  if(mc->args.size() != m->params.size()) return false;
  for(int i = 0; i < mc->args.size();i++){
    RType* t1 = (RType*)mc->args[i]->accept(r, mc);
    RType* t2 = r->visitParam(m->params[i]);
    if(!isSame(t1, t2)) return false;
  }
  return true;  
}

void* Resolver::visitMethodCall(MethodCall *mc, void* arg){
  if(mc->scope == nullptr){
  if(curClass != nullptr){
    //friend method
    for(Method* m : curClass->methods){
      if(isSame(this, mc, m)){
        auto res = new RType;
        res->targetMethod = m;
        res->targetDecl = curClass;
        return res;
      }
    }//for
    //global method
    for(Method* m: unit.methods){
      if(isSame(this, mc, m)){
        auto res = new RType;
        res->targetMethod = m;
        return res;
      }
    }
  }
  throw std::string("method:  "+ mc->name + " not found");
  }
  else{
    RType* rt = (RType*)mc->scope->accept(this, mc);
    //todo
    throw std::string("method:  "+ mc->name + " not found in type: " + rt->type->print());
  }
}
     