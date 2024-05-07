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

bool Cache::need_compile(const fs::path &p) {
    if (!Config::use_cache) {
        return true;
    }
    auto s = p.string();
    auto out = get_out_file(s);
    if (!fs::exists(fs::path(out))) {
        return true;
    }
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
        if (STRUCT_BASE_INDEX == 0) {
            fields.insert(fields.begin(), base);
        } else if (STRUCT_BASE_INDEX == -1) {
            fields.insert(fields.end(), base);
        } else {
            error("no valid base index");
        }
    }
    st->setBody(fields);
    //st->dump();
}

void Layout::set_elems_enum(llvm::StructType *st, llvm::Type *base, llvm::Type *tag, llvm::ArrayType *data) {
    std::vector<llvm::Type *> elems;
    if (base) {
        if (ENUM_BASE_INDEX == 0) {
            elems.push_back(base);
        } else {
            error("no valid base index");
        }
    }
    if (ENUM_TAG_INDEX < ENUM_DATA_INDEX) {
        elems.push_back(tag);
        elems.push_back(data);
    } else {
        elems.push_back(data);
        elems.push_back(tag);
    }
    st->setBody(elems);
}

int Layout::get_tag_index(BaseDecl *decl) {
    if (decl->base) {
        return ENUM_TAG_INDEX;
    } else if (ENUM_BASE_INDEX < ENUM_TAG_INDEX) {
        //shift left
        return ENUM_TAG_INDEX - 1;
    } else {
        //base right, doesnt matter
        return ENUM_TAG_INDEX;
    }
}

int Layout::get_data_index(BaseDecl *decl) {
    if (decl->base) {
        return ENUM_DATA_INDEX;
    } else if (ENUM_BASE_INDEX < ENUM_DATA_INDEX) {
        //shift left
        return ENUM_DATA_INDEX - 1;
    } else {
        //base right, doesnt matter
        return ENUM_DATA_INDEX;
    }
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
    /*llvm::AttributeList attr;
    llvm::AttrBuilder builder(ctx());
    //builder.addAlignmentAttr(16);
    attr = attr.addFnAttributes(ctx(), builder);
    f->setAttributes(attr);*/
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
    auto res = makeDecl(rt.targetDecl);
    makeDecl(rt.targetDecl);
    return res;
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

class AllocCollector : public Visitor {
public:
    Compiler *compiler;

    AllocCollector(Compiler *c) : compiler(c) {}

    template<class T>
    llvm::Value *alloc(llvm::Type *type, T *e) {
        if (e->id == -1) {
            throw std::runtime_error("id -1 for " + e->print());
        }
        auto ptr = compiler->Builder->CreateAlloca(type);
        compiler->allocMap2[e->id] = ptr;
        return ptr;
    }
    template<class T>
    llvm::Value *alloc(const Type &type, T *e) {
        return alloc(compiler->mapType(type), e);
    }
    std::any visitVarDecl(VarDecl *node) override {
        node->decl->accept(this);
        return {};
    }
    std::any visitVarDeclExpr(VarDeclExpr *node) override {
        for (auto &f : node->list) {
            auto rhs = f.rhs.get();
            auto type = f.type ? compiler->resolv->resolve(*f.type) : compiler->resolv->resolve(rhs);
            llvm::Value *ptr;
            if (compiler->doesAlloc(rhs)) {
                //auto alloc
                auto rhs2 = f.rhs->accept(this);
                ptr = std::any_cast<llvm::Value *>(rhs2);
            } else {
                //prim_size(s).unwrap() as i32;
                //manual alloc, prims, struct copy
                ptr = alloc(type.type, &f);
                f.rhs->accept(this);
                // if (dynamic_cast<MethodCall *>(rhs)//args
                //     || dynamic_cast<FieldAccess *>(rhs) /*scope*/) {
                //     //todo not just this
                //     f.rhs->accept(this);
                // }
            }
            ptr->setName(f.name);
            auto id = compiler->getId(f.name);
            compiler->varAlloc[id] = ptr;
        }
        return {};
    }
    void call(MethodCall *node) {
        //todo rvo
        if (node->scope) {
            node->scope->accept(this);
        }
        for (auto a : node->args) {
            if (!node->scope && node->name == "print" && isStrLit(a)) {
                continue;
            }
            a->accept(this);
        }
    }
    std::any visitMethodCall(MethodCall *node) override {
        if (is_std_parent_name(node)) {
            return alloc(Type("str"), node);
        }
        if (is_format(node)) {
            auto &info = compiler->resolv->format_map.at(node->id);
            info.block.accept(this);
            return alloc(Type("String"), node);
        }
        if (is_print(node)) {
            auto &info = compiler->resolv->format_map.at(node->id);
            info.block.accept(this);
            return {};
        }
        if (is_panic(node)) {
            auto &info = compiler->resolv->format_map.at(node->id);
            info.block.accept(this);
            return {};
        }
        auto m = compiler->resolv->resolve(node).targetMethod;
        llvm::Value *ptr = nullptr;
        if (m && compiler->isRvo(m)) {
            ptr = alloc(m->type, node);
        }
        if (node->scope) node->scope->accept(this);
        for (auto a : node->args) {
            a->accept(this);
        }
        return ptr;
    }
    std::any visitType(Type *node) override {
        if (!node->scope) {
            return {};
        }
        if (node->isPointer()) {
            return {};
        }
        return alloc(*node, node);
    }

    void child(Expression *e) {
        auto mc = dynamic_cast<MethodCall *>(e);
        if (mc) {
            if (Config::rvo_ptr) call(mc);
            else
                e->accept(this);
            return;
        }
        auto obj = dynamic_cast<ObjExpr *>(e);
        if (obj) {
            for (auto &ent : obj->entries) {
                if (!ent.isBase) child(ent.value);
            }
            return;
        }
        auto ty = dynamic_cast<Type *>(e);
        if (ty) {
            return;
        }
        auto ae = dynamic_cast<ArrayExpr *>(e);
        if (ae) {
            return;
        }
        auto aa = dynamic_cast<ArrayAccess *>(e);
        if (aa && aa->index2) {
            aa->array->accept(this);
        }
    }
    void object(ObjExpr *node) {
        for (auto &e : node->entries) {
            if (!e.isBase) child(e.value);
        }
    }
    std::any visitObjExpr(ObjExpr *node) override {
        auto ty = compiler->resolv->getType(node);
        auto ptr = alloc(ty, node);
        for (auto &e : node->entries) {
            if (!e.isBase) child(e.value);
            else {
                child(e.value);
            }
        }
        return ptr;
    }
    std::any visitArrayExpr(ArrayExpr *node) override {
        auto ty = compiler->resolv->getType(node);
        auto ptr = alloc(ty, node);
        //((llvm::AllocaInst*)ptr)->setAlignment(llvm::Align(100));
        if (node->isSized() && compiler->doesAlloc(node->list[0])) {
            node->list[0]->accept(this);
        }
        return ptr;
    }
    std::any visitArrayAccess(ArrayAccess *node) override {
        if (node->index2) {
            auto ptr = alloc(compiler->sliceType, node);
            node->array->accept(this);
            node->index2->accept(this);
            node->index->accept(this);
            return ptr;
        } else {
            node->array->accept(this);
            node->index->accept(this);
        }
        return {};
    }
    std::any visitLiteral(Literal *node) override {
        if (node->type == Literal::STR) {
            return alloc(compiler->stringType, node);
        }
        return {};
    }
    std::any visitFieldAccess(FieldAccess *node) override {
        node->scope->accept(this);
        return {};
    }
    std::any visitBlock(Block *node) override {
        for (auto &s : node->list) {
            s->accept(this);
        }
        return {};
    }
    std::any visitWhileStmt(WhileStmt *node) override {
        node->expr->accept(this);
        compiler->resolv->max_scope++;
        node->body->accept(this);
        return {};
    }
    std::any visitForStmt(ForStmt *node) override {
        compiler->resolv->max_scope++;
        if (node->decl) {
            node->decl->accept(this);
        }
        node->body->accept(this);
        return {};
    }
    std::any visitIfStmt(IfStmt *node) override {
        node->expr->accept(this);
        compiler->resolv->max_scope++;
        node->thenStmt->accept(this);
        if (node->elseStmt) {
            compiler->resolv->max_scope++;
            node->elseStmt->accept(this);
        }
        return {};
    }
    std::any visitReturnStmt(ReturnStmt *node) override {
        if (!node->expr) {
            return {};
        }
        auto e = node->expr.get();
        auto mc = dynamic_cast<MethodCall *>(e);
        if (mc) {
            call(mc);
            return {};
        }
        auto oe = dynamic_cast<ObjExpr *>(e);
        if (oe) {
            object(oe);
            return {};
        }
        if (compiler->doesAlloc(e)) {
            return {};
        } else {
            e->accept(this);
        }
        return {};
    }
    std::any visitExprStmt(ExprStmt *node) override {
        node->expr->accept(this);
        return {};
    }
    std::any visitAssign(Assign *node) override {
        node->right->accept(this);
        return {};
    }
    std::any visitSimpleName(SimpleName *node) override {
        return {};
    }
    std::any visitInfix(Infix *node) override {
        node->left->accept(this);
        node->right->accept(this);
        return {};
    }
    std::any visitAssertStmt(AssertStmt *node) override {
        node->expr->accept(this);
        return {};
    }

    std::any visitRefExpr(RefExpr *node) override {
        node->expr->accept(this);
        return {};
    }
    std::any visitDerefExpr(DerefExpr *node) override {
        node->expr->accept(this);
        return {};
    }
    std::any visitUnary(Unary *node) override {
        node->expr->accept(this);
        return {};
    }
    std::any visitParExpr(ParExpr *node) override {
        node->expr->accept(this);
        return {};
    }
    std::any visitAsExpr(AsExpr *node) override {
        node->expr->accept(this);
        return {};
    }
    std::any visitIsExpr(IsExpr *node) override {
        node->expr->accept(this);
        return {};
    }
    std::any visitIfLetStmt(IfLetStmt *node) override {
        node->rhs->accept(this);
        compiler->resolv->max_scope++;
        auto rhs_rt = compiler->resolv->resolve(node->type);
        auto decl = (EnumDecl *) rhs_rt.targetDecl;
        auto index = Resolver::findVariant(decl, node->type.name);
        auto &variant = decl->variants[index];
        int i = 0;
        for (auto &arg : node->args) {
            Type type = variant.fields[i].type;
            if (arg.ptr) {
                type = Type(Type::Pointer, type);
            }
            auto ptr = alloc(type, node);
            ptr->setName(arg.name);
            auto id = compiler->getId(arg.name);
            compiler->varAlloc[id] = ptr;
            i++;
        }
        node->thenStmt->accept(this);
        if (node->elseStmt) {
            compiler->resolv->max_scope++;
            node->elseStmt->accept(this);
        }
        return {};
    }
    std::any visitContinueStmt(ContinueStmt *node) override {
        return {};
    }
    std::any visitBreakStmt(BreakStmt *node) override {
        return {};
    }
};

void Compiler::makeLocals(Statement *st) {
    //std::cout << "makeLocals " << resolv->unit->path << " " << curMethod->name << "\n";
    allocMap2.clear();
    if (st) {
        resolv->max_scope = 1;
        AllocCollector col(this);
        st->accept(&col);
    }
}

bool Exit::is_return() {
    if (kind == ExitType::RETURN) return true;
    if (if_kind && else_kind) return if_kind->is_return() && else_kind->is_return();
    return false;
}
bool Exit::is_jump() {
    if (kind == ExitType::RETURN || kind == ExitType::CONTINE || kind == ExitType::BREAK || kind == ExitType::PANIC) return true;
    if (if_kind && else_kind) return if_kind->is_jump() && else_kind->is_jump();
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


Exit Exit::get_exit_type(Statement *stmt) {
    if (stmt->line == 106) {
        int x = 10;
    }
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