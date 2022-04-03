#include "Resolver.h"
#include "parser/Util.h"
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



Resolver::Resolver(Unit* unit) : unit(unit){}
Resolver::~Resolver() = default;

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

std::shared_ptr<Scope> Resolver::curScope(){
  return scopes[scopes.size() - 1];
}

void Resolver::resolveAll(){
    scopes.push_back(std::shared_ptr<Scope>(new Scope));
    for(Statement* st : unit->stmts){
        st->accept(this,nullptr);
    }
  
    for(BaseDecl* bd : unit->types){
        visitBaseDecl(bd, nullptr);
    }
    
    for(Method* m : unit->methods){
        visitMethod(m, nullptr);
    }
  
 dump();
}

void Resolver::init(){
    
}

RType* Resolver::resolveScoped(Expression* expr){
  return (RType*)expr->accept(this, nullptr);
}

void* Resolver::visitBaseDecl(BaseDecl* bd, void* arg){
    auto it = declMap.find(bd);
    if(it != declMap.end()) return (*it).second;
    std::cout << "visitBaseDecl: " << bd->name <<  "\n";
	if(bd->isEnum){
		return visitEnumDecl(dynamic_cast<EnumDecl*>(bd), arg);
	}else{
		return visitTypeDecl(dynamic_cast<TypeDecl*>(bd), arg);
	}
}

RType* Resolver::visitCommon(BaseDecl* bd){
	auto res = new RType;
	if(bd->parent != nullptr){
    	//qualified type
	    auto pt = (RType*)visitBaseDecl(bd->parent, nullptr);
  	  auto type = new Type;
        type->scope = pt->type;
  	  type->name = bd->name;
  	  res->type = type;
    }else{
   	 res = makeSimple(bd->name);
    }
    res->unit = unit;
    res->targetDecl = bd;
	return res;
}

void* Resolver::visitEnumDecl(EnumDecl* ed, void* arg){
    auto it = declMap.find((BaseDecl*)ed);
    if(it != declMap.end()) return (*it).second;
	auto backup = curDecl;
	curDecl = ed;
	auto res = visitCommon(ed);
	for(Method* m : ed->methods){
    	visitMethod(m, ed);
    }
	curDecl = backup;
	return res;
}

void* Resolver::visitTypeDecl(TypeDecl* td, void* arg){
    auto it = declMap.find((BaseDecl*)td);
    if(it != declMap.end()) return (*it).second;
	auto backup = curDecl;
	curDecl = td;
    auto res = visitCommon(td);
    declMap[(BaseDecl*)td] = res;
    for(VarDecl* fd : td->fields){
        fd->accept(this, nullptr);
    }
    for(Method* m : td->methods){
        m->accept(this, nullptr);
    }
    for(BaseDecl* bd : td->types){
        bd->accept(this, td);
    }
    curDecl = backup;
    return res;
}

RType* funcType(Method* m){
    auto res = new RType;
    auto arrow = new ArrowType;
    res->type = new Type;
    res->type->arrow = arrow;
    res->type->name = m->name;
    for(auto prm : m->params){
        arrow->params.push_back(prm->type);
    }
    arrow->type = m->type;
    return res;
}    
     
void* Resolver::visitMethod(Method* m, void* arg){
  curMethod = m;
  RType* res =nullptr;
  
  for(Param* prm : m->params){
    prm->accept(this, nullptr);
  }  
  res = (RType*)m->type->accept(this, m);
  if(m->body){
      scopes.push_back(std::shared_ptr<Scope>(new Scope));
      for(Statement* st:m->body->list){
          st->accept(this, nullptr);
      }
      dropScope();
  }
  methodMap[m] = res;
  curMethod = nullptr;
  return res;
}

void* Resolver::visitParam(Param* p, void* arg){
  if(p->method){
      auto res =  resolveType(p->type);
      paramMap[p] = res;
      return res;
  }
  else{
      //todo infer?
      auto res = resolveType(p->type);
      return res;
      //throw std::string("todo arrow param type");
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

void* Resolver::visitType(Type* type, void* arg){
    return resolveType(type);
}

RType* Resolver::find(Type* type, BaseDecl* bd){
    if(bd->name == type->name){
        return (RType*)visitBaseDecl(bd, nullptr);
    }
    //inner
    for(auto inner : bd->types){
        if(inner->name == type->name){
            return (RType*)visitBaseDecl(inner, nullptr);
        }    
    }
    if(bd->parent){
        return find(type, bd->parent);
        /*auto p = bd->parent;
        if(p->name == type->name) return (RType*)visitBaseDecl(p, nullptr);
        //sibling
        for(auto sib : p->types){
            if(sib->name == type->name) return (RType*)visitBaseDecl(sib, nullptr);
        }
        //parent sibling
        if(p->parent){
            for(auto ps : )
        } */
    }    
    return nullptr;
}

/*RType* strType(){
    auto res ;
}*/

RType* Resolver::resolveType(Type* type){
    auto it = typeMap.find(type);
    if(it != typeMap.end()) return (*it).second;
    std::cout << "resolveType: " << type->print() << "\n";
    RType* res = nullptr;
    if(type->isPrim() || type->isVoid()){
        res = new RType;
        res->type = type;
    }
    else if(type->isString() || type->print() == "string"){
      res = new RType;
      auto ref = new Type;
      ref->scope = simpleType("core");
      ref->name = "string";
      res->type = ref;
  }
  else if(type->arrow){
      res = new RType;
      res->type = type;
  }    
  else {
      if(type->scope == nullptr){
      	if(curDecl != nullptr){
  			res = find(type, curDecl);
  		}else{
  			for(auto bd : unit->types){
  				res = find(type, bd);
                  if(res) break;
  			}
  		}
      }else{
          auto st = (RType*)type->scope->accept(this, nullptr);
          for(auto bd : st->targetDecl->types){
              if(bd->name == type->name){
                  /*res = new RType;
                  res->type = type;
                  res->targetDecl = bd;*/
                  res = (RType*)bd->accept(this, nullptr);
                  break;
              }    
          }    
      }
      if(!res) throw std::string("todo resolveType: " + type->print());
  }
  typeMap[type] = res;
  return res;
}

RType* Resolver::resolveFrag(Fragment* f){
    auto it = varMap.find(f);
    if(it != varMap.end()) return (*it).second;
    log("resolveFrag: " + f->print());
    RType* res;
    if(f->type){
        res = (RType*)f->type->accept(this, nullptr);
    }else{
        if(f->rhs){
            res = resolveScoped(f->rhs);
        }else{
            throw std::string("fragment neither has type nor rhs");
        }
  }
  res->targetVar = f;
  //res->targetDecl = curDecl;//todo?
  varMap[f] = res;
  curScope()->add(f);
  return res;
}

void* Resolver::visitVarDeclExpr(VarDeclExpr* vd, void* arg){
  for(Fragment *f : vd->list){
    resolveFrag(f);
  }
  return nullptr;
}

void* Resolver::visitVarDecl(VarDecl* vd, void* arg){
	visitVarDeclExpr(vd->decl, arg);
}

RType* Resolver::local(std::string name){
  //check for local variable
  for(auto it = scopes.rbegin();it != scopes.rend();++it){
    auto frag = (*it)->find(name);
    if(frag){
        RType *res = resolveFrag(frag);
        res->targetVar = frag;
        return res;
    }
  }
  return nullptr;
}

RType* Resolver::param(std::string name){
    if(curMethod){
        for(Param* p : curMethod->params){
            if(p->name == name){
                return (RType*)p->accept(this, nullptr);
            }
        }
    }
    if(arrow){
       for(Param p : arrow->params){
            if(p.name == name){
                return (RType*)p.accept(this, nullptr);
            }
        }
    }    
    return nullptr;
}

RType* Resolver::field(std::string name){
    if(!curDecl) return nullptr;
    if(curDecl->isEnum){
        auto ed = dynamic_cast<EnumDecl*>(curDecl);
    }
    else{
        auto td = dynamic_cast<TypeDecl*>(curDecl);
        for(VarDecl* field : td->fields){
              for(Fragment* f: field->decl->list){
                  if(f->name == name){
                      return resolveFrag(f);
                  }
              }
        }
    }
    return nullptr;
}

Method* Resolver::method(std::string name){
    if(!curDecl) return nullptr;
    for(Method* m : curDecl->methods){
        if(m->name == name) return m;
    }
    return nullptr;
}    

void* Resolver::visitSimpleName(SimpleName *sn, void* arg){
  //check for local variable
  RType* res = local(sn->name);
  if(res) return res;
  //method parameter
  res = param(sn->name);
  if(res) return res;
  //class fields
  res = field(sn->name);
  if(res) return res;
  auto m = method(sn->name);
  if(m) return funcType(m);
  for(BaseDecl* bd : unit->types){
      if(bd->name == sn->name) return bd->accept(this, nullptr);
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

void* Resolver::visitFieldAccess(FieldAccess* fa, void* arg){
    auto scp = (RType*)fa->scope->accept(this, nullptr);
    auto decl = scp->targetDecl;
    if(decl->isEnum){
        auto ed = dynamic_cast<EnumDecl*>(decl);
    }else{
        auto td = dynamic_cast<TypeDecl*>(decl);
        for(auto v : td->fields){
            for(auto frag : v->decl->list){
                if(frag->name == fa->name){
                    return resolveFrag(frag);
                }    
            }    
        }
        for(Method* m : td->methods){
            if(m->name == fa->name) return funcType(m);
        }    
    }
    throw std::string("invalid field " + fa->name + " in " + scp->type->print());
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
    RType* t2 = (RType*)m->params[i]->accept(r, nullptr);
    if(!isSame(t1, t2)) return false;
  }
  return true;  
}

void* Resolver::visitMethodCall(MethodCall *mc, void* arg){
    std::cout << "visitMethodCall " << mc->name << "\n";
    for(auto arg : mc->args){
        auto arrow = dynamic_cast<ArrowFunction*>(arg);
        if(arrow){
            inferArrow(arrow, mc);
        }    
        arg->accept(this, nullptr);
    }    
    if(mc->scope){
        RType* rt = (RType*)mc->scope->accept(this, mc);
        //todo
        for(Method* m : rt->targetDecl->methods){
            if(isSame(this, mc, m)) return visitMethod(m, nullptr);
        }    
        throw std::string("method:  "+ mc->name + " not found in type: " + rt->type->print());
    }    
    if(curDecl){
        //friend method
        for(Method* m : curDecl->methods){
            if(isSame(this, mc, m)){
                return visitMethod(m, nullptr);
            }
        }//for
    }
    //global method
    for(Method* m: unit->methods){
        if(isSame(this, mc, m)){
            return visitMethod(m, nullptr);
        }
     }
     //todo signature check
     //fptr in variables
    RType* res = local(mc->name);
    if(res) return res->type->arrow->type->accept(this, nullptr);
    //method parameter
     res = param(mc->name);
     if(res) return res->type->arrow->type->accept(this, nullptr);
     //class fields
    res = field(mc->name);
    if(res) return res->type->arrow->type->accept(this, nullptr);
    auto m = method(mc->name);
    if(m) return (RType*)visitMethod(m, nullptr);
    throw std::string("method:  "+ mc->name + " not found");
}

Type* common(std::vector<Type*> arr){
}    

RType* inferType(Block* b, Resolver* r){
    for(auto st : b->list){
        st->accept(r, nullptr);
        auto ret = dynamic_cast<ReturnStmt*>(st);
        if(ret){
            if(ret->expr){
                return (RType*)ret->expr->accept(r, nullptr);
            }
        }    
    }
    return makeSimple("void");
}

void* Resolver::visitArrowFunction(ArrowFunction* af, void* arg){
    auto res = new RType;
    auto t = new ArrowType;
    res->type = new Type;
    res->type->arrow = t;
    for(auto prm : af->params){
        t->params.push_back(prm.type);//resolve
    }
    arrow = af;
    if(af->block){
        t->type = inferType(af->block, this)->type;
    }else{
        t->type = ((RType*)af->expr->accept(this, nullptr))->type;
    }
    arrow = nullptr;
    return res;
}

void* Resolver::visitObjExpr(ObjExpr* o, void* arg){
    for(Entry e : o->entries){
        e.value->accept(this, nullptr);
    }    
    return resolveType(o->type);
}

void* Resolver::visitArrayCreation(ArrayCreation *ac, void* arg){
    for(auto e : ac->dims){
        e->accept(this, nullptr);
    }    
    return ac->type->accept(this, nullptr);
}
     