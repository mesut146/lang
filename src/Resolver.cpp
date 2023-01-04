#include <iostream>
#include <list>

#include "Resolver.h"
#include "parser/Parser.h"
#include "parser/Util.h"

int Resolver::findVariant(EnumDecl *decl, const std::string &name) {
    for (int i = 0; i < decl->variants.size(); i++) {
        if (decl->variants[i]->name == name) {
            return i;
        }
    }
    throw std::runtime_error("unknown variant: " + name + " of type " + decl->name);
}

bool isSigned(const std::string &s) {
    return s == "u8" || s == "u16" ||
           s == "u32" || s == "u64";
}
void Scope::add(VarHolder *f) { list.push_back(f); }

void Scope::clear() { list.clear(); }

std::string nameOf(VarHolder *vh) {
    auto f = std::get_if<Fragment *>(vh);
    if (f) return (*f)->name;
    auto p = std::get_if<Param *>(vh);
    if (p) return (*p)->name;
    auto fd = std::get_if<FieldDecl *>(vh);
    if (fd) return (*fd)->name;
    auto ep = std::get_if<EnumPrm *>(vh);
    if (ep) return (*ep)->name;
    return "#none#";
}

VarHolder *Scope::find(const std::string &name) {
    for (auto vh : list) {
        auto f = std::get_if<Fragment *>(vh);
        if (f && (*f)->name == name) return vh;
        auto p = std::get_if<Param *>(vh);
        if (p && (*p)->name == name) return vh;
        auto fd = std::get_if<FieldDecl *>(vh);
        if (fd && (*fd)->name == name) return vh;
        auto ep = std::get_if<EnumPrm *>(vh);
        if (ep && (*ep)->name == name) return vh;
    }
    return nullptr;
}

std::map<std::string, Resolver *> Resolver::resolverMap;

Resolver::Resolver(Unit *unit) : unit(unit) {}
Resolver::~Resolver() = default;

Type *clone(Type *type) {
    auto ptr = dynamic_cast<PointerType *>(type);
    if (ptr) {
        auto res = new PointerType;
        res->type = clone(ptr->type);
        return res;
    } else {
        auto res = new Type;
        if (type->scope) {
            res->scope = clone(type->scope);
        }
        res->name = type->name;
        res->dims.insert(res->dims.end(), type->dims.begin(), type->dims.end());
        res->typeArgs.insert(res->typeArgs.end(), type->typeArgs.begin(), type->typeArgs.end());
        return res;
    }
}

RType *clone(RType *rt) {
    auto res = new RType;
    res->type = clone(rt->type);
    res->unit = rt->unit;
    res->targetDecl = rt->targetDecl;
    res->targetMethod = rt->targetMethod;
    res->targetVar = rt->targetVar;
    return res;
}

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
    for (auto scope : scopes) {
        for (auto vh : scope->list) {
            std::cout << "scope var :" << nameOf(vh) << std::endl;
        }
    }
    for (auto f : varMap) {
        std::cout << "var: " << f.first->name << " = "
                  << f.second->type->print() << std::endl;
    }
    /*for(auto &p : fieldMap){
      std::cout << "field: " << p.first->name << " = " <<
    p.second->type->print() << "\n";
    }*/
    for (auto &p : methodMap) {
        std::cout << "method: " << p.first->name << " = "
                  << p.second->type->print() << std::endl;
        for (auto *prm : p.first->params) {
            std::cout << "param: " << prm->name << " = "
                      << paramMap[prm]->type->print() << std::endl;
        }
    }
}
void Resolver::newScope() {
    scopes.push_back(std::make_shared<Scope>());
}

void Resolver::dropScope() {
    curScope()->clear();
    scopes.pop_back();
}

std::shared_ptr<Scope> Resolver::curScope() {
    return scopes.back();
}

void Resolver::resolveAll() {
    init();
    for (auto *st : unit->stmts) {
        st->accept(this, nullptr);
    }
    for (auto *m : unit->methods) {
        visitMethod(m, nullptr);
    }
    for (auto *bd : unit->types) {
        newScope();
        visitBaseDecl(bd, nullptr);
        for (auto m : bd->methods) {
            visitMethod(m, nullptr);
        }
        dropScope();
    }
    //dump();
}

void Resolver::init() {
    for (auto bd : unit->types) {
        auto *res = makeSimple(bd->name);
        res->unit = unit;
        res->targetDecl = bd;
        typeMap[bd->name] = res;
    }
    newScope();//globals
}

RType *Resolver::resolveScoped(Expression *expr) {
    return (RType *) expr->accept(this, nullptr);
}

void *Resolver::visitBaseDecl(BaseDecl *bd, void *arg) {
    if (bd->isEnum) {
        auto en = dynamic_cast<EnumDecl *>(bd);
        for (auto ev : en->variants) {
            for (auto ep : ev->params) {
                ep->type->accept(this, nullptr);
            }
        }
    } else {
        auto td = dynamic_cast<TypeDecl *>(bd);
        for (auto fd : td->fields) {
            fd->accept(this, nullptr);
        }
    }
    return typeMap[bd->name];
}

void *Resolver::visitFieldDecl(FieldDecl *fd, void *arg) {
    auto res = fd->type->accept(this, nullptr);
    //if(fd->expr) fd->expr->accept (this, nullptr);
    return res;
}

void *Resolver::visitMethod(Method *m, void *arg) {
    auto it = methodMap.find(m);
    if (it != methodMap.end()) return it->second;
    curMethod = m;
    auto *res = clone((RType *) m->type->accept(this, m));
    res->targetMethod = m;
    newScope();
    for (auto *prm : m->params) {
        curScope()->add(new VarHolder(prm));
        prm->accept(this, nullptr);
    }
    if (m->body) {
        m->body->accept(this, nullptr);
    }
    dropScope();
    methodMap[m] = res;
    curMethod = nullptr;
    return res;
}

void *Resolver::visitParam(Param *p, void *arg) {
    auto res = clone(resolveType(p->type));
    paramMap[p] = res;
    return res;
}

void *Resolver::visitAssign(Assign *as, void *arg) {
    auto *t1 = (RType *) as->left->accept(this, as);
    auto *t2 = (RType *) as->right->accept(this, as);
    // return t1 because t2 is going to be autocast to t1 ultimately
    return t1;
}

RType *bin(std::string &s1, std::string &s2) {
    if (s1 == s2) {
        return makeSimple(s1);
    }
    if (s1 == "double" || s2 == "double") return makeSimple("double");
    if (s1 == "float" || s2 == "float") return makeSimple("float");
    if (s1 == "long" || s2 == "long") return makeSimple("long");
    if (s1 == "int" || s2 == "int") return makeSimple("int");
    if (s1 == "byte" || s2 == "byte") return makeSimple("byte");
    throw std::runtime_error("bin");
}

void *Resolver::visitInfix(Infix *infix, void *arg) {
    auto it = exprMap.find(infix);
    if (it != exprMap.end()) return it->second;
    std::cout << "visitInfix = " << infix->print() << std::endl;
    if (infix->print() == "x < 5") {
        int x = 1 + 2;
    }
    auto *rt1 = (RType *) infix->left->accept(this, infix);
    auto *rt2 = (RType *) infix->right->accept(this, infix);
    if (!rt1->type) throw std::runtime_error("lhs null");
    if (!rt2->type) throw std::runtime_error("rhs null");
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
        auto res = bin(s1, s2);
        exprMap[infix] = res;
        return res;
    } else {
    }
    throw std::runtime_error("visitInfix: " + infix->print());
}

void *Resolver::visitUnary(Unary *u, void *arg) {
    auto it = exprMap.find(u);
    if (it != exprMap.end()) return it->second;
    //todo check unsigned
    auto res = resolveScoped(u->expr);
    exprMap[u] = res;
    return res;
}

void *Resolver::visitType(Type *type, void *arg) { return resolveType(type); }

RType *Resolver::resolveType(Type *type) {
    auto it = typeMap.find(type->print());
    if (it != typeMap.end()) return it->second;
    //std::cout << "resolveType: " << type->print() << "\n";
    RType *res = nullptr;
    if (type->isPrim() || type->isVoid()) {
        res = new RType;
        res->type = type;
    } else {
        auto ptr = dynamic_cast<PointerType *>(type);
        if (ptr) {
            res = clone(resolveType(ptr->type));
            auto inner = res->type;
            auto pt = new PointerType;
            pt->type = inner;
            res->type = pt;
        } else {
            if (type->scope == nullptr) {
                //todo is import
            } else {
                auto st = (RType *) type->scope->accept(this, nullptr);
                auto bd = st->targetDecl;
                if (bd->isEnum) {
                    auto ed = dynamic_cast<EnumDecl *>(bd);
                    bool found = false;
                    for (auto ev : ed->variants) {
                        if (ev->name == type->name) {
                            found = true;
                            res = (RType *) visitBaseDecl(ed, nullptr);
                        }
                    }
                }
            }
        }
    }
    if (!res) throw std::runtime_error("todo resolveType: " + type->print());
    typeMap[type->print()] = res;
    return res;
}

void *Resolver::visitFragment(Fragment *f, void *arg) {
    auto it = varMap.find(f);
    if (it != varMap.end()) return it->second;
    RType *res = nullptr;
    if (f->type) {
        res = (RType *) f->type->accept(this, nullptr);
    } else {
        int aa = 1 + 2;
    }
    if (f->rhs) {
        auto r = (RType *) f->rhs->accept(this, nullptr);
        if (!res) res = r;
    }

    if (!res) {
        throw std::runtime_error("fragment neither has type nor rhs");
    }
    res->targetVar = f;
    varMap[f] = res;
    curScope()->add(new VarHolder(f));
    return res;
}

void *Resolver::visitVarDeclExpr(VarDeclExpr *vd, void *arg) {
    for (auto *f : vd->list) {
        f->accept(this, arg);
    }
    return nullptr;
}

void *Resolver::visitVarDecl(VarDecl *vd, void *arg) {
    return visitVarDeclExpr(vd->decl, arg);
}

std::vector<Symbol> Resolver::find(std::string &name, bool checkOthers) {
    std::vector<Symbol> res;
    //params+locals+fields,globals
    for (int i = scopes.size() - 1; i >= 0; i--) {
        auto vh = scopes[i]->find(name);
        if (vh) {
            res.push_back(Symbol(vh, this));
        }
    }
    //imports(name, res, this);
    //if (checkOthers) other(name, res);
    return res;
}
void *Resolver::visitSimpleName(SimpleName *sn, void *arg) {
    auto arr = find(sn->name, true);
    if (arr.empty()) {
        dump();
        throw std::runtime_error("unknown identifier: " + sn->name);
    }
    if (arr.size() == 1) {
        auto s = arr[0];
        if (s.v) {
            auto frag = std::get_if<Fragment *>(s.v);
            if (frag) {
                return s.resolve(*frag);
            }
            auto prm = std::get_if<Param *>(s.v);
            if (prm) {
                return s.resolve(*prm);
            }
            auto field = std::get_if<FieldDecl *>(s.v);
            if (field) {
                return s.resolve(*field);
            }
            auto ep = std::get_if<EnumPrm *>(s.v);
            if (ep) {
                return s.resolve((*ep)->decl->type);
            }
        } else if (s.m) {
            return s.resolve(s.m);
        } else if (s.decl) {
            return s.resolve(s.decl);
        } else if (s.imp) {
            auto res = new RType;
            res->arr.push_back(s);
            return res;
        } else {
            throw std::runtime_error("unexpected state");
        }
    } else {
        auto res = new RType;
        res->arr = arr;
        return res;
        //throw std::string("more than 1 result for ") + sn->name;
    }
    throw std::runtime_error("unknown identifier: " + sn->name);
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
        if (fa->name == "index") {
            return makeSimple("int");
        }
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

bool subType(Type *type, Type *sub) {
    if (type->print() == sub->print()) return true;
    if (type->isVoid()) return false;
    if (type->isArray()) return false;
    if (type->isPrim()) {
        if (!sub->isPrim()) return false;
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
    for (auto *is : r->unit->imports) {
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
    auto it = exprMap.find(mc);
    if (it != exprMap.end()) return it->second;
    //std::cout << "visitMethodCall " << mc->name << "\n";
    if (mc->scope) {
        return scopedMethod(mc, this);
    }
    if (mc->name == "print") {
        return nullptr;
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
        auto res = (RType *) real[0]->accept(this, arg);
        exprMap[mc] = res;
        std::cout << "resolved call " << mc->name << "to: " << res->targetMethod->name << std::endl;
        return res;
    }
    if (real.empty()) {
        //print cand
        throw std::runtime_error("method: " + mc->name + " not found from candidates: ");
    }
    throw std::runtime_error("method:  " + mc->name + " has " +
                             std::to_string(list.size()) + " candidates");
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
    auto inner = clone((RType *) as->expr->accept(this, arg));
    auto type = new PointerType{};
    type->type = inner->type;
    inner->type = type;
    return inner;
}

void *Resolver::visitDerefExpr(DerefExpr *as, void *arg) {
    auto res = clone((RType *) as->expr->accept(this, arg));
    auto inner = res->type;
    auto ptr = dynamic_cast<PointerType *>(inner);
    if (!ptr) throw std::runtime_error("deref is not pointer: ");
    res->type = ptr->type;
    return res;
}

void *Resolver::visitAssertStmt(AssertStmt *as, void *arg) {
    as->expr->accept(this, nullptr);
    return nullptr;
}

void *Resolver::visitIfLetStmt(IfLetStmt *as, void *arg) {
    newScope();
    auto rt = (RType *) as->type->scope->accept(this, nullptr);
    auto decl = dynamic_cast<EnumDecl *>(rt->targetDecl);
    int index = findVariant(decl, as->type->name);
    auto variant = decl->variants[index];
    int i = 0;
    for (auto &name : as->args) {
        auto ep = variant->params[i];
        auto tmp = new EnumPrm;
        tmp->decl = ep;
        tmp->name = name;
        curScope()->add(new VarHolder(tmp));
        i++;
    }
    as->thenStmt->accept(this, nullptr);
    dropScope();
    if (as->elseStmt) {
        as->elseStmt->accept(this, nullptr);
    }
    return nullptr;
}

void *Resolver::visitParExpr(ParExpr *as, void *arg) {
    return as->expr->accept(this, nullptr);
}

void *Resolver::visitExprStmt(ExprStmt *as, void *arg) {
    as->expr->accept(this, nullptr);
    return nullptr;
}

void *Resolver::visitBlock(Block *as, void *arg) {
    for (auto st : as->list) {
        st->accept(this, nullptr);
    }
    return nullptr;
}

void *Resolver::visitIfStmt(IfStmt *is, void *arg) {
    is->expr->accept(this, nullptr);
    is->thenStmt->accept(this, nullptr);
    if (is->elseStmt) is->elseStmt->accept(this, nullptr);
    return nullptr;
}

void *Resolver::visitReturnStmt(ReturnStmt *as, void *arg) {
    if (as->expr) as->expr->accept(this, nullptr);
    return nullptr;
}

void *Resolver::visitIsExpr(IsExpr *ie, void *arg) {
    auto rt = resolveScoped(ie->expr);
    auto decl1 = rt->targetDecl;
    if (!decl1->isEnum) {
        throw std::runtime_error("is expr must have enum operand");
    }
    auto rt2 = resolveScoped(ie->type->scope);
    auto decl2 = rt2->targetDecl;
    if (decl1 != decl2) {
        throw std::runtime_error("is expr has icompatible operands");
    }
    return makeSimple("bool");
}