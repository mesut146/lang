#include "MethodResolver.h"
#include "TypeUtils.h"
#include "parser/Util.h"

std::string printSig(Signature& sig){
    std::string s;
    std::optional<RType> sc;
    if(sig.mc&&sig.mc->scope){
      s+=sig.scope->print();
      s+="::";
    }
    else if(sig.m){
        auto p=sig.m->parent;
        if(p){
            auto imp=(Impl*)p;
            s+=imp->type->print();
            s+="::";
        }
    }
    if(sig.mc)
      s+=sig.mc->name;
    else s+=sig.m->name;
    s+="(";
    int i=0;
    for(auto &a:sig.args){
        if(i++>0) s+=",";
        s+=a->print();
    }
    s+=")";
    return s;
}

    Signature Signature::make(MethodCall* mc, Resolver* r){
        Signature res;
        res.mc=mc;
        if(mc->scope){
            res.scope = r->getType(mc->scope.get());
            if(!dynamic_cast<Type*>(mc->scope.get())){
                res.args.push_back(res.scope);
            }
        }
        for(auto a:mc->args){
            res.args.push_back(r->getType(a));
        }
        return res;
    }
    Signature Signature::make(Method* m, Resolver* r){
        Signature res;
        res.m=m;
        if(m->self){
            res.args.push_back(m->self->type.get());
        }
        for(auto &prm:m->params){
            res.args.push_back(prm->type.get());
        }
        return res;
    }
    

std::vector<Signature> MethodResolver::collect(Signature &sig){
  std::vector<Signature> list;
  auto mc = sig.mc;
  if(mc->scope){
      getMethods(sig.scope, mc->name, list, true);
  }else{
      r->findMethod(mc->name, list);
    for (auto is : r->unit->imports) {
        auto resolver = Resolver::getResolver(r->root + "/" + join(is->list, "/") + ".x", r->root);
        resolver->resolveAll();
        resolver->findMethod(mc->name, list);
    }
  }
  return list;
}

bool isGeneric(Type *type, std::vector<Type *> &typeParams) {
        if (type->scope) error("isGeneric::scope");
        if (type->typeArgs.empty()) {
            for (auto &t : typeParams) {
                if (t->print() == type->print()) return true;
            }
        } else {
            for (auto ta : type->typeArgs) {
                if (isGeneric(ta, typeParams)) return true;
            }
        }
        return false;
    }

void Resolver::findMethod(std::string &name, std::vector<Signature> &list) {
    for (auto &item : unit->items) {
        if (item->isMethod()) {
            auto m = dynamic_cast<Method *>(item.get());
            if (m->name == name) {
                list.push_back(Signature::make(m, this));
            }
        }else if(item->isExtern()){
            auto ex = dynamic_cast<Extern *>(item.get());
            for(auto &m:ex->methods){
                if (m->name == name) { list.push_back(Signature::make(m.get(), this)); }
             }
        }
    }
    if (curImpl) {
        //sibling
        for (auto &m : curImpl->methods) {
            if (!m->self && m->name == name) {
                list.push_back(Signature::make(m.get(), this));
            }
        }
    }
}

void MethodResolver::getMethods(Type *type, std::string &name, std::vector<Signature> &list, bool imports) {
    if (type->isPointer()) {
        auto ptr = dynamic_cast<PointerType *>(type);
        type = ptr->type;
    }
    for (auto &item : r->unit->items) {
        if (!item->isImpl()) {
            continue;
            }
            auto impl = dynamic_cast<Impl *>(item.get());
            if (impl->type->name != type->name) continue;
            if (!impl->type->typeArgs.empty()) {
                //todo move this
                r->resolve(type);
            }
            for (auto &m : impl->methods) {
                //todo generate if generic
                if (m->name != name){
                    continue;
                }
                    if(type->typeArgs.empty()){
                        
                        list.push_back(Signature::make(m.get(), r));
                    }else{
                        std::map<std::string, Type *> typeMap;
                        for(int i=0;i<m->typeArgs.size();i++){
                            auto ta = m->typeArgs[i];
                            typeMap[ta->name]=type->typeArgs[i];
                        }
                        Generator gen(typeMap);
                        auto sig=Signature::make(m.get(), r);
                        for(auto &a:sig.args){
                            a=(Type*)std::any_cast<Expression*>(a->accept(&gen));
                        }
                        list.push_back(sig);
                        
                    }
                    
            }
    }
    if(imports){
    for (auto is : r->unit->imports) {
        auto resolver = Resolver::getResolver(r->root + "/" + join(is->list, "/") + ".x", r->root);
        
        resolver->resolveAll();
        MethodResolver mr(resolver.get());
        mr.getMethods(type, name, list, false);
    }
    }
}

void MethodResolver::infer(Type *arg, Type *prm, std::map<std::string, Type *> &typeMap) {
    auto it = typeMap.find(prm->name);
    if (prm->typeArgs.empty()) {
        if (it != typeMap.end()) {
            if (it->second == nullptr) {
                it->second = arg;
            } else {
                std::vector<Type *> tmp;
                if (!MethodResolver::isCompatible(it->second, arg, tmp)) {
                    error("type infer failed: " + it->second->print() + " vs " + arg->print());
                }
            }
        }
    } else {
        if (arg->typeArgs.size() != prm->typeArgs.size()) {
            error("type arg size mismatch, " + arg->print() + " = " + prm->print());
        }
        if (arg->name != prm->name) error("cant infer");
        for (int i = 0; i < arg->typeArgs.size(); i++) {
            auto ta = arg->typeArgs[i];
            auto tp = prm->typeArgs[i];
            infer(ta, tp, typeMap);
        }
    }
}


RType Resolver::handleCallResult(std::vector<Signature > &list, Signature *sig) {
    auto mc = sig->mc;
    if (list.empty()) {
        error("no such method: " + printSig(*sig));
    }
    std::vector<Signature> real;
    MethodResolver mr(this);
    std::map<Method *, std::string> errors;
    for (auto &sig2 : list) {
        auto msg = mr.isSame(*sig, sig2);
        if (!msg) {
            real.push_back(sig2);
        } else {
            errors[sig2.m] = msg.value();
        }
    }
    if (real.empty()) {
        std::string s = "method: " + mc->print() + " not found from candidates:\n ";
        for (auto &[m, err] : errors) {
            s += printMethod(m) + " " + err + "\n";
        }
        error(s);
    }

    if (real.size() > 1) {
        std::string s;
        for (auto m : real) {
            s += printSig(m) + "\n";
        }
        error("method:  " + mc->print()+"\n"+printSig(*sig) + " has " +
              std::to_string(real.size()) + " candidates;\n" + s);
    }
    auto &sig2=real[0];
    auto target = sig2.m;
    if (target->isGeneric) {
        std::map<std::string, Type *> typeMap;
        if (mc->typeArgs.empty()) {
            //infer
            for (auto ta : target->typeArgs) {
                typeMap[ta->name] = nullptr;
            }
            if (mc->scope) {
                auto scope = sig->scope;
                for (int i = 0; i < scope->typeArgs.size(); i++) {
                    typeMap[target->typeArgs[i]->name] = scope->typeArgs[i];
                }
            }
            for (int i = 0; i < sig->args.size(); i++) {
                auto arg_type = sig->args[i];
                auto target_type = sig2.args[i];
                MethodResolver::infer(arg_type, target_type, typeMap);
            }
            for (auto &i : typeMap) {
                if (i.second == nullptr) {
                    error("can't infer type parameter: " + i.first);
                }
            }
        } else {
            if (mc->typeArgs.size() < target->typeArgs.size()) {
                error("not enough type args: " + mc->print());
            }
            //place specified type args
            for (int i = 0; i < mc->typeArgs.size(); i++) {
                auto argt = resolve(mc->typeArgs[i]);
                typeMap[target->typeArgs[i]->name] = argt.type;
            }
        }
        auto newMethod = mr.generateMethod(typeMap, target, *sig);
        target = newMethod;
    } else if (target->unit != unit.get()) {
        usedMethods.insert(target);
    }
    auto res = clone(resolve(target->type.get()));
    res.targetMethod = target;
    return res;
}

Method *MethodResolver::generateMethod(std::map<std::string, Type *> &map, Method *m, Signature &sig) {
    auto mc = sig.mc;
    for (auto gm : r->generatedMethods) {
        auto sig2=Signature::make(gm, r);
        if (!isSame(sig, sig2).has_value()) {
            return gm;
        }
    }
    auto gen = new Generator(map);
    auto res = std::any_cast<Method *>(gen->visitMethod(m));
    if (m->parent && m->parent->isImpl()) {
        auto impl = dynamic_cast<Impl *>(m->parent);
        auto newImpl = new Impl(clone(sig.scope));
        res->parent = newImpl;
    }
    r->generatedMethods.push_back(res);
    return res;
}

bool MethodResolver::isCompatible(Type *arg, Type *target, std::vector<Type *> &typeParams) {
    if (isGeneric(target, typeParams)) return true;
    if (arg->print() == target->print()) return true;
    if (arg->isPointer()) {
        if (!target->isPointer()) return false;
        auto p1 = dynamic_cast<PointerType *>(arg);
        auto p2 = dynamic_cast<PointerType *>(target);
        return isCompatible(p1->type, p2->type, typeParams);
    }
    if (arg->isSlice()) {
        if (!target->isSlice()) return false;
        auto p1 = dynamic_cast<SliceType *>(arg);
        auto p2 = dynamic_cast<SliceType *>(target);
        return isCompatible(p1->type, p2->type, typeParams);
    }
    if (arg->isArray()) {
        if (!target->isArray()) return false;
        auto p1 = dynamic_cast<ArrayType *>(arg);
        auto p2 = dynamic_cast<ArrayType *>(target);
        return isCompatible(p1->type, p2->type, typeParams);
    }
    if (arg->isPrim()) {
        if (!target->isPrim()) return false;
        if (arg->print() == "bool" || target->print() == "bool") return false;
        // auto cast to larger size
        return sizeMap[arg->name] <= sizeMap[target->name];
    }
    return false;
}

std::optional<std::string> MethodResolver::isSame(Signature &sig, Signature &sig2) {
    auto mc=sig.mc;
    auto m=sig2.m;
    if (mc->name != m->name) return "";
    if (!m->typeArgs.empty()) {
        if (!mc->typeArgs.empty()) {
            //size mismatch
            if (mc->typeArgs.size() != m->typeArgs.size()) return "type arg size mismatched";
        }
        if (!m->isGeneric) {
            //check if args are compatible with generic type params
            for (int i = 0; i < mc->typeArgs.size(); i++) {
                if (mc->typeArgs[i]->print() != m->typeArgs[i]->print()) {
                    return "type arg " + mc->typeArgs[i]->print() + " not matched with " + m->typeArgs[i]->print();
                }
            }
        }
    }
    if (m->parent && m->parent->isImpl() && mc->scope) {
        auto impl = dynamic_cast<Impl *>(m->parent);
        if (!impl->isGeneric && !impl->type->typeArgs.empty()) {
            auto scope = sig.scope;
            //check they belong same impl
            for (int i = 0; i < scope->typeArgs.size(); i++) {
                if (scope->typeArgs[i]->print() != impl->type->typeArgs[i]->print()) return "not same impl";
            }
        }
    }
    //check if args are compatible with non generic params
    return checkArgs(sig, sig2);
}


std::optional<std::string> MethodResolver::checkArgs(Signature &sig, Signature& sig2) {
    if (sig2.m->self && !sig.mc->scope) {
        return "member method called without scope";
    }
    if (sig.args.size() != sig2.args.size()) return "arg size mismatched";
    auto typeParams = sig2.m->isGeneric ? sig2.m->typeArgs : std::vector<Type *>();
    for (int i = 0; i < sig.args.size(); i++) {
        auto t1 = sig.args[i];
        auto t2 = sig2.args[i];
        if (sig2.m->self && i == 0) {
            if (t1->isPointer()) {
                auto ptr = dynamic_cast<PointerType *>(t1);
                t1 = ptr->type;
            }
        }
        if (!isCompatible(t1, t2, typeParams)) {
            return "arg type " + t1->print() + " is not compatible with param " + t2->print();
        }
    }
    return {};
}
