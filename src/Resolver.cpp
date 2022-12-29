#include <iostream>
#include <list>

#include "Resolver.h"
#include "parser/Parser.h"
#include "parser/Util.h"

void Scope::add(Fragment *f) { list.push_back(f); }

void Scope::clear() { list.clear(); }

Fragment *Scope::find(std::string &name) {
    for (auto *f : list) {
        if (f->name == name) return f;
    }
    return nullptr;
}

class IncompleteType : public Type {
    std::string print() override { return "@incomplete"; }
};

std::map<std::string, Resolver *> Resolver::resolverMap;

Resolver::Resolver(Unit *unit) : unit(unit) {}
Resolver::~Resolver() = default;

Type *simpleType(const std::string name) {
    auto res = new Type;
    res->name = name;
    return res;
}

RType *makeSimple(const std::string name) {
    auto *res = new RType;
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
    for (auto &p : methodMap) {
        std::cout << "method: " << p.first->name << " = "
                  << p.second->type->print() << "\n";
        for (Param *prm : p.first->params) {
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
    for (auto *bd : unit->types) {
        visitBaseDecl(bd, nullptr);
    }

    for (auto *m : unit->methods) {
        visitMethod(m, nullptr);
    }

    dump();
}

void Resolver::init() {
    scopes.push_back(std::shared_ptr<Scope>(new Scope));
    for (auto *st : unit->stmts) {
        st->accept(this, nullptr);
    }
}

RType *Resolver::resolveScoped(Expression *expr) {
    return (RType *) expr->accept(this, nullptr);
}

void *Resolver::visitBaseDecl(BaseDecl *bd, void *arg) {
    auto it = declMap.find(bd);
    if (it != declMap.end()) return (*it).second;
    std::cout << "visitBaseDecl: " << bd->name << "\n";
    if (bd->isEnum) {
        return visitEnumDecl(dynamic_cast<EnumDecl *>(bd), arg);
    } else {
        return visitTypeDecl(dynamic_cast<TypeDecl *>(bd), arg);
    }
}

RType *Resolver::visitCommon(BaseDecl *bd) {
    auto res = new RType;
    if (bd->parent != nullptr) {
        // qualified type
        auto pt = (RType *) visitBaseDecl(bd->parent, nullptr);
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

void *Resolver::visitEnumDecl(EnumDecl *ed, void *arg) {
    auto it = declMap.find((BaseDecl *) ed);
    if (it != declMap.end()) return (*it).second;
    auto backup = curDecl;
    curDecl = ed;
    auto res = visitCommon(ed);
    for (auto *m : ed->methods) {
        visitMethod(m, ed);
    }
    curDecl = backup;
    return res;
}

void *Resolver::visitTypeDecl(TypeDecl *td, void *arg) {
    auto it = declMap.find((BaseDecl *) td);
    if (it != declMap.end()) return (*it).second;
    auto backup = curDecl;
    curDecl = td;
    auto res = visitCommon(td);
    declMap[(BaseDecl *) td] = res;
    //    for (auto *fd : td->fields) {
    //        fd->accept(this, nullptr);
    //    }
    for (auto *m : td->methods) {
        m->accept(this, nullptr);
    }
    for (auto *bd : td->types) {
        bd->accept(this, td);
    }
    curDecl = backup;
    return res;
}

void *Resolver::visitMethod(Method *m, void *arg) {
    auto backup = curMethod;
    curMethod = m;
    RType *res = nullptr;

    for (auto *prm : m->params) {
        prm->accept(this, nullptr);
    }
    res = (RType *) m->type->accept(this, m);
    res->targetMethod = m;
    /*if (m->body) {
        scopes.push_back(std::make_shared<Scope>());
        for (auto *st : m->body->list) {
            st->accept(this, nullptr);
        }
        dropScope();
    }*/
    methodMap[m] = res;
    curMethod = backup;
    return res;
}

void *Resolver::visitParam(Param *p, void *arg) {
    if (p->type == nullptr) return new RType(new IncompleteType);
    if (p->method) {
        auto res = resolveType(p->type);
        paramMap[p] = res;
        return res;
    } else {
        // todo infer?
        auto res = resolveType(p->type);
        return res;
    }
}

void *Resolver::visitAssign(Assign *as, void *arg) {
    auto *t1 = (RType *) as->left->accept(this, as);
    auto *t2 = (RType *) as->right->accept(this, as);
    // return t1 because t2 is going to be autocast to t1 ultimately
    return t1;
}

void *Resolver::visitInfix(Infix *infix, void *arg) {
    std::cout << "visitInfix = " << infix->print() << "\n";
    auto *rt1 = (RType *) infix->left->accept(this, infix);
    auto *rt2 = (RType *) infix->right->accept(this, infix);
    if (rt1->type->isVoid() || rt2->type->isVoid()) {
        throw std::runtime_error("operation on void type");
    }
    if (infix->op == "+" && (rt1->type->isString() || rt2->type->isString())) {
        // string concat
        return rt1;
    }

    if (rt1->type->isPrim()) {
        if (!rt2->type->isPrim()) {
            throw std::runtime_error("infix on prim and non prim types");
        }
        auto s1 = rt1->type->print();
        auto s2 = rt2->type->print();
        if (s1 == s2) {
            return makeSimple(s1);
        }
        std::string arr[] = {"double", "float", "long", "int",
                             "short", "char", "byte", "bool"};
        for (auto &t : arr) {
            if (s1 == t || s2 == t) {
                return makeSimple(t);
            }
        }

    } else {
    }
    throw std::runtime_error("visitInfix: " + infix->print());
}

void *Resolver::visitType(Type *type, void *arg) { return resolveType(type); }

RType *Resolver::find(Type *type, BaseDecl *bd) {
    if (bd->name == type->name) {
        return (RType *) visitBaseDecl(bd, nullptr);
    }
    // inner
    for (auto inner : bd->types) {
        if (inner->name == type->name) {
            return (RType *) visitBaseDecl(inner, nullptr);
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

RType *Resolver::resolveType(Type *type) {
    auto it = typeMap.find(type);
    if (it != typeMap.end()) return (*it).second;
    std::cout << "resolveType: " << type->print() << "\n";
    RType *res = nullptr;
    if (type->isPrim() || type->isVoid()) {
        res = new RType;
        res->type = type;
    } else if (type->isString() || type->print() == "string") {
        res = new RType;
        auto ref = new Type;
        ref->scope = simpleType("core");
        ref->name = "string";
        res->type = ref;
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
            auto st = (RType *) type->scope->accept(this, nullptr);
            for (auto bd : st->targetDecl->types) {
                if (bd->name == type->name) {
                    /*res = new RType;
                    res->type = type;
                    res->targetDecl = bd;*/
                    res = (RType *) bd->accept(this, nullptr);
                    break;
                }
            }
        }
        if (!res) throw std::runtime_error("todo resolveType: " + type->print());
    }
    typeMap[type] = res;
    return res;
}

void *Resolver::visitFragment(Fragment *f, void *arg) {
    auto it = varMap.find(f);
    if (it != varMap.end()) return (*it).second;
    log("visitFragment: " + f->print());
    RType *res;
    if (f->type) {
        res = (RType *) f->type->accept(this, nullptr);
    } else {
        if (f->rhs) {
            res = (RType *) f->rhs->accept(this, nullptr);
            if (!res->arr.empty()) {
            }
        } else {
            throw std::runtime_error("fragment neither has type nor rhs");
        }
    }
    res->targetVar = f;
    // res->targetDecl = curDecl;//todo?
    varMap[f] = res;
    if (!scopes.empty()) curScope()->add(f);
    return res;
}

void *Resolver::visitVarDeclExpr(VarDeclExpr *vd, void *arg) {
    for (Fragment *f : vd->list) {
        f->accept(this, arg);
    }
    return nullptr;
}

void *Resolver::visitVarDecl(VarDecl *vd, void *arg) {
    return visitVarDeclExpr(vd->decl, arg);
}

void Resolver::local(std::string name, std::vector<Symbol> &res) {
    if (fromOther) {
        //other import, need to resolved differently
        for (auto st : unit->stmts) {
            auto vd = dynamic_cast<VarDecl *>(st);
            if (!vd) continue;
            for (auto *f : vd->decl->list) {
                if (f->name == name) {
                    res.push_back(Symbol(f, this));
                    return;
                }
            }
        }
        return;
    }
    // check for local variable
    for (auto it = scopes.rbegin(); it != scopes.rend(); ++it) {
        auto frag = (*it)->find(name);
        if (frag) {
            res.push_back(Symbol(frag, this));
        }
    }
}

void Resolver::param(const std::string &name, std::vector<Symbol> &res) {
    // method or lambda parameter
    if (curMethod) {
        for (auto *p : curMethod->params) {
            if (p->name == name) {
                res.push_back(Symbol(p, this));
            }
        }
    }
}

void Resolver::field(const std::string &name, std::vector<Symbol> &res) {
    if (!curDecl) return;
    if (curDecl->isEnum) {
        auto ed = dynamic_cast<EnumDecl *>(curDecl);
    } else {
        auto td = dynamic_cast<TypeDecl *>(curDecl);
        for (auto *f : td->fields) {
            if (f->name == name) {
                res.push_back(Symbol(f, this));
            }
        }
    }
}

void Resolver::method(const std::string &name, std::vector<Symbol> &res) {
    if (!curDecl) return;
    for (auto *m : curDecl->methods) {
        if (m->name == name) res.push_back(Symbol(m, this));
    }
}

void *Resolver::visitSimpleName(SimpleName *sn, void *arg) {
    auto arr = find(sn->name, true);
    if (arr.empty()) throw std::runtime_error("unknown identifier: " + sn->name);
    if (arr.size() == 1) {
        auto s = arr[0];
        if (s.prm) return s.resolve(s.prm);
        else if (s.f)
            return s.resolve(s.f);
        else if (s.m)
            return s.resolve(s.m);
        else if (s.decl)
            return s.resolve(s.decl);
        else if (s.imp) {
            auto res = new RType;
            res->arr.push_back(s);
            return res;
        } else
            throw std::runtime_error("unexpected state");
    } else {
        auto res = new RType;
        res->arr = arr;
        return res;
        //throw std::string("more than 1 result for ") + sn->name;
    }
}

void *Resolver::visitQName(QName *qn, void *arg) {
    auto *scp = (RType *) qn->scope->accept(this, qn);
    if (scp->type->isArray()) {
        if (qn->name == "size" || qn->name == "length") {
            return makeSimple("int");
        } else {
            // todo more methods
            throw std::runtime_error("invalid array method: " + qn->name);
        }
    }
    auto bd = scp->targetDecl;
    if (bd == nullptr) throw std::runtime_error("bd is null");
    if (bd->isEnum) {
        throw std::runtime_error("visitQName todo enum field");
    } else {
        auto td = dynamic_cast<TypeDecl *>(bd);
        for (auto *f : td->fields) {
            if (f->name == qn->name) {
                auto res = (RType *) f->accept(this, nullptr);
                return res;
            }
        }
    }
    throw std::runtime_error("can't resolve " + qn->name + " in " + bd->name);
}


void *Resolver::visitFieldAccess(FieldAccess *fa, void *arg) {
    auto scp = (RType *) fa->scope->accept(this, nullptr);
    std::vector<Symbol> arr;
    if (scp->isImport) {
        auto *r = getResolver(scp->unit->path);
        auto tmp = r->find(fa->name, false);
        auto res = new RType;
        res->arr = tmp;
        return res;
    }
    auto decl = scp->targetDecl;
    if (decl->isEnum) {
        auto ed = dynamic_cast<EnumDecl *>(decl);
    } else {
        auto td = dynamic_cast<TypeDecl *>(decl);
        for (auto v : td->fields) {
            if (v->name == fa->name) {
                return v->accept(this, nullptr);
            }
        }
    }
    throw std::runtime_error("invalid field " + fa->name + " in " +
                             scp->type->print());
}

void *Resolver::visitLiteral(Literal *lit, void *arg) {
    auto *res = new RType;
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

bool isSame(Type *t1, Type *t2) { return t1->print() == t2->print(); }

bool isSame(RType *rt1, RType *rt2) {
    Type *t1 = rt1->type;
    Type *t2 = rt2->type;
    return t1->print() == t2->print();
}

bool subType(Type *type, Type *sub) {
    if (dynamic_cast<IncompleteType *>(type)) return true;
    if (type->print() == sub->print()) return true;
    if (type->isVoid()) return false;
    if (type->isArray()) return false;
    if (type->isPrim()) {
        if (!sub->isPrim()) return false;
        std::map<std::string, int> sizeMap{
                {"byte", 1},
                {"char", 2},
                {"short", 2},
                {"int", 4},
                {"long", 8},
                {"float", 4},
                {"double", 8}};
        if (type->name == "bool") return false;
        // auto cast to larger size
        if (sizeMap[type->name] <= sizeMap[sub->name]) {
            return true;
        } else {
            return false;
        }
    }
    // upcast
    throw std::runtime_error("subtype " + type->print() + " sub: " + sub->print());
}

bool isSame(Resolver *r, MethodCall *mc, Method *m) {
    if (mc->name != m->name) return false;
    if (mc->args.size() != m->params.size()) return false;
    for (int i = 0; i < mc->args.size(); i++) {
        auto *t1 = (RType *) mc->args[i]->accept(r, mc);
        auto *t2 = (RType *) m->params[i]->accept(r, nullptr);
        if (t1->type == nullptr) continue;// to be inferred
        if (!subType(t1->type, t2->type)) return false;
    }
    return true;
}

bool isSame1(MethodCall *mc, Method *m) {
    if (mc->name != m->name) return false;
    if (mc->args.size() != m->params.size()) return false;
    return true;
}

std::string toPath(Name *nm) {
    if (nm->isSimple()) {
        return dynamic_cast<SimpleName *>(nm)->name;
    } else {
        auto q = dynamic_cast<QName *>(nm);
        return toPath(q->scope) + "/" + q->name;
    }
}

Resolver *Resolver::getResolver(const std::string &path) {
    auto it = resolverMap.find(path);
    if (it != resolverMap.end()) return (*it).second;
    Lexer lexer(path);
    Parser parser(lexer);
    Unit *u = parser.parseUnit();
    u->path = path;
    auto r = new Resolver(u);
    //r->resolveAll();
    resolverMap[path] = r;
    return r;
}

void imports(std::string &name, std::vector<Symbol> &res, Resolver *r) {
    for (ImportStmt *is : r->unit->imports) {
        if (is->normal) {
            if (is->normal->path->isSimple()) {
                auto s = dynamic_cast<SimpleName *>(is->normal->path);
                if (s->name == name) res.push_back(Symbol(is, r));
            } else {
                auto *q = dynamic_cast<QName *>(is->normal->path);
                if (q->name == name) res.push_back(Symbol(is, r));
            }
        } else {
            throw std::runtime_error("import2");
        }
    }
}

std::vector<Symbol> Resolver::find(std::string &name, bool checkOthers) {
    std::vector<Symbol> res;
    for (auto bd : unit->types) {
        if (bd->name == name) res.push_back(Symbol(bd, this));
    }
    for (auto m : unit->methods) {
        if (m->name == name) res.push_back(Symbol(m, this));
    }
    // for local variable
    local(name, res);
    // method parameter
    param(name, res);
    // class fields
    field(name, res);
    // class methods
    method(name, res);
    imports(name, res, this);
    if (checkOthers) other(name, res);
    return res;
}

void Resolver::other(std::string name, std::vector<Symbol> &res) const {
    for (auto *is : unit->imports) {
        if (is->normal) {
            auto *r = getResolver(root + "/" + toPath(is->normal->path));
            r->fromOther = true;
            auto arr = r->find(name, false);
            r->fromOther = false;
            res.insert(res.end(), arr.begin(), arr.end());
        } else {
            throw std::runtime_error("import2");
        }
    }
}

std::vector<std::string> split(Name *path) {
    std::list<std::string> res;
    while (true) {
        if (path->isSimple()) {
            res.push_front(path->print());
            break;
        } else {
            auto *q = dynamic_cast<QName *>(path);
            res.push_front(q->name);
            path = q->scope;
        }
    }
    return {res.begin(), res.end()};
}

std::pair<std::string, Name *> split2(Name *name) {
    auto arr = split(name);
    auto *cur = (Name *) new SimpleName(arr[1]);
    for (int i = 2; i < arr.size(); i++) {
        cur = new QName(cur, arr[i]);
    }
    return std::make_pair(arr[0], cur);
}

/*RType* isImport(Name* name, std::vector<Symbol> res, Resolver* r){
    auto arr = split(name);
    for(auto imp : r->unit->imports){
        if(imp->normal){
            auto p = imp->normal->path;
            int pos = 0;
            if(arr[pos++] == p->name){
                Resolver* otherr = getResolver(toPath(p));
                auto rest = split2(name);
                return res->accept(otherr, nullptr);
            }
        }else{
            throw std::string("import2");
        }
    }
}*/

RType *scopedMethod(MethodCall *mc, Resolver *r) {
    //    auto *scp = (RType *) mc->scope->accept(r, mc);
    //    if (!scp->arr.empty()) {
    //        for (auto s : scp->arr) {
    //            if (s.imp) {
    //                auto *re = r->getResolver(s.imp->normal->path->print());
    //                auto arr = re->find(mc->name, false);
    //            }
    //        }
    //    }
    throw std::runtime_error("scopedMethod");
}

void *Resolver::visitMethodCall(MethodCall *mc, void *arg) {
    std::cout << "visitMethodCall " << mc->name << "\n";
    if (mc->scope) {
        return scopedMethod(mc, this);
    }
    Type *target = nullptr;
    std::vector<Type *> list;  // candidates
    std::vector<Method *> cand;// candidates
    for (auto m : unit->methods) {
        if (m->name == mc->name) {
            cand.push_back(m);
        }
    }
    if (curDecl) {
        for (auto m : curDecl->methods) {
            if (m->name == mc->name) {
                cand.push_back(m);
            }
        }
    }
    if (cand.empty()) {
        throw std::runtime_error("method:  " + mc->name + " not found");
    }
    //filter
    std::vector<Method *> real;
    for (auto c : cand) {
        if (isSame(this, mc, c)) {
            real.push_back(c);
        }
    }
    if (real.size() == 1) {
        return real[0]->accept(this, arg);
    }
    if (real.empty()) {
        //print cand
        throw std::runtime_error("method: " + mc->name + " not found from candidates: ");
    }
    throw std::runtime_error("method:  " + mc->name + " has " +
                             std::to_string(list.size()) + " candidates");
}

RType *inferType(Block *b, Resolver *r) {
    for (auto st : b->list) {
        st->accept(r, nullptr);
        auto ret = dynamic_cast<ReturnStmt *>(st);
        if (ret) {
            if (ret->expr) {
                return (RType *) ret->expr->accept(r, nullptr);
            }
        }
    }
    return makeSimple("void");
}

void *Resolver::visitObjExpr(ObjExpr *o, void *arg) {
    for (auto &e : o->entries) {
        e.value->accept(this, nullptr);
    }
    return resolveType(o->type);
}

void *Resolver::visitArrayCreation(ArrayCreation *ac, void *arg) {
    for (auto &e : ac->dims) {
        e->accept(this, nullptr);
    }
    return ac->type->accept(this, nullptr);
}

void *Resolver::visitAsExpr(AsExpr *as, void *arg) {
    //auto left = (RType *) as->expr->accept(this, nullptr);
    auto right = (RType *) as->type->accept(this, nullptr);
    return right;
}

void *Resolver::visitRefExpr(RefExpr *as, void *arg) {
    auto inner = (RType *) as->expr->accept(this, arg);
    auto type = new PointerType{};
    type->type = inner->type;
    inner->type = type;
    return inner;
}

void *Resolver::visitDerefExpr(DerefExpr *as, void *arg) {
    auto inner = (RType *) as->expr->accept(this, arg);
    auto ptr = dynamic_cast<PointerType *>(inner->type);
    return ptr->type;
    ;
}
