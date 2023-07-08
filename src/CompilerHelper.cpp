#include "Compiler.h"
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/LLVMContext.h>

void sort(std::vector<BaseDecl *> &list, Resolver *r) {
    // for (auto decl : list) {
    //     std::cout << decl->type.print() << ", ";
    // }
    // std::cout << std::endl;
    for (int i = 0; i < list.size(); i++) {
        //find min that belongs to i'th index
        auto min = list[i];
        for (int j = i + 1; j < list.size(); j++) {
            auto &cur = list[j];
            if (r->isCyclic(min->type, cur)) {
                //print("swap " + min->type.print() + " and " + cur->type.print());
                min = cur;
                std::swap(list[i], list[j]);
            }
        }
    }
}

std::vector<Method *> getMethods(Unit *unit) {
    std::vector<Method *> list;
    for (auto &item : unit->items) {
        if (item->isMethod()) {
            auto m = dynamic_cast<Method *>(item.get());
            list.push_back(m);
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
        return !obj->isPointer;
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

bool isStrLit(Expression *e) {
    auto l = dynamic_cast<Literal *>(e);
    if (!l) return false;
    return l->type == Literal::STR;
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
    auto ordPtr = gep2(ptr, Layout::get_tag_index(decl));
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
    llvm::AttributeList attr;
    llvm::AttrBuilder builder;
    builder.addAlignmentAttr(16);
    attr = attr.addAttributes(ctx(), 0, builder);
    f->setAttributes(attr);
    return f;
}

llvm::StructType *Compiler::make_slice_type() {
    std::vector<llvm::Type *> elems;
    elems.push_back(getInt(8)->getPointerTo());
    elems.push_back(getInt(32));//len
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

llvm::DIType *Compiler::map_di(const Type *t) {
    auto rt = resolv->resolve(*t);
    t = &rt.type;
    auto s = t->print();
    auto it = di.types.find(s);
    if (it != di.types.end()) return it->second;
    if (t->isPointer()) {
        return DBuilder->createPointerType(map_di(t->scope.get()), 64);
    }
    if (t->isArray()) {
        llvm::DINodeArray sub;
        auto elem = map_di(t->scope.get());
        return DBuilder->createArrayType(t->size, 8, elem, sub);
    }
    if (t->isSlice()) {
        auto sz = getSize(t);
        auto file = DBuilder->createFile(di.cu->getFilename(), di.cu->getDirectory());
        std::vector<llvm::Metadata *> elems;
        elems.push_back(DBuilder->createPointerType(map_di(t->scope.get()), 64));
        elems.push_back(map_di(new Type("i32")));
        auto et = llvm::DINodeArray(llvm::MDTuple::get(ctx(), elems));
        return DBuilder->createStructType(di.cu, s, file, 0, sz, 8, llvm::DINode::FlagZero, nullptr, et);
    }
    if (s == "bool") return DBuilder->createBasicType(s, 8, llvm::dwarf::DW_ATE_boolean);
    if (s == "i8") return DBuilder->createBasicType(s, 8, llvm::dwarf::DW_ATE_signed);
    if (s == "i16") return DBuilder->createBasicType(s, 16, llvm::dwarf::DW_ATE_signed);
    if (s == "i32") return DBuilder->createBasicType(s, 32, llvm::dwarf::DW_ATE_signed);
    if (s == "i64") return DBuilder->createBasicType(s, 64, llvm::dwarf::DW_ATE_signed);
    if (s == "f32") return DBuilder->createBasicType(s, 32, llvm::dwarf::DW_ATE_float);
    if (s == "i64") return DBuilder->createBasicType(s, 64, llvm::dwarf::DW_ATE_float);
    if (s == "void") return nullptr;
    if (s == "u8") return DBuilder->createBasicType(s, 8, llvm::dwarf::DW_ATE_unsigned);
    if (s == "u16") return DBuilder->createBasicType(s, 16, llvm::dwarf::DW_ATE_unsigned);
    if (s == "u32") return DBuilder->createBasicType(s, 32, llvm::dwarf::DW_ATE_unsigned);
    if (s == "u64") return DBuilder->createBasicType(s, 64, llvm::dwarf::DW_ATE_unsigned);
    if (rt.targetDecl) {
        auto file = DBuilder->createFile(rt.targetDecl->unit->path, di.cu->getDirectory());
        auto st_size = getSize2(t);
        std::vector<llvm::Metadata *> elems;
        if (rt.targetDecl->isEnum()) {
            //todo order
            auto ed = (EnumDecl *) rt.targetDecl;
            auto tag = DBuilder->createBasicType("tag", ENUM_TAG_BITS, llvm::dwarf::DW_ATE_signed);
            auto tagm = DBuilder->createMemberType(nullptr, "tag", file, ed->line, ENUM_TAG_BITS, 8, 0, llvm::DINode::FlagZero, tag);
            elems.push_back(tagm);
            auto chr = DBuilder->createBasicType("i8", 8, llvm::dwarf::DW_ATE_signed);
            auto sz = getSize2(ed) - ENUM_TAG_BITS;
            llvm::DINodeArray sub;
            auto at = DBuilder->createArrayType(sz, 8, chr, sub);
            auto arrm = DBuilder->createMemberType(nullptr, "data", file, ed->line, sz, 8, ENUM_TAG_BITS, llvm::DINode::FlagZero, at);
            elems.push_back(arrm);
        } else {
            auto sd = (StructDecl *) rt.targetDecl;
            int idx = 0;
            auto st = (llvm::StructType *) mapType(sd->type);
            auto sl = mod->getDataLayout().getStructLayout(st);
            for (auto &fd : sd->fields) {
                auto off = sl->getElementOffsetInBits(idx);
                int sz;
                if (idx == sd->fields.size() - 1) {
                    //sz = st_size - off;
                    sz = getSize2(fd.type);
                } else {
                    sz = sl->getElementOffsetInBits(idx + 1) - off;
                }
                auto mt = DBuilder->createMemberType(nullptr, fd.name, file, fd.line, sz, 0, off, llvm::DINode::FlagZero, map_di(fd.type));
                elems.push_back(mt);
                idx++;
            }
        }
        auto et = llvm::DINodeArray(llvm::MDTuple::get(ctx(), elems));
        return DBuilder->createStructType(di.cu, s, file, rt.targetDecl->line, st_size, 0, llvm::DINode::FlagZero, nullptr, et);
    }
    throw std::runtime_error("di type: " + t->print());
}

int Compiler::getSize(BaseDecl *decl) {
    if (decl->isEnum()) {
        auto ed = dynamic_cast<EnumDecl *>(decl);
        int res = 0;
        for (auto &ev : ed->variants) {
            if (ev.fields.empty()) continue;
            int cur = 0;
            for (auto &f : ev.fields) {
                cur += getSize(f.type);
            }
            res = cur > res ? cur : res;
        }
        return res + ENUM_TAG_BITS;
    } else {
        auto td = dynamic_cast<StructDecl *>(decl);
        int res = 0;
        for (auto &fd : td->fields) {
            res += getSize(fd.type);
        }
        return res;
    }
}

int Compiler::getSize2(BaseDecl *decl) {
    auto st = (llvm::StructType *) mapType(decl->type);
    auto sl = mod->getDataLayout().getStructLayout(st);
    return sl->getSizeInBits();
}

int Compiler::getSize(const Type *type) {
    auto tt = resolv->getType(*type);
    type = &tt;
    if (type->isPointer()) {
        return 64;
    }
    if (type->isPrim()) {
        return sizeMap[type->name];
        //return 64;
    }
    if (type->isArray()) {
        return getSize(type->scope.get()) * type->size;
    }
    if (type->isSlice()) {
        //ptr + len
        return 64 + 32;
    }
    auto decl = resolv->resolve(*type).targetDecl;
    if (decl) {
        return getSize(decl);
    }
    throw std::runtime_error("size(" + type->print() + ")");
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
        //todo align
        return 64 + 32;
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
        auto ptr = compiler->Builder->CreateAlloca(type);
        auto &arr = compiler->allocMap[e->print()];
        arr.push_back(ptr);
        //print("alloc "+e->print());
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
            auto type = f.type ? compiler->resolv->resolve(*f.type) : compiler->resolv->resolve(f.rhs.get());
            llvm::Value *ptr;
            if (compiler->doesAlloc(f.rhs.get())) {
                //auto alloc
                auto rhs = f.rhs->accept(this);
                ptr = std::any_cast<llvm::Value *>(rhs);
            } else {
                //manual alloc, prims, struct copy
                ptr = alloc(type.type, node);
                if (dynamic_cast<MethodCall *>(f.rhs.get())//args
                    || dynamic_cast<FieldAccess *>(f.rhs.get()) /*scope*/) {
                    //todo not just this
                    f.rhs->accept(this);
                }
            }
            ptr->setName(f.name);
            auto id = compiler->getId(f.name);
            compiler->varAlloc[id] = ptr;
        }
        return {};
    }
    void call(MethodCall *node) {
        //todo rvo
        if (node->scope) node->scope->accept(this);
        for (auto a : node->args) {
            if (!node->scope && node->name == "print" && isStrLit(a)) {
                continue;
            }
            a->accept(this);
        }
    }
    std::any visitMethodCall(MethodCall *node) override {
        auto m = compiler->resolv->resolve(node).targetMethod;
        llvm::Value *ptr = nullptr;
        if (m && compiler->isRvo(m)) {
            ptr = alloc(m->type, node);
        }
        if (node->scope) node->scope->accept(this);
        for (auto a : node->args) {
            if (!node->scope && node->name == "print" && isStrLit(a)) {
                continue;
            }
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
            for (auto &e : obj->entries) {
                if (!e.isBase) child(e.value);
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
        if (node->isPointer) {
            //todo this too
            return {};
        }
        auto ty = compiler->resolv->getType(node);
        auto ptr = alloc(ty, node);
        for (auto &e : node->entries) {
            if (!e.isBase) child(e.value);
        }
        return ptr;
    }
    std::any visitArrayExpr(ArrayExpr *node) override {
        auto ty = compiler->resolv->getType(node);
        auto ptr = alloc(ty, node);
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
    allocMap.clear();
    if (st) {
        resolv->max_scope = 1;
        AllocCollector col(this);
        st->accept(&col);
    }
}