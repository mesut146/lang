#include "Resolver.h"
#include "TypeUtils.h"
#include "parser/Ast.h"

//Debug::debug(e, f)
Ptr<ExprStmt> makeDebug(std::shared_ptr<Unit> &unit, Expression *e, bool use_ref, const std::string &fmt) {
    auto mc = new MethodCall;
    mc->loc(++unit->lastLine);
    mc->is_static = true;
    mc->scope.reset(new Type("Debug"));
    mc->name = "debug";
    if (use_ref) {
        e = new RefExpr(std::unique_ptr<Expression>(e));
        e->loc(0);
    }
    mc->args.push_back(e);
    mc->args.push_back((new SimpleName(fmt))->loc(0));
    auto res = std::make_unique<ExprStmt>(mc);
    res->line = unit->lastLine;
    return res;
}

FieldAccess *makeFa(const std::string &scope, const std::string &name) {
    auto fa = new FieldAccess;
    fa->scope = (new SimpleName(scope))->loc(0);
    fa->name = name;
    fa->loc(0);
    return fa;
}

//Drop::drop(expr)
std::unique_ptr<Statement> newDrop2(Expression *expr, Unit *unit) {
    auto mc = new MethodCall;
    mc->loc(++unit->lastLine);
    mc->is_static = true;
    mc->scope.reset(new Type("Drop"));
    mc->name = "drop";
    mc->args.push_back(expr);
    auto res = std::make_unique<ExprStmt>(mc);
    res->line = unit->lastLine;
    return res;
}

//Drop::drop({scope.fd});
std::unique_ptr<Statement> newDrop(const std::string &scope, const std::string &field, Unit *unit) {
    auto fa = new FieldAccess;
    fa->loc(++unit->lastLine);
    fa->scope = (new SimpleName(scope))->loc(fa->line);
    fa->name = field;
    return newDrop2(fa, unit);
}
//Drop::drop({fd.name});
std::unique_ptr<Statement> newDrop(const std::string &field, Unit *unit) {
    auto arg = new SimpleName(field);
    arg->loc(++unit->lastLine);
    return newDrop2(arg, unit);
}


MethodCall *newStr(std::shared_ptr<Unit> &unit, const std::string &name) {
    auto mc = new MethodCall;
    mc->is_static = true;
    mc->line = unit->lastLine;
    mc->scope.reset(new Type("String"));
    mc->name = "new";
    if (!name.empty()) {
        auto lit = new Literal(Literal::STR, "\"" + name + "\"");
        lit->line = unit->lastLine;
        mc->args.push_back(lit);
    }
    return mc;
}
Ptr<ExprStmt> newPrint(std::shared_ptr<Unit> &unit, const std::string &scope, Expression *e) {
    auto mc = new MethodCall;
    mc->line = unit->lastLine;
    mc->scope.reset(new SimpleName(scope));
    mc->name = "print";
    mc->args.push_back(e);
    auto res = std::make_unique<ExprStmt>(mc);
    res->line = unit->lastLine;
    return res;
}
//scope.print(str);
Ptr<ExprStmt> newPrint(std::shared_ptr<Unit> &unit, const std::string &scope, const std::string &str) {
    auto mc = new MethodCall;
    mc->loc(unit->lastLine);
    mc->scope.reset((new SimpleName(scope))->loc(0));
    mc->name = "print";
    auto lit = new Literal(Literal::STR, "\"" + str + "\"");
    lit->loc(unit->lastLine);
    mc->args.push_back(lit);
    auto res = std::make_unique<ExprStmt>(mc);
    res->line = unit->lastLine;
    return res;
}

Ptr<ReturnStmt> makeRet(std::shared_ptr<Unit> unit, Expression *e) {
    auto ret = std::make_unique<ReturnStmt>();
    ret->line = ++unit->lastLine;
    ret->expr.reset(e);
    return ret;
}

bool need_drop(const Type &type) {
    if (type.isPointer()) return false;
    if (type.isPrim()) return false;
    return type.print() != "str";
}

Method Resolver::derive_drop_method(BaseDecl *bd) {
    if (bd->type.name == "List") {
        throw std::runtime_error("derive drop list");
    }
    int line = unit->lastLine;
    Method m(unit->path);
    m.name = "drop";
    Param slf("self", clone(bd->type));
    slf.loc(line);
    slf.is_deref = true;
    m.self = std::move(slf);
    m.type = Type("void");
    auto bl = new Block;
    m.body.reset(bl);

    if (bd->isEnum()) {
        auto ed = (EnumDecl *) bd;
        IfLetStmt *last_iflet = nullptr;
        for (int i = 0; i < ed->variants.size(); i++) {
            auto &ev = ed->variants[i];
            auto ifs = std::make_unique<IfLetStmt>();
            ifs->loc(line);
            ifs->type = Type(clone(bd->type), ev.name);
            for (auto &fd : ev.fields) {
                //todo make this ptr
                auto arg = ArgBind(fd.name, false);
                arg.loc(line);
                ifs->args.push_back(arg);
            }
            ifs->rhs.reset((new SimpleName("self"))->loc(line));
            auto then = new Block;
            ifs->thenStmt.reset(then);
            for (auto &fd : ev.fields) {
                if (!need_drop(fd.type)) continue;
                //Drop::drop(fd)
                then->list.push_back(newDrop(fd.name, unit.get()));
            }
            if (last_iflet == nullptr) {
                bl->list.push_back(std::move(ifs));
                last_iflet = (IfLetStmt *) bl->list.back().get();
            } else {
                last_iflet->elseStmt = std::move(ifs);
                last_iflet = (IfLetStmt *) last_iflet->elseStmt.get();
            }
        }
        //print("derive drop enum " + bd->type.print());
        //print(m.print());
    } else {
        auto sd = (StructDecl *) bd;
        for (auto &fd : sd->fields) {
            if (!need_drop(fd.type)) continue;
            //Drop::drop(self.fd);
            bl->list.push_back(newDrop("self", fd.name, unit.get()));
        }
    }
    m.parent = Parent{Parent::IMPL, bd->type, Type("Drop")};
    if (bd->isGeneric) {
        m.parent.type_params = bd->type.typeArgs;
    }
    m.isGeneric = bd->isGeneric;
    return m;
}

std::unique_ptr<Impl> Resolver::derive_drop(BaseDecl *bd) {
    if (bd->type.name == "List") {
        throw std::runtime_error("derive drop list");
    }
    auto imp = std::make_unique<Impl>(bd->type);
    imp->trait_name = Type("Drop");
    if (bd->isGeneric) {
        imp->type_params = bd->type.typeArgs;
    }
    imp->methods.push_back(derive_drop_method(bd));
    // auto tr = resolve(Type("Drop")).trait;
    // for (auto &mm : tr->methods) {
    //     if (mm.body) {
    //         AstCopier copier;
    //         auto m2 = std::any_cast<Method *>(mm.accept(&copier));
    //         imp->methods.push_back(std::move(*m2));
    //     }
    // }
    return imp;
}

std::unique_ptr<Impl> Resolver::derive_debug(BaseDecl *bd) {
    int line = unit->lastLine;
    Method m(unit->path);
    m.name = "debug";
    Param s("self", clone(bd->type).toPtr());
    m.self = std::move(s);
    m.type = Type("void");
    Param fp("f", Type(Type::Pointer, Type("Fmt")));
    m.params.push_back(std::move(fp));
    auto bl = new Block;
    m.body.reset(bl);
    if (bd->isEnum()) {
        auto ed = (EnumDecl *) bd;
        for (int i = 0; i < ed->variants.size(); i++) {
            auto &ev = ed->variants[i];
            auto ifs = std::make_unique<IfLetStmt>();
            ifs->line = line;
            ifs->id = ++Node::last_id;
            ifs->type = (Type(clone(bd->type), ev.name));
            bool is_ptr = true;
            for (auto &fd : ev.fields) {
                //todo make this ptr
                ifs->args.push_back(ArgBind(fd.name, is_ptr));
            }
            ifs->rhs.reset((new SimpleName("self"))->loc(0));
            auto then = new Block;
            ifs->thenStmt.reset(then);
            then->list.push_back(newPrint(unit, "f", bd->type.print() + "::" + ev.name));
            if (!ev.fields.empty()) {
                then->list.push_back(newPrint(unit, "f", "{"));
                int j = 0;
                for (auto &fd : ev.fields) {
                    if (fd.type.isPointer()) continue;
                    if (j++ > 0) then->list.push_back(newPrint(unit, "f", ", "));
                    then->list.push_back(newPrint(unit, "f", fd.name + ": "));
                    then->list.push_back(makeDebug(unit, (new SimpleName(fd.name))->loc(0), false, "f"));
                }
                then->list.push_back(newPrint(unit, "f", "}"));
            }
            bl->list.push_back(std::move(ifs));
        }
    } else {
        auto sd = (StructDecl *) bd;
        bl->list.push_back(newPrint(unit, "f", sd->type.name + "{"));
        int i = 0;
        for (auto &fd : sd->fields) {
            if (fd.type.isPointer()) continue;
            bl->list.push_back(newPrint(unit, "f", (i > 0 ? ", " : "") + fd.name + ": "));
            //auto ts = fd.type.print();
            bl->list.push_back(makeDebug(unit, makeFa("self", fd.name), true, "f"));
            i++;
        }
        bl->list.push_back(newPrint(unit, "f", "}"));
    }
    auto imp = std::make_unique<Impl>(bd->type);
    imp->trait_name = Type("Debug");
    imp->type_params = bd->type.typeArgs;
    //m.parent = imp.get();
    m.parent = Parent{Parent::IMPL, imp->type, imp->trait_name};
    imp->methods.push_back(std::move(m));
    auto tr = resolve(Type("Debug")).trait;
    for (auto &mm : tr->methods) {
        if (mm.body) {
            AstCopier copier;
            auto m2 = std::any_cast<Method *>(mm.accept(&copier));
            imp->methods.push_back(std::move(*m2));
        }
    }
    return imp;
}

void generate_format(MethodCall *mc, Resolver *r) {
    if (mc->args.empty()) {
        r->err(mc, "format no arg");
    }
    auto fmt = mc->args.at(0);
    auto &fmt_str = dynamic_cast<Literal *>(fmt)->val;
    if (!isStrLit(fmt)) {
        r->err(mc, "format arg not str literal");
    }
    FormatInfo info(SimpleName("_f"));
    info.ret.loc(mc->line);
    Block block;
    //let f = Fmt::new();
    auto vd = std::make_unique<VarDecl>();
    vd->loc(mc->line);
    Fragment frag;
    frag.loc(mc->line);
    frag.name = "_f";
    frag.type = Type("Fmt");
    auto rhs = new MethodCall;
    rhs->loc(mc->line);
    rhs->is_static = true;
    rhs->scope.reset(new Type("Fmt"));
    rhs->name = "new";
    frag.rhs.reset(rhs);
    //r->addScope(frag.name, frag.type.value(), false, frag.line, frag.id);
    vd->decl = new VarDeclExpr;
    vd->decl->list.push_back(std::move(frag));
    block.list.push_back(std::move(vd));
    SimpleName f("_f");
    f.loc(mc->line);
    int i = 0;
    int idx = 1;
    while (i < fmt_str.size()) {
        int pos = fmt_str.find("{}", i);
        if (pos > i) {
            auto sub = fmt_str.substr(i, pos - i);
            auto sub_mc = new MethodCall;
            sub_mc->loc(mc->line);
            sub_mc->scope.reset(new SimpleName("_f"));
            sub_mc->scope->loc(mc->line);
            sub_mc->name = "print";
            sub_mc->args.push_back((new Literal(Literal::STR, sub))->loc(mc->line));
            //r->resolve(sub_mc);
            auto sub_stmt = std::make_unique<ExprStmt>(sub_mc);
            sub_stmt->loc(mc->line),
            block.list.push_back(std::move(sub_stmt));
            i = pos + 2;
        }
        if (pos == std::string::npos) {
            break;
        }
        auto arg = mc->args.at(idx);
        ++idx;
        auto arg_debug_mc = new MethodCall;
        arg_debug_mc->loc(mc->line);
        arg_debug_mc->name = "debug";
        arg_debug_mc->scope.reset(arg);
        //todo lifetime of f?
        auto ref = new RefExpr(std::make_unique<SimpleName>(f));
        ref->loc(mc->line);
        arg_debug_mc->args.push_back(ref);
        /*auto mc_rt = r->resolve(arg_debug_mc);
        if (!mc_rt.targetMethod) {
            r->err(arg_debug_mc, "no debug method");
        }*/
        //arg_debug_mc->scope.release();
        auto debug_stmt = std::make_unique<ExprStmt>(arg_debug_mc);
        debug_stmt->loc(mc->line);
        block.list.push_back(std::move(debug_stmt));
    }
    info.ret_mc.loc(mc->line);
    info.ret_mc.scope.reset(new SimpleName("_f"));
    info.ret_mc.scope->loc(mc->line);
    info.ret_mc.name = "unwrap";
    block.accept(r);
    r->resolve(&info.ret_mc);
    print(block.print());
    print(info.ret_mc.print());
    info.block = std::move(block);
    r->format_map.insert({mc->id, std::move(info)});
}