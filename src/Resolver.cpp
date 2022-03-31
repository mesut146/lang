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

Type* simpleType(const std::string name){
    auto res = new Type;
    res->name = name;
    return res;
}    

RType* makeSimple(const std::string name){
  RType* res = new RType;
  res->type = simpleType(name);
  return res;
}

void normalize(Unit& unit){
  
}

void Resolver::dump(){
  for(auto f : varMap){
      std::cout << "var: " << f.first->name << " = " << f.second->type->print() << "\n";
  }
  /*for(auto &p : fieldMap){
    std::cout << "field: " << p.first->name << " = " << p.second->type->print() << "\n";
  }*/
  for(auto& p:methodMap){
    std::cout << "method: " << p.first->name << " = " << p.second->type->print() << "\n";
    for(Param* prm:p.first->params){
      std::cout << "param: " << prm->name << " = " <<  paramMap[prm]->type->print() << "\n";
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
      visitVarDecl(vd, nullptr);
    }
    else{
      st->accept(this, nullptr);
    }
  }//for
  
  for(BaseDecl* bd : unit.types){
    visitBaseDecl(bd, nullptr);
  }
  for(Method* m : unit.methods){
    visitMethod(m, nullptr);
  }
  
 dump();
}

RType* Resolver::resolveScoped(Expression* expr){
  return (RType*)expr->accept(this, nullptr);
}

void* Resolver::visitBaseDecl(BaseDecl* bd, void* arg){
	if(bd->isEnum){
		return visitEnumDecl(dynamic_cast<EnumDecl*>(bd));
	}else{
		return visitTypeDecl(dynamic_cast<TypeDecl*>(bd));
	}
}

RType* Resolver::visitCommon(BaseDecl* bd){
	auto res = new RType;
	res->targetDecl = bd;
	if(bd->parent != nullptr){
    	//qualified type
	    auto pt = (RType*)visitBaseDecl(bd->parent, nullptr);
  	  auto type = new Type;
        type->scope = pt->type;
  	  type->name = bd->name;
  	  res->type = type;
    }else{
   	 res = makeSimple(bd->name);
   	 res->unit = &unit;
    }
	return res;
}

RType* Resolver::visitEnumDecl(EnumDecl* ed){
	auto backup = curDecl;
	curDecl = ed;
	auto res = visitCommon(ed);
	for(Method* m : ed->methods){
    	visitMethod(m, ed);
    }
	curDecl = backup;
	return res;
}

RType* Resolver::visitTypeDecl(TypeDecl* td){
	auto backup = curDecl;
	curDecl = td;
    auto res = visitCommon(td);
    for(VarDecl* fd : td->fields){
        visitVarDecl(fd->decl, td);
    }
    for(Method* m : td->methods){
        visitMethod(m, td);
    }
    for(BaseDecl* bd : td->types){
        bd->accept(this, td);
    }
    curDecl = backup;
    return res;
}
     
void* Resolver::visitMethod(Method* m, void* arg){
  curMethod = m;
  RType* res =nullptr;
  
  for(Param* prm:m->params){
    visitParam(prm);
  }  
  res = (RType*)m->type->accept(this, m);
  scopes.push_back(new Scope);
  for(Statement* st:m->body->list){
    st->accept(this, nullptr);
  }//for
  methodMap[m] = res;
  dropScope();
  curMethod = nullptr;
  return res;
}

RType* Resolver::visitParam(Param* p){
  if(p->method != nullptr){
    auto res =  resolveType(p->type);
    paramMap[p] = res;
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
  RType* rt1 = (RType*)infix->left->accept(this, infix);
  RType* rt2 = (RType*)infix->right->accept(this, infix);
  if(rt1->type->isVoid() || rt2->type->isVoid()){
    throw std::string("operation on void type");
  }
  if(infix->op == "+" && (rt1->type->isString() || rt2->type->isString())){
    //string concat
    return rt1;
    /*auto res = new RType;
    auto ref = new Type;
    res->type = ref;
    return res;*/
  }

  if(rt1->type->isPrim()){
    if(rt2->type->isPrim()){
      auto s1 = rt1->type->print();
      auto s2 = rt2->type->print();
      if(s1 == s2){
        return makeSimple(s1);
      }
      std::string arr[] = {"double", "float", "long", "int", "short", "char", "byte", "bool"};
      for(auto t : arr){
        if(s1 == t || s2 == t){
          return makeSimple(t);
        }
      }
      /*if(s1 == "double" || s2 == "double"){
        return makeSimple("double");
      }
      if(s1 == "float" || s2 == "float"){
        return makeSimple("float");
      }
      if(s1 == "long" || s2 == "long"){
        return makeSimple("long");
      }
      if(s1 == "int" || s2 == "int"){
        return makeSimple("int");
      }
      if(s1 == "short" || s2 == "short"){
        return makeSimple("short");
      }
      if(s1 == "char" || s2 == "char"){
        return makeSimple("char");
      }
      if(s1 == "byte" || s2 == "byte"){
        return makeSimple("byte");
      }
      if(s1 == "bool" || s2 == "bool"){
        return makeSimple("bool");
      }*/
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
    auto ref = new Type;
    ref->scope = simpleType("core");
    ref->name = "string";
    res->type = ref;
  }else {
      if(type->scope == nullptr){
      	if(curDecl != nullptr){
  			if(curDecl->name == type->name){
  				return (RType*)visitBaseDecl(curDecl, nullptr);
  			}else{
  			//inner
  			}
  		}else{
  			for(auto bd : unit.types){
  				if(bd->name == type->name){
  					return (RType*)visitBaseDecl(bd, nullptr);
  				}else{
  				//inner
  				}
  			}
  		}
      }else{
          auto st = (RType*)type->scope->accept(this, nullptr);
          for(auto bd : st->targetDecl->types){
              if(bd->name == type->name){
                  res->type = type;
                  res->targetDecl = bd;
                  return res;
              }    
          }    
      }    
      throw std::string("todo resolveType: " + type->print());
  }
  return res;
}

RType* Resolver::resolveFrag(Fragment* f){
  RType* res = nullptr;
  if(f->rhs != nullptr){
    res = resolveScoped(f->rhs);
  }
  //res->targetVar = f;
  //varMap[f] = res;
  curScope()->add(f);
  return res;
}

void* Resolver::visitVarDecl(VarDeclExpr* vd, void* arg){
  for(Fragment *f : vd->list){
    resolveFrag(f);
  }
  return nullptr;
}

void* Resolver::visitVarDecl(VarDecl* vd, void* arg){
	visitVarDecl(vd->decl, arg);
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
    for(Param* p : curMethod->params){
      if(p->name == sn->name){
        std::cout << "param\n";
        return visitParam(p);
      }
    }
  }
  //class fields
  if(curDecl != nullptr){
      if(curDecl->isEnum){
          auto ed = dynamic_cast<EnumDecl*>(curDecl);
      }
      else{
          auto td = dynamic_cast<TypeDecl*>(curDecl);
          for(VarDecl* field : td->fields){
              for(Fragment* f: field->decl->list){
                  if(f->name == sn->name){
                      std::cout << "field\n";
                      return resolveFrag(f);
                  }
              }
          }
      }
  }
  throw std::string("unknown identifier: ") + sn->name;
}

void* Resolver::visitQName(QName *qn, void* arg){
  RType* scp = (RType*)qn->scope->accept(this, qn);
  if(scp->type->isArray()){
    if(qn->name == "size" || qn->name == "length"){
      return makeSimple("int");
    }else{
        //todo more methods
      throw std::string("invalid array method: " + qn->name);
    }
  }
  auto bd = scp->targetDecl;
  if(bd == nullptr) throw std::string("bd is null");
  if(bd->isEnum){
      throw std::string("visitQName todo enum field");
  }else{
      auto td = dynamic_cast<TypeDecl*>(bd);
      for(VarDecl* field : td->fields){
          for(Fragment* f : field->decl->list){
              if(f->name == qn->name){
                  auto res = (RType*)resolveFrag(f);
                  return res;
              }
          }
      }
  }
  throw std::string("can't resolve " + qn->name + " in " + bd->name);
}

void* Resolver::visitLiteral(Literal *lit, void* arg){
  RType* res = new RType;
  auto type = new Type;
  res->type = type;
  if(lit->isStr){
      type->scope = simpleType("core");
      type->name = "string";
  }else{
    std::string s;
    if(lit->isBool){
      s = "bool";
    }else  if(lit->isFloat){
      s = "float";
    }else  if(lit->isInt){
      s = "int";
    }else  if(lit->isChar){
      s = "char";
    }
    type->name = s;
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
  if(curDecl != nullptr){
    //friend method
    for(Method* m : curDecl->methods){
      if(isSame(this, mc, m)){
        return visitMethod(m, nullptr);
      }
    }//for
    //global method
    for(Method* m: unit.methods){
      if(isSame(this, mc, m)){
        return visitMethod(m, nullptr);
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
  return resolveType(o->type);
}  
     