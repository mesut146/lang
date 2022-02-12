#include "Resolver.h"
#include <iostream>

void Scope::add(Fragment* f){
  list.push_back(f);
}
void Scope::clear(){
  list.clear();
}
Fragment* Scope::find(std::string& name){
  for(Fragment* f : list){
    if(f->name == name) return f;
  }
  return nullptr;
}



Resolver::Resolver(Unit& unit) : unit(unit){}
Resolver::~Resolver(){
  
}

RType* makeSimple(const std::string& name){
  SimpleType* st = new SimpleType;
  st->type = new std::string(name);
  RType* res = new RType;
  res->type = st;
  return res;
}

void normalize(Unit& unit){
  
}

void Resolver::dump(){
  for(auto &p : varMap){
    std::cout << "var: " << p.first->name << " = " << p.second->type->print() << "\n";
  }
  for(auto &p : fieldMap){
    std::cout << "field: " << p.first->name << " = " << p.second->type->print() << "\n";
  }
  for(auto& p:methodMap){
    std::cout << "method: " << p.first->name << " = " << p.second->type->print() << "\n";
    for(Param& prm:p.first->params){
      std::cout << "param: " << prm.name << " = " <<  paramMap[&prm]->type->print() << "\n";
    }
  }
}

void Resolver::dropScope(){
  curScope()->clear();
  scopes.erase(scopes.end());
}

Scope* Resolver::curScope(){
  return scopes[scopes.size() - 1];
}

void Resolver::resolveAll(){
  scopes.push_back(new Scope);
  for(Statement* st : unit.stmts){
    auto vd = dynamic_cast<VarDecl*>(st);
    if(vd){
      resolveVar(vd);
    }
    else{
      st->accept(this, nullptr);
    }
  }//for
  
  for(BaseDecl* bd : unit.types){
    if(bd->isEnum){
    }else{
      TypeDecl* td = dynamic_cast<TypeDecl*>(bd);
      visitTypeDecl(td);
    } 
  }
  for(Method* m : unit.methods){
    visitMethod(m, nullptr);
  }
  
 dump();
}

RType* Resolver::resolveScoped(Expression* expr){
  return (RType*)expr->accept(this, nullptr);
}

RType* Resolver::visitTypeDecl(TypeDecl* td){
  auto res = new RType;
  res->targetDecl = td;
  if(td->parent != nullptr){
    auto pt = visitTypeDecl(dynamic_cast<TypeDecl*>(td->parent));
    //auto qn = new QName();
    auto qt = new RefType;
    //qt->name = qn;
    //res->type = 
  }else{
    res = makeSimple(td->name);
    res->unit = &unit;
  }
  for(FieldDecl* fd : td->fields){
    visitFieldDecl(fd, td);
  }
  for(Method* m : td->methods){
    visitMethod(m, td);
  }
  for(BaseDecl* bd : td->types){
    bd->accept(this, td);
  }
  return res;
}
     
void* Resolver::visitMethod(Method* m, void* arg){
  curMethod = m;
  RType* res =nullptr;
  
  for(Param& prm:m->params){
    visitParam(prm);
  }  
  
  if(m->type != nullptr){
    res = (RType*)m->type->accept(this, m);
  }
  scopes.push_back(new Scope);
  for(Statement* st:m->body->list){
      auto ret = dynamic_cast<ReturnStmt*>(st);
      if(ret){
        RType* tmp;
        if(ret->expr == nullptr){
          tmp = makeSimple("void");
        }else{
          tmp = resolveScoped(ret->expr);
        }
        if(res == nullptr){
          res = tmp;
        }
      }
      else{
        st->accept(this, nullptr);
      }
        //todo multiple return compatibility
    }//for
    if(res == nullptr){
      //no return, so void
      res = makeSimple("void");
    }
  methodMap[m] = res;
  dropScope();
  curMethod = nullptr;
  return res;
}

RType* Resolver::visitParam(Param& p){
  if(p.method != nullptr){
    auto res =  resolveType(p.type);
    paramMap[&p] = res;
    return res;
  }
  else{
    throw std::string("todo arrow param type");
  }
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
  else if(type->isString() || type->print() == "string"){
    auto ref = new RefType;
    ref->name = new QName(new SimpleName("core"), "string");
    res->type = ref;
  }else {
    throw std::string("todo resolveType: " + type->print());
  }
  return res;
}

void* Resolver::visitFieldDecl(FieldDecl* fd, void* arg){
  RType* res;
  if(fd->type != nullptr){
    res = resolveType(fd->type);
  }
  else{
    if(fd->expr == nullptr){
      throw std::string("can not infer field type because rhs is absent");
    }
    res = resolveScoped(fd->expr);
  }
  fieldMap[fd] = res;
  //curScope()->add(f);
}

RType* Resolver::resolveFrag(Fragment* f){
  RType* res;
  if(f->type != nullptr){
    res = resolveType(f->type);
  }
  else{
    if(f->rhs == nullptr){
      throw std::string("can not infer var type because rhs is absent");
    }
    res = resolveScoped(f->rhs);
  }
  varMap[f] = res;
  curScope()->add(f);
}

void Resolver::resolveVar(VarDecl* vd){
  for(Fragment &f : vd->list){
    resolveFrag(&f);
  }
}  

void* Resolver::visitSimpleName(SimpleName *sn, void* arg){
  //check for local variable
  for(auto it = scopes.rbegin();it != scopes.rend();++it){
    auto f = (*it)->find(sn->name);
    if(f){
        std::cout << "found var\n";
        RType *res = resolveFrag(f);
        res->targetVar = f;
        exprMap[sn] = res;
        return res;
    }
  }
  //method parameter
  if(curMethod != nullptr){
    for(Param& p : curMethod->params){
      if(p.name == sn->name){
        std::cout << "param\n";
        return visitParam(p);
      }
    }
  }
  //class fields
  throw std::string("unknown identifier: ") + sn->name;
}

void* Resolver::visitQName(QName *qn, void* arg){
  RType* scp = (RType*)qn->scope->accept(this, qn);
  TypeDecl* td = scp->targetDecl;
  for(FieldDecl* field : td->fields){
    if(field->name == qn->name){
      auto res = (RType*)visitFieldDecl(field, td);
      return res;
    }
  }
  throw std::string("can't resolve " + qn->name + " in " + td->name);
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

void* Resolver::visitObjExpr(ObjExpr* o, void* arg){
  auto res = new RType;
  if(curClass == nullptr){
    //global symbol
    for(BaseDecl* bd : unit.types){
      if(bd->isEnum) continue;
      TypeDecl* td = dynamic_cast<TypeDecl*>(bd);
      if(td->name == o->name){
        return visitTypeDecl(td);
      }
    }
  }else{
    //inside method
    if(curClass->name == o->name){
      return visitTypeDecl(curClass);
    }
  }
  throw std::string("unresolved class type: " + o->name);
}
     