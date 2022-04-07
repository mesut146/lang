#include <iostream>

#include "Resolver.h"
#include "parser/Util.h"
#include "parser/Parser.h"

void Scope::add(Fragment* f) { list.push_back(f); }

void Scope::clear() { list.clear(); }

Fragment* Scope::find(std::string& name) {
    for (Fragment* f : list) {
        if (f->name == name) return f;
    }
    return nullptr;
}

class IncompleteType : public Type {
    std::string print() { return "@incomplete"; }
};

std::map<std::string, Resolver*> Resolver::resolverMap;

Resolver::Resolver(Unit* unit) : unit(unit) {}
Resolver::~Resolver() = default;

Type* simpleType(const std::string name) {
    auto res = new Type;
    res->name = name;
    return res;
}

RType* makeSimple(const std::string name) {
    RType* res = new RType;
    res->type = simpleType(name);
    return res;
}

void Resolver::dump() {
    for (auto f : varMap) {
        std::cout << "var: " << f.first->name << " = "
                  << f.second->type->print() << "\n";
    }
    /*for(auto &p : fieldMap){
      std::cout << "field: " << p.first->name << " = " <<
    p.second->type->print() << "\n";
    }*/
    for (auto& p : methodMap) {
        std::cout << "method: " << p.first->name << " = "
                  << p.second->type->print() << "\n";
        for (Param* prm : p.first->params) {
            std::cout << "param: " << prm->name << " = "
                      << paramMap[prm]->type->print() << "\n";
        }
    }
}

void Resolver::dropScope() {
    curScope()->clear();
    scopes.erase(scopes.end());
}

std::shared_ptr<Scope> Resolver::curScope() {
    return scopes[scopes.size() - 1];
}

void Resolver::resolveAll() {
    init();
    for (BaseDecl* bd : unit->types) {
        visitBaseDecl(bd, nullptr);
    }

    for (Method* m : unit->methods) {
        visitMethod(m, nullptr);
    }

    dump();
}

void Resolver::init() {
    scopes.push_back(std::shared_ptr<Scope>(new Scope));
    for (Statement* st : unit->stmts) {
        st->accept(this, nullptr);
    }
}

RType* Resolver::resolveScoped(Expression* expr) {
    return (RType*)expr->accept(this, nullptr);
}

void* Resolver::visitBaseDecl(BaseDecl* bd, void* arg) {
    auto it = declMap.find(bd);
    if (it != declMap.end()) return (*it).second;
    std::cout << "visitBaseDecl: " << bd->name << "\n";
    if (bd->isEnum) {
        return visitEnumDecl(dynamic_cast<EnumDecl*>(bd), arg);
    } else {
        return visitTypeDecl(dynamic_cast<TypeDecl*>(bd), arg);
    }
}

RType* Resolver::visitCommon(BaseDecl* bd) {
    auto res = new RType;
    if (bd->parent != nullptr) {
        // qualified type
        auto pt = (RType*)visitBaseDecl(bd->parent, nullptr);
        auto type = new Type;
        type->scope = pt->type;
        type->name = bd->name;
        res->type = type;
    } else {
        res = makeSimple(bd->name);
    }
    res->unit = unit;
    res->targetDecl = bd;
    return res;
}

void* Resolver::visitEnumDecl(EnumDecl* ed, void* arg) {
    auto it = declMap.find((BaseDecl*)ed);
    if (it != declMap.end()) return (*it).second;
    auto backup = curDecl;
    curDecl = ed;
    auto res = visitCommon(ed);
    for (Method* m : ed->methods) {
        visitMethod(m, ed);
    }
    curDecl = backup;
    return res;
}

void* Resolver::visitTypeDecl(TypeDecl* td, void* arg) {
    auto it = declMap.find((BaseDecl*)td);
    if (it != declMap.end()) return (*it).second;
    auto backup = curDecl;
    curDecl = td;
    auto res = visitCommon(td);
    declMap[(BaseDecl*)td] = res;
    for (VarDecl* fd : td->fields) {
        fd->accept(this, nullptr);
    }
    for (Method* m : td->methods) {
        m->accept(this, nullptr);
    }
    for (BaseDecl* bd : td->types) {
        bd->accept(this, td);
    }
    curDecl = backup;
    return res;
}

ArrowType* funcType(Method* m) {
    auto arrow = new ArrowType;
    for (auto prm : m->params) {
        arrow->params.push_back(prm->type);
    }
    arrow->type = m->type;
    return arrow;
}

Type* funcType2(Method* m) {
    auto arrow = new ArrowType;
    for (auto prm : m->params) {
        arrow->params.push_back(prm->type);
    }
    arrow->type = m->type;
    auto res = new Type;
    res->arrow = arrow;
    return res;
}

void* Resolver::visitMethod(Method* m, void* arg) {
    auto backup = curMethod;
    curMethod = m;
    RType* res = nullptr;

    for (Param* prm : m->params) {
        prm->accept(this, nullptr);
    }
    res = (RType*)m->type->accept(this, m);
    if (m->body) {
        scopes.push_back(std::shared_ptr<Scope>(new Scope));
        for (Statement* st : m->body->list) {
            st->accept(this, nullptr);
        }
        dropScope();
    }
    methodMap[m] = res;
    curMethod = backup;
    return res;
}

void* Resolver::visitParam(Param* p, void* arg) {
    if (p->type == nullptr) return new RType(new IncompleteType);
    if (p->method) {
        auto res = resolveType(p->type);
        paramMap[p] = res;
        return res;
    } else {
        // todo infer?
        auto res = resolveType(p->type);
        return res;
        // throw std::string("todo arrow param type");
    }
}

void* Resolver::visitAssign(Assign* as, void* arg) {
    RType* t1 = (RType*)as->left->accept(this, as);
    RType* t2 = (RType*)as->right->accept(this, as);
    // return t1 because t2 is going to be autocast to t1 ultimately
    return t1;
}

void* Resolver::visitInfix(Infix* infix, void* arg) {
    std::cout << "visitInfix = " << infix->print() << "\n";
    RType* rt1 = (RType*)infix->left->accept(this, infix);
    RType* rt2 = (RType*)infix->right->accept(this, infix);
    if (rt1->type->isVoid() || rt2->type->isVoid()) {
        throw std::string("operation on void type");
    }
    if (infix->op == "+" && (rt1->type->isString() || rt2->type->isString())) {
        // string concat
        return rt1;
    }

    if (rt1->type->isPrim()) {
        if(!rt2->type->isPrim()){
            throw std::string("infix on prim and non prim types");
        }
            auto s1 = rt1->type->print();
            auto s2 = rt2->type->print();
            if (s1 == s2) {
                return makeSimple(s1);
            }
            std::string arr[] = {"double", "float", "long", "int",
                                 "short",  "char",  "byte", "bool"};
            for (auto t : arr) {
                if (s1 == t || s2 == t) {
                    return makeSimple(t);
                }
            }
        
    } else {
    }
}

void* Resolver::visitType(Type* type, void* arg) { return resolveType(type); }

RType* Resolver::find(Type* type, BaseDecl* bd) {
    if (bd->name == type->name) {
        return (RType*)visitBaseDecl(bd, nullptr);
    }
    // inner
    for (auto inner : bd->types) {
        if (inner->name == type->name) {
            return (RType*)visitBaseDecl(inner, nullptr);
        }
    }
    if (bd->parent) {
        return find(type, bd->parent);
        /*auto p = bd->parent;
        if(p->name == type->name) return (RType*)visitBaseDecl(p, nullptr);
        //sibling
        for(auto sib : p->types){
            if(sib->name == type->name) return (RType*)visitBaseDecl(sib,
        nullptr);
        }
        //parent sibling
        if(p->parent){
            for(auto ps : )
        } */
    }
    return nullptr;
}

RType* Resolver::resolveType(Type* type) {
    auto it = typeMap.find(type);
    if (it != typeMap.end()) return (*it).second;
    std::cout << "resolveType: " << type->print() << "\n";
    RType* res = nullptr;
    if (type->isPrim() || type->isVoid()) {
        res = new RType;
        res->type = type;
    } else if (type->isString() || type->print() == "string") {
        res = new RType;
        auto ref = new Type;
        ref->scope = simpleType("core");
        ref->name = "string";
        res->type = ref;
    } else if (type->arrow) {
        res = new RType;
        res->type = type;
    } else {
        if (type->scope == nullptr) {
            if (curDecl != nullptr) {
                res = find(type, curDecl);
            } else {
                for (auto bd : unit->types) {
                    res = find(type, bd);
                    if (res) break;
                }
            }
        } else {
            auto st = (RType*)type->scope->accept(this, nullptr);
            for (auto bd : st->targetDecl->types) {
                if (bd->name == type->name) {
                    /*res = new RType;
                    res->type = type;
                    res->targetDecl = bd;*/
                    res = (RType*)bd->accept(this, nullptr);
                    break;
                }
            }
        }
        if (!res) throw std::string("todo resolveType: " + type->print());
    }
    typeMap[type] = res;
    return res;
}

void* Resolver::visitFragment(Fragment* f, void* arg) {
    auto it = varMap.find(f);
    if (it != varMap.end()) return (*it).second;
    log("visitFragment: " + f->print());
    RType* res;
    if (f->type) {
        res = (RType*)f->type->accept(this, nullptr);
    } else {
        if (f->rhs) {
            res = resolveScoped(f->rhs);
        } else {
            throw std::string("fragment neither has type nor rhs");
        }
    }
    res->targetVar = f;
    // res->targetDecl = curDecl;//todo?
    varMap[f] = res;
    curScope()->add(f);
    return res;
}

void* Resolver::visitVarDeclExpr(VarDeclExpr* vd, void* arg) {
    for (Fragment* f : vd->list) {
        f->accept(this, arg);
    }
    return nullptr;
}

void* Resolver::visitVarDecl(VarDecl* vd, void* arg) {
    visitVarDeclExpr(vd->decl, arg);
}

void Resolver::local(std::string name, std::vector<Symbol> res) {
    // check for local variable
    for (auto it = scopes.rbegin(); it != scopes.rend(); ++it) {
        auto frag = (*it)->find(name);
        if (frag) {
            res.push_back(Symbol(frag, this));
        }
    }
}

void Resolver::param(std::string name, std::vector<Symbol> res) {
    // method or lambda parameter
    if (curMethod) {
        for (Param* p : curMethod->params) {
            if (p->name == name) {
                res.push_back(Symbol(p, this));
            }
        }
    }
    if (arrow) {
        for (Param* p : arrow->params) {
            if (p->name == name) {
                res.push_back(Symbol(p, this));
            }
        }
    }
}

void Resolver::field(std::string name, std::vector<Symbol> res) {
    if (!curDecl) return;
    if (curDecl->isEnum) {
        auto ed = dynamic_cast<EnumDecl*>(curDecl);
    } else {
        auto td = dynamic_cast<TypeDecl*>(curDecl);
        for (VarDecl* field : td->fields) {
            for (Fragment* f : field->decl->list) {
                if (f->name == name) {
                    res.push_back(Symbol(f, this));
                }
            }
        }
    }
}

void Resolver::method(std::string name, std::vector<Symbol> res) {
    if (!curDecl) return;
    for (Method* m : curDecl->methods) {
        if (m->name == name) res.push_back(Symbol(m, this));
    }
}

void* Resolver::visitSimpleName(SimpleName* sn, void* arg) {
    auto arr = find(sn->name);
    if(arr.size() == 1){
        auto s = arr[0];
        if(s.prm)  return s.resolve(s.prm);
        else if(s.f) return s.resolve(s.f);
        else if(s.m) return s.resolve(s.m);
        else if(s.decl) return s.resolve(s.decl);
    }
    throw std::string("unknown identifier: ") + sn->name;
}

void* Resolver::visitQName(QName* qn, void* arg) {
    RType* scp = (RType*)qn->scope->accept(this, qn);
    if (scp->type->isArray()) {
        if (qn->name == "size" || qn->name == "length") {
            return makeSimple("int");
        } else {
            // todo more methods
            throw std::string("invalid array method: " + qn->name);
        }
    }
    auto bd = scp->targetDecl;
    if (bd == nullptr) throw std::string("bd is null");
    if (bd->isEnum) {
        throw std::string("visitQName todo enum field");
    } else {
        auto td = dynamic_cast<TypeDecl*>(bd);
        for (VarDecl* field : td->fields) {
            for (Fragment* f : field->decl->list) {
                if (f->name == qn->name) {
                    auto res = (RType*)f->accept(this, nullptr);
                    return res;
                }
            }
        }
    }
    throw std::string("can't resolve " + qn->name + " in " + bd->name);
}

void* Resolver::visitFieldAccess(FieldAccess* fa, void* arg) {
    auto scp = (RType*)fa->scope->accept(this, nullptr);
    auto decl = scp->targetDecl;
    if (decl->isEnum) {
        auto ed = dynamic_cast<EnumDecl*>(decl);
    } else {
        auto td = dynamic_cast<TypeDecl*>(decl);
        for (auto v : td->fields) {
            for (auto frag : v->decl->list) {
                if (frag->name == fa->name) {
                    return frag->accept(this, nullptr);
                }
            }
        }
        for (Method* m : td->methods) {
            if (m->name == fa->name) return funcType(m);
        }
    }
    throw std::string("invalid field " + fa->name + " in " +
                      scp->type->print());
}

void* Resolver::visitLiteral(Literal* lit, void* arg) {
    RType* res = new RType;
    auto type = new Type;
    res->type = type;
    if (lit->isStr) {
        type->scope = simpleType("core");
        type->name = "string";
    } else {
        std::string s;
        if (lit->isBool) {
            s = "bool";
        } else if (lit->isFloat) {
            s = "float";
        } else if (lit->isInt) {
            s = "int";
        } else if (lit->isChar) {
            s = "char";
        }
        type->name = s;
    }
    return res;
}

bool isSame(Type* t1, Type* t2) { return t1->print() == t2->print(); }

bool isSame(RType* rt1, RType* rt2) {
    Type* t1 = rt1->type;
    Type* t2 = rt2->type;
    return t1->print() == t2->print();
}

bool subType(Type* type, Type* sub) {
    if (dynamic_cast<IncompleteType*>(type)) return true;
    if (type->arrow) {
        if (!sub->arrow) return false;
        auto arrow = type->arrow;
        auto arrow2 = sub->arrow;
        if (arrow->params.size() != arrow2->params.size()) return false;
        if (!dynamic_cast<IncompleteType*>(arrow->type) &&
            !isSame(arrow->type, arrow2->type))
            return false;
        for (int i = 0; i < arrow->params.size(); i++) {
            Type* t1 = arrow->params[i];
            Type* t2 = arrow2->params[i];
            if (dynamic_cast<IncompleteType*>(t1)) continue;  // to be inferred
            if (t1->print() != t2->print()) return false;
        }
        return true;
    }
    if (type->print() == sub->print()) return true;
    if (type->isVoid()) return false;
    if (type->isArray()) return false;
    if (type->isPrim()) {
        if (!sub->isPrim()) return false;
        std::map<std::string, int> sizeMap{
            {"byte", 1}, {"char", 2},  {"short", 2}, {"int", 4},
            {"long", 8}, {"float", 4}, {"double", 8}};
        if (type->name == "bool") return false;
        // auto cast to larger size
        if (sizeMap[type->name] <= sizeMap[sub->name]) {
            return true;
        } else {
            return false;
        }
    }
    // upcast
    throw std::string("subtype " + type->print() + " sub: " + sub->print());
}

bool isSame(Resolver* r, MethodCall* mc, Method* m) {
    if (mc->name != m->name) return false;
    if (mc->args.size() != m->params.size()) return false;
    for (int i = 0; i < mc->args.size(); i++) {
        RType* t1 = (RType*)mc->args[i]->accept(r, mc);
        RType* t2 = (RType*)m->params[i]->accept(r, nullptr);
        if (t1->type == nullptr) continue;  // to be inferred
        if (!subType(t1->type, t2->type)) return false;
    }
    return true;
}

bool isSame(Resolver* r, MethodCall* mc, ArrowType* sig) {
    if (mc->args.size() != sig->params.size()) return false;
    for (int i = 0; i < mc->args.size(); i++) {
        RType* t1 = (RType*)mc->args[i]->accept(r, mc);
        RType* t2 = (RType*)sig->params[i]->accept(r, nullptr);
        if (t1->type == nullptr) continue;  // to be inferred
        if (!subType(t1->type, t2->type)) return false;
    }
    return true;
}
bool isSameFull(Resolver* r, MethodCall* mc, ArrowType* sig) {
    if (mc->args.size() != sig->params.size()) return false;
    for (int i = 0; i < mc->args.size(); i++) {
        RType* t1 = (RType*)mc->args[i]->accept(r, mc);
        RType* t2 = (RType*)sig->params[i]->accept(r, nullptr);
        if (t1->type == nullptr) continue;  // to be inferred
        if (!isSame(t1->type, t2->type)) return false;
    }
    return true;
}
bool isSame1(MethodCall* mc, Method* m) {
    if (mc->name != m->name) return false;
    if (mc->args.size() != m->params.size()) return false;
    return true;
}

void bind(MethodCall* mc, Type* sig) {
    for (int i = 0; i < mc->args.size(); i++) {
        Expression* arg = mc->args[i];
        auto arrow = dynamic_cast<ArrowFunction*>(arg);
        if (!arrow) continue;
        ArrowType* arg2 = sig->arrow->params[i]->arrow;
        int j = 0;
        for (auto prm : arrow->params) {
            if (!prm->type) {
                prm->type = arg2->params[j];
                std::cout << "inferred: " + prm->print() + "\n";
            }
            j++;
        }
    }
}

std::string toPath(Name* nm){
    if(nm->isSimple()){
        return dynamic_cast<SimpleName*>(nm)->name;
    }else{
        auto q = dynamic_cast<QName*>(nm);
        return toPath(q->scope) + "/" + q->name;
    }
}

Resolver* Resolver::getResolver(std::string path){
    auto it = resolverMap.find(path);
    if(it != resolverMap.end()) return (*it).second;
    Lexer lexer(path);
    Parser parser(lexer);
    Unit* u = parser.parseUnit();
    u->path = path;
    auto r = new Resolver(u);
    r->resolveAll();
    resolverMap[path] = r;
    return r;
}


std::vector<Symbol> Resolver::find(std::string& name){
    std::vector<Symbol> res;
    for(auto bd : unit->types){
        if(bd->name == name) res.push_back(Symbol(bd, this));
    }
    for(auto m : unit->methods){
        if(m->name == name) res.push_back(Symbol(m, this));
    }
    /*for(auto st : unit->stmts){
        auto vd = dynamic_cast<VarDecl*>(st);
        if(vd){
            for(Fragment* f : vd->decl->list){
                if(f->name == name) res.push_back(Symbol(f, this));
            }
        }
    }*/
    // for local variable
    local(name, res);
    // method parameter
    param(name, res);
    // class fields
    field(name, res);
    // class methods
    method(name, res);
    other(name, res);
    return res;
}

void Resolver::other(std::string name, std::vector<Symbol> res){
    for(ImportStmt is : unit->imports){
        if(is.normal){
            Resolver* r = getResolver(root +"/" +toPath(is.normal->path));
            auto arr = r->find(name);
            res.insert(res.end(), arr.begin(), arr.end());
        }else{
            throw std::string("import2");
        }
    }
}

void* Resolver::visitMethodCall(MethodCall* mc, void* arg) {
    std::cout << "visitMethodCall " << mc->name << "\n";
    Type* target = nullptr;
    std::vector<Type*> list;  // candidates
    if (mc->scope) {
        RType* scp = (RType*)mc->scope->accept(this, mc);
        // todo
        for (Method* m : scp->targetDecl->methods) {
            if (isSame(this, mc, m)) list.push_back(funcType2(m));
        }
        if (list.empty())
            throw std::string("method:  " + mc->name +
                              " not found in type: " + scp->type->print());
        if (list.size() > 1)
            throw std::string("more than one candidate method for " + mc->name +
                              "in " + scp->type->print());
        auto sig = list[0];
        return sig->accept(this, nullptr);
    } else {
        auto syms = find(mc->name);
        for(Symbol s : syms){
            if(s.m){
                if(isSame(this, mc, s.m)) list.push_back(funcType2(s.m));
            }else if(s.f){
                auto t = s.resolve(s.f)->type;
                if(isSame(this, mc, t->arrow)) list.push_back(t);
            }
            else if(s.prm){
                auto t = s.resolve(s.prm)->type;
                if(isSame(this, mc, t->arrow)) list.push_back(t);
            }
        }
        if (list.empty())
            throw std::string("method:  " + mc->name + " not found");
        // find most compatible
        for (auto sig : list) {
            if (isSameFull(this, mc, sig->arrow)) {
                return sig->accept(this, nullptr);
            }
        }
        if (list.size() == 1) {
            bind(mc, list[0]);
            return list[0]->accept(this, nullptr);
        }

        throw std::string("method:  " + mc->name + " has " +
                          std::to_string(list.size()) + " candidates");
    }
}

RType* inferType(Block* b, Resolver* r) {
    for (auto st : b->list) {
        st->accept(r, nullptr);
        auto ret = dynamic_cast<ReturnStmt*>(st);
        if (ret) {
            if (ret->expr) {
                return (RType*)ret->expr->accept(r, nullptr);
            }
        }
    }
    return makeSimple("void");
}

void* Resolver::visitArrowFunction(ArrowFunction* af, void* arg) {
    auto type = new Type;
    auto t = new ArrowType;
    type->arrow = t;
    bool needInfer = false;
    for (auto prm : af->params) {
        if (!prm->type) {
            needInfer = true;
            t->params.push_back(new IncompleteType);
        } else {
            t->params.push_back(((RType*)prm->accept(this, nullptr))->type);
        }
    }
    if (!needInfer) {
        arrow = af;
        if (af->block) {
            t->type = inferType(af->block, this)->type;
        } else {
            t->type = ((RType*)af->expr->accept(this, nullptr))->type;
        }
        arrow = nullptr;
    } else {
        t->type = new IncompleteType;
    }
    return new RType(type);
}

void* Resolver::visitObjExpr(ObjExpr* o, void* arg) {
    for (Entry e : o->entries) {
        e.value->accept(this, nullptr);
    }
    return resolveType(o->type);
}

void* Resolver::visitArrayCreation(ArrayCreation* ac, void* arg) {
    for (auto e : ac->dims) {
        e->accept(this, nullptr);
    }
    return ac->type->accept(this, nullptr);
}

void* Resolver::visitAsExpr(AsExpr* as, void* arg) {
    auto left = (RType*)as->expr->accept(this, nullptr);
    auto right = (RType*)as->type->accept(this, nullptr);
    return right;
}