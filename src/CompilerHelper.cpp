#include "Compiler.h"
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/LLVMContext.h>

std::string Cache::CACHE_FILE = "cache.txt";

void Cache::read_cache() {
    if (!Config::use_cache) return;
    auto path = fs::path(CACHE_FILE);
    if (!fs::exists(path)) {
        std::ofstream os(path.string());
        return;
    }
    std::fstream is(path.string());
    std::string line;
    while (std::getline(is, line)) {
        auto idx = line.find(",");
        auto file = line.substr(0, idx);
        auto time = line.substr(idx + 1);
        map[file] = time;
    }
}

void Cache::write_cache() {
    if (!Config::use_cache) return;
    auto path = fs::path(CACHE_FILE);
    std::ofstream os(path.string());
    for (auto &[f, t] : map) {
        os << f;
        os << "," << t << std::endl;
    }
    os.close();
}

bool Cache::need_compile(const fs::path &p, const std::string &out) {
    if (!Config::use_cache) {
        return true;
    }
    if (!fs::exists(fs::path(out))) {
        return true;
    }
    auto s = p.string();
    if (map.contains(s)) {
        auto &time2 = map[s];
        auto time1 = get_time(p);
        return time1 != time2;
    } else {
        return true;
    }
}

void sort(std::vector<BaseDecl *> &list, Resolver *r) {
    // for (auto decl : list) {
    //     std::cout << decl->type.print() << ", ";
    // }
    // std::cout << std::endl;
    bool swapped = false;
    do {
        swapped = false;
        for (int i = 0; i < list.size(); i++) {
            //find min that belongs to i'th index
            auto min = list[i];
            for (int j = i + 1; j < list.size(); j++) {
                auto &cur = list[j];
                if (r->isCyclic(min->type, cur)) {
                    //print("swap " + min->type.print() + " and " + cur->type.print());
                    min = cur;
                    std::swap(list[i], list[j]);
                    swapped = true;
                }
            }
        }
    } while (swapped);
}

std::vector<Method *> getMethods(Unit *unit) {
    std::vector<Method *> list;
    for (auto &item : unit->items) {
        if (item->isMethod()) {
            auto m = dynamic_cast<Method *>(item.get());
            if (m->typeArgs.empty()) {
                list.push_back(m);
            }
        } else if (item->isImpl()) {
            auto impl = dynamic_cast<Impl *>(item.get());
            if (!impl->type.typeArgs.empty()) { continue; }
            for (auto &m : impl->methods) {
                list.push_back(&m);
            }
        } else if (item->isExtern()) {
            auto ex = dynamic_cast<Extern *>(item.get());
            for (auto &m : ex->methods) {
                list.push_back(&m);
            }
        }
    }
    return list;
}

bool Compiler::doesAlloc(Expression *e) {
    auto obj = dynamic_cast<ObjExpr *>(e);
    if (obj) {
        return true;
    }
    auto aa = dynamic_cast<ArrayAccess *>(e);
    if (aa) {
        return aa->index2.get() != nullptr;
    }
    auto lit = dynamic_cast<Literal *>(e);
    if (lit) {
        return lit->type == Literal::STR;
    }
    auto mc = dynamic_cast<MethodCall *>(e);
    if (mc) {
        if (true || Config::rvo_ptr) {
            auto m = resolv->resolve(mc).targetMethod;
            return m && isRvo(m);
        }
        return false;
    }
    auto ty = dynamic_cast<Type *>(e);
    if (ty) {
        return true;
    }
    return dynamic_cast<ArrayExpr *>(e);
}

//llvm

llvm::ConstantInt *Compiler::makeInt(int val, int bits) {
    auto intType = llvm::IntegerType::get(ctx(), bits);
    return llvm::ConstantInt::get(intType, val);
}

llvm::ConstantInt *Compiler::makeInt(int val) {
    return makeInt(val, 32);
}

llvm::Type *Compiler::getInt(int bit) {
    return llvm::IntegerType::get(ctx(), bit);
}

void Compiler::simpleVariant(const Type &n, llvm::Value *ptr) {
    auto bd = resolv->resolve(n.scope.get()).targetDecl;
    auto decl = dynamic_cast<EnumDecl *>(bd);
    int index = Resolver::findVariant(decl, n.name);
    setOrdinal(index, ptr, bd);
}

void Layout::set_elems_struct(llvm::StructType *st, llvm::Type *base, std::vector<llvm::Type *> &fields) {
    if (base) {
        fields.insert(fields.begin(), base);
    }
    st->setBody(fields);
}

void Layout::set_elems_enum(llvm::StructType *st, llvm::Type *tag, llvm::ArrayType *data) {
    //tag, {base, ...data}
    std::vector<llvm::Type *> elems;
    elems.push_back(tag);
    elems.push_back(data);
    st->setBody(elems);
}

int Layout::get_base_index(BaseDecl *decl) {
    if (decl->isEnum()) {
        //tag data
        return 1;
    }
    return 0;
}

int Layout::get_tag_index(BaseDecl *decl) {
    return 0;
}

int Layout::get_data_index(BaseDecl *decl) {
    return 1;
}

void Compiler::setOrdinal(int index, llvm::Value *ptr, BaseDecl *decl) {
    auto ordPtr = gep2(ptr, Layout::get_tag_index(decl), decl->type);
    Builder->CreateStore(makeInt(index, ENUM_TAG_BITS), ordPtr);
}

llvm::Function *Compiler::make_printf() {
    std::vector<llvm::Type *> args;
    args.push_back(getInt(8)->getPointerTo());
    auto ft = llvm::FunctionType::get(getInt(32), args, true);
    auto f = llvm::Function::Create(ft, llvm::Function::ExternalLinkage, "printf", *mod);
    f->setCallingConv(llvm::CallingConv::C);
    llvm::AttributeList attr;
    f->setAttributes(attr);
    return f;
}

llvm::Function *Compiler::make_fflush() {
    std::vector<llvm::Type *> args{getPtr()};
    auto ft = llvm::FunctionType::get(getInt(32), args, false);
    auto f = llvm::Function::Create(ft, llvm::Function::ExternalLinkage, "fflush", *mod);
    f->setCallingConv(llvm::CallingConv::C);
    return f;
}

llvm::Function *Compiler::make_exit() {
    auto ft = llvm::FunctionType::get(Builder->getVoidTy(), getInt(32), false);
    auto f = llvm::Function::Create(ft, llvm::GlobalValue::ExternalLinkage, "exit", *mod);
    f->setCallingConv(llvm::CallingConv::C);
    llvm::AttributeList attr;
    f->setAttributes(attr);
    return f;
}

llvm::Function *Compiler::make_malloc() {
    auto ret = getInt(8)->getPointerTo();//i8*
    auto ft = llvm::FunctionType::get(ret, getInt(64), false);
    auto f = llvm::Function::Create(ft, llvm::GlobalValue::ExternalLinkage, "malloc", *mod);
    f->setCallingConv(llvm::CallingConv::C);
    return f;
}

llvm::StructType *Compiler::make_slice_type() {
    std::vector<llvm::Type *> elems;
    elems.push_back(getInt(8)->getPointerTo());
    elems.push_back(getInt(SLICE_LEN_BITS));
    return llvm::StructType::create(ctx(), elems, "__slice");
}

llvm::StructType *Compiler::make_string_type() {
    std::vector<llvm::Type *> elems = {sliceType};
    return llvm::StructType::create(ctx(), elems, "str");
}

llvm::Type *Compiler::mapType(const Type &type0, Resolver *r) {
    auto rt = r->resolve(type0);
    auto type = &rt.type;
    if (type->isPointer()) {
        auto &elem = *type->scope.get();
        if (isStruct(elem)) {
            //forward
        }
        return mapType(elem)->getPointerTo();
    }
    if (type->isArray()) {
        auto res = resolv->getType(*type);
        return llvm::ArrayType::get(mapType(res.scope.get()), res.size);
    }
    if (type->isSlice()) {
        return sliceType;
    }
    if (type->isString()) {
        return stringType;
    }
    if (type->isVoid()) {
        return llvm::Type::getVoidTy(ctx());
    }
    if (type->isPrim()) {
        auto bits = sizeMap[type->name];
        return getInt(bits);
    }
    auto str = rt.targetDecl->type.print();
    auto it = classMap.find(str);
    if (it != classMap.end()) {
        return it->second;
    }
    throw std::runtime_error("mapType(" + str + ")");
    /*auto res = makeDecl(rt.targetDecl);
    return res;*/
}

int Compiler::getSize2(BaseDecl *decl) {
    auto st = (llvm::StructType *) mapType(decl->type);
    auto sl = mod->getDataLayout().getStructLayout(st);
    return sl->getSizeInBits();
}

int getSize(llvm::StructType *type, Compiler *c) {
    auto sl = c->mod->getDataLayout().getStructLayout(type);
    return sl->getSizeInBits();
}

int Compiler::getSize2(const Type *type) {
    if (type->isPointer()) {
        return 64;
    }
    if (type->isPrim()) {
        return sizeMap[type->name];
        //return 64;//aligned
    }
    if (type->isArray()) {
        return getSize2(type->scope.get()) * type->size;
    }
    if (type->isSlice()) {
        //ptr + len
        //return 64 + 32;
        return getSize(sliceType, this);
    }
    auto decl = resolv->resolve(*type).targetDecl;
    if (decl) {
        return getSize2(decl);
    }
    throw std::runtime_error("size(" + type->print() + ")");
}


bool Exit::is_return() {
    if (kind == ExitType::RETURN) return true;
    if (if_kind && else_kind) return if_kind->is_return() && else_kind->is_return();
    return false;
}
bool Exit::is_panic() {
    if (kind == ExitType::PANIC) return true;
    if (if_kind && else_kind) return if_kind->is_panic() && else_kind->is_panic();
    return false;
}
bool Exit::is_exit() {
    if (kind == ExitType::PANIC || kind == ExitType::RETURN) return true;
    if (if_kind && else_kind) return if_kind->is_exit() && else_kind->is_exit();
    return false;
}
bool Exit::is_jump() {
    if (kind == ExitType::RETURN || kind == ExitType::CONTINE || kind == ExitType::BREAK || kind == ExitType::PANIC) return true;
    if (if_kind && else_kind) return if_kind->is_jump() && else_kind->is_jump();
    return false;
}


Exit Exit::get_exit_type(Statement *stmt) {
    if (dynamic_cast<ReturnStmt *>(stmt)) return ExitType::RETURN;
    if (dynamic_cast<BreakStmt *>(stmt)) return ExitType::BREAK;
    if (dynamic_cast<ContinueStmt *>(stmt)) return ExitType::CONTINE;
    auto expr = dynamic_cast<ExprStmt *>(stmt);
    if (expr) {
        auto mc = dynamic_cast<MethodCall *>(expr->expr);
        if (mc && !mc->scope && mc->name == "panic") {
            return ExitType::PANIC;
        }
        return ExitType::NONE;
    }
    auto block = dynamic_cast<Block *>(stmt);
    if (block && !block->list.empty()) {
        auto &last = block->list.back();
        return get_exit_type(last.get());
    }
    auto is = dynamic_cast<IfStmt *>(stmt);
    if (is) {
        auto res = Exit{ExitType::NONE};
        auto if_type = get_exit_type(is->thenStmt.get());
        res.if_kind = std::make_unique<Exit>(std::move(if_type));
        if (is->elseStmt) {
            auto else_kind = get_exit_type(is->elseStmt.get());
            res.else_kind = std::make_unique<Exit>(std::move(else_kind));
        }
        return res;
    }
    return ExitType::NONE;
}

void Compiler::make_decl_protos() {
    std::vector<BaseDecl *> list;
    for (auto bd : getTypes(unit.get())) {
        if (bd->isGeneric) continue;
        list.push_back(bd);
        //print("local "+bd->type.print());
    }
    for (auto bd : resolv->usedTypes) {
        if (bd->isGeneric) {
            //error("gen");
            continue;
        }
        list.push_back(bd);
        //print("used "+bd->type.print());
    }
    sort(list, resolv.get());
    for (auto bd : list) {
        make_decl_proto(bd);
    }
    for (auto bd : list) {
        fill_decl_proto(bd);
    }
    for (auto bd : list) {
        map_di_proto(bd);
    }
    for (auto bd : list) {
        map_di_fill(bd);
    }
}

llvm::Type *Compiler::make_decl_proto(BaseDecl *decl) {
    if (decl->isGeneric) {
        return nullptr;
    }
    auto mangled = decl->type.print();
    auto ty = llvm::StructType::create(ctx(), mangled);
    classMap[mangled] = ty;
    if (decl->isEnum()) {
        auto ed = dynamic_cast<EnumDecl *>(decl);
        for (auto &ev : ed->variants) {
            auto var_mangled = mangled + "::" + ev.name;
            auto var_ty = llvm::StructType::create(ctx(), var_mangled);
            classMap[var_mangled] = var_ty;
        }
    }
    return ty;
}

llvm::Type *Compiler::fill_decl_proto(BaseDecl *decl) {
    if (decl->isGeneric) {
        return nullptr;
    }
    auto mangled = decl->type.print();
    auto ty = (llvm::StructType *) classMap.at(mangled);
    if (decl->isEnum()) {
        auto ed = dynamic_cast<EnumDecl *>(decl);
        int max_var = 0;
        for (auto &ev : ed->variants) {
            auto var_mangled = mangled + "::" + ev.name;
            auto var_ty = (llvm::StructType *) classMap.at(var_mangled);
            std::vector<llvm::Type *> var_elems;
            if (decl->base) {
                auto base_ty = mapType(decl->base.value(), resolv.get());
                var_elems.push_back(base_ty);
            }
            for (auto &field : ev.fields) {
                var_elems.push_back(mapType(&field.type, resolv.get()));
            }
            var_ty->setBody(var_elems);
            auto var_size = mod->getDataLayout().getStructLayout(var_ty)->getSizeInBits();
            if (var_size > max_var) {
                max_var = var_size;
            }
            /*if (decl->type.print() == "Expr") {
                print(var_mangled + "=" + std::to_string(var_size / 8) + " max=" + std::to_string(max_var / 8));
            }*/
        }
        auto data_size = max_var / 8;
        auto tag_type = getInt(ENUM_TAG_BITS);
        auto data_type = llvm::ArrayType::get(getInt(8), data_size);
        Layout::set_elems_enum(ty, tag_type, data_type);
    } else {
        auto sd = dynamic_cast<StructDecl *>(decl);
        std::vector<llvm::Type *> elems;
        for (auto &field : sd->fields) {
            elems.push_back(mapType(&field.type, resolv.get()));
        }
        if (decl->base) {
            auto base_ty = mapType(decl->base.value(), resolv.get());
            Layout::set_elems_struct(ty, base_ty, elems);
        } else {
            Layout::set_elems_struct(ty, nullptr, elems);
        }
    }
    return ty;
}

llvm::Value *Compiler::get_obj_ptr(Expression *e) {
    auto pe = dynamic_cast<ParExpr *>(e);
    if (pe) {
        return get_obj_ptr(pe->expr);
    }
    auto val = gen(e);
    auto infix = dynamic_cast<Infix *>(e);
    if (infix) {
        return val;
    }
    auto de = dynamic_cast<DerefExpr *>(e);
    if (de) {
        //resolv->err(e, "deref");
        return val;
    }
    if (dynamic_cast<ObjExpr *>(e)) {
        return val;
    }
    auto sn = dynamic_cast<SimpleName *>(e);
    if (sn) {
        //local, localptr, prm, prm ptr, mut prm
        auto rt = resolv->resolve(e);
        if (rt.type.isPointer()) {
            //auto deref
            //always alloca
            //local ptr
            return load(val, getPtr());
        } else {
            //mut or not has no effect
            //local
            return val;
        }
        //return val;
    }
    auto mc = dynamic_cast<MethodCall *>(e);
    if (mc) {
        if (is_ptr_deref(mc)) {
        }
        return val;
    }
    if (dynamic_cast<ArrayAccess *>(e) || dynamic_cast<FieldAccess *>(e)) {
        auto rt = resolv->resolve(e);
        if (rt.type.isPointer()) {
            //deref gep
            return load(val, getPtr());
        } else {
            return val;
        }
    }
    if (dynamic_cast<RefExpr *>(e) || dynamic_cast<Literal *>(e) || dynamic_cast<Unary *>(e) || dynamic_cast<AsExpr *>(e)) {
        return val;
    }

    throw std::runtime_error("get_obj_ptr " + e->print());
}