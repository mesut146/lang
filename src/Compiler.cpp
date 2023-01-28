#include "Compiler.h"
#include "Resolver.h"
#include "parser/Ast.h"
#include "parser/Parser.h"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <unordered_map>
#include <variant>


#include "llvm/Transforms/IPO/PassManagerBuilder.h"
#include <llvm/IR/Attributes.h>
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/LegacyPassManager.h>
#include <llvm/IR/Value.h>
#include <llvm/IR/Verifier.h>
#include <llvm/Support/FileSystem.h>
#include <llvm/Support/Host.h>
#include <llvm/Support/TargetRegistry.h>
#include <llvm/Support/TargetSelect.h>
#include <llvm/Target/TargetOptions.h>

namespace fs = std::filesystem;

const int SLICE_LEN_INDEX = 1;

std::string getName(const std::string &path) {
    auto i = path.rfind('/');
    return path.substr(i + 1);
}

std::string trimExtenstion(const std::string &name) {
    auto i = name.rfind('.');
    if (i == std::string::npos) {
        return name;
    }
    return name.substr(0, i);
}

std::unique_ptr<llvm::LLVMContext> ctx;
std::unique_ptr<llvm::Module> mod;
std::unique_ptr<llvm::IRBuilder<>> Builder;
std::map<std::string, llvm::Value *> NamedValues;
std::map<std::string, llvm::Function *> funcMap;
std::map<std::string, llvm::Type *> classMap;
llvm::Function *printf_proto;
llvm::Function *exit_proto;
llvm::Function *mallocf;

std::vector<llvm::Value *> allocArr;
llvm::StructType *sliceType;

static void InitializeModule(std::string &name) {
    ctx.release();
    mod.release();
    Builder.release();
    // Open a new context and module.
    ctx = std::make_unique<llvm::LLVMContext>();
    mod = std::make_unique<llvm::Module>(name, *ctx);
    Builder = std::make_unique<llvm::IRBuilder<>>(*ctx);
    funcMap.clear();
    classMap.clear();
}
llvm::ConstantInt *makeInt(int val, int bits) {
    auto intType = llvm::IntegerType::get(*ctx, bits);
    return llvm::ConstantInt::get(intType, val);
}

llvm::ConstantInt *makeInt(int val) {
    return makeInt(val, 32);
}

llvm::Type *getInt(int bit) {
    return llvm::IntegerType::get(*ctx, bit);
}

llvm::Type *Compiler::mapType(Type *type) {
    if (type->isPointer()) {
        auto elem = dynamic_cast<PointerType *>(type)->type;
        if (isStruct(elem)) {
            //forward
        }
        return mapType(elem)->getPointerTo();
    }
    if (type->isArray()) {
        auto res = resolv->resolve(type);
        auto arr = dynamic_cast<ArrayType *>(res->type);
        return llvm::ArrayType::get(mapType(arr->type), arr->size);
    }
    if (type->isSlice()) {
        return sliceType;
    }
    if (type->isVoid()) {
        return llvm::Type::getVoidTy(*ctx);
    }
    if (type->isPrim()) {
        auto bits = sizeMap[type->name];
        return getInt(bits);
    }
    auto rt = resolv->resolveType(type);
    auto s = mangle(rt->targetDecl->type);
    auto it = classMap.find(s);
    if (it != classMap.end()) {
        return it->second;
    }
    throw std::runtime_error("mapType: " + s);
}

int Compiler::getSize(BaseDecl *decl) {
    if (decl->isEnum()) {
        auto ed = dynamic_cast<EnumDecl *>(decl);
        int res = 0;
        for (auto ev : ed->variants) {
            if (ev->fields.empty()) continue;
            int cur = 0;
            for (auto &f : ev->fields) {
                cur += getSize(f->type);
            }
            res = cur > res ? cur : res;
        }
        return res;
    } else {
        auto td = dynamic_cast<StructDecl *>(decl);
        int res = 0;
        for (auto &fd : td->fields) {
            res += getSize(fd->type);
        }
        return res;
    }
}

int Compiler::getSize(Type *type) {
    if (dynamic_cast<PointerType *>(type)) {
        return 64;
    }
    if (type->isPrim()) {
        return sizeMap[type->name];
    }
    if (type->isArray()) {
        auto arr = dynamic_cast<ArrayType *>(type);
        return getSize(arr->type) * arr->size;
    }
    if(type->isSlice()){
        //data ptr, len
        return 64 + 32;
    }

    auto decl = resolv->resolveType(type)->targetDecl;
    if (decl) {
        return getSize(decl);
    }
    throw std::runtime_error("size(" + type->print() + ")");
}

llvm::Value *makeStr(std::string &str) {
    auto charType = getInt(8);
    auto glob = Builder->CreateGlobalString(str);
    return Builder->CreateBitCast(glob, charType->getPointerTo());
}

llvm::Value *branch(llvm::Value *val) {
    auto ty = llvm::cast<llvm::IntegerType>(val->getType());
    if (ty) {
        auto w = ty->getBitWidth();
        if (w != 1) {
            return Builder->CreateTrunc(val, getInt(1));
        }
    }
    return val;
}

bool isObj(Expression *e) {
    auto obj = dynamic_cast<ObjExpr *>(e);
    return obj && !obj->isPointer || dynamic_cast<Type *>(e);
}

llvm::Value *load(llvm::Value *val) {
    auto ty = val->getType()->getPointerElementType();
    return Builder->CreateLoad(ty, val);
}

bool isVar(Expression *e) {
    return dynamic_cast<SimpleName *>(e) || dynamic_cast<DerefExpr *>(e) || dynamic_cast<FieldAccess *>(e) || dynamic_cast<ArrayAccess *>(e);
}

llvm::Value *Compiler::loadPtr(Expression *e) {
    auto val = gen(e);
    if (isVar(e)) {
        return load(val);
    }
    return val;
}

llvm::Value *Compiler::loadPtr(std::unique_ptr<Expression> &e) {
    return loadPtr(e.get());
}

static void make_printf() {
    std::vector<llvm::Type *> args;
    auto charPtr = getInt(8)->getPointerTo();
    args.push_back(charPtr);
    auto ft = llvm::FunctionType::get(getInt(32), args, true);
    auto f = llvm::Function::Create(ft, llvm::Function::ExternalLinkage, "printf", mod.get());
    f->setCallingConv(llvm::CallingConv::C);
    llvm::AttributeList attr;
    f->setAttributes(attr);
    printf_proto = f;
}

static void make_exit() {
    auto ft = llvm::FunctionType::get(Builder->getVoidTy(), getInt(32), false);
    auto f = llvm::Function::Create(ft, llvm::GlobalValue::ExternalLinkage, "exit", mod.get());
    f->setCallingConv(llvm::CallingConv::C);
    llvm::AttributeList attr;
    f->setAttributes(attr);
    exit_proto = f;
}

static void make_malloc() {
    auto ret = getInt(8)->getPointerTo();//i8*
    auto ft = llvm::FunctionType::get(ret, getInt(64), false);
    auto f = llvm::Function::Create(ft, llvm::GlobalValue::ExternalLinkage, "malloc", mod.get());
    f->setCallingConv(llvm::CallingConv::C);
    llvm::AttributeList attr;
    llvm::AttrBuilder builder;
    builder.addAlignmentAttr(16);
    attr = attr.addAttributes(*ctx, 0, builder);
    f->setAttributes(attr);
    mallocf = f;
}

void Compiler::make_proto(std::unique_ptr<Method> &m) {
    make_proto(m.get());
}

void Compiler::make_proto(Method *m) {
    if (m->isGeneric) {
        return;
    }
    std::vector<llvm::Type *> argTypes;
    /*bool rvo = !m->type->isVoid() && isStruct(m->type.get());
    if (rvo) {
        argTypes.push_back(mapType(m->type.get())->getPointerTo());
    }*/
    if (isMember(m)) {
        auto p = m->self->type.get();
        if (isStruct(p)) {
            argTypes.push_back(mapType(p)->getPointerTo());
        } else {
            argTypes.push_back(mapType(p));
        }
    }
    for (auto prm : m->params) {
        auto t = prm->type.get();
        if (isStruct(t)) {
            //structs are always pass by ptr
            argTypes.push_back(mapType(prm->type.get())->getPointerTo());
        } else {
            argTypes.push_back(mapType(prm->type.get()));
        }
    }
    auto retType = mapType(m->type.get());
    /*if (isStruct(m->type.get())) {
        retType = Builder->getVoidTy();
    }*/
    auto mangled = mangle(m);
    auto fr = llvm::FunctionType::get(retType, argTypes, false);
    auto f = llvm::Function::Create(fr, llvm::Function::ExternalLinkage, mangled, mod.get());
    //f->addTypeMetadata(0, llvm::MDNode::get(*ctx, llvm::MDString::get(*ctx, m->name)));
    int i = 0;
    if (isMember(m)) {
        f->getArg(0)->setName("self");
        i++;
    }
    for (int pi = 0; i < f->arg_size(); i++) {
        f->getArg(i)->setName(m->params[pi++]->name);
    }
    funcMap[mangled] = f;
}

void make_slice_type() {
    std::vector<llvm::Type *> elems;
    elems.push_back(getInt(8)->getPointerTo());
    elems.push_back(getInt(32));//len
    sliceType = llvm::StructType::create(*ctx, elems, "__slice");
}

void Compiler::makeDecl(BaseDecl *bd) {
    if (bd->isGeneric) {
        return;
    }
    std::vector<llvm::Type *> elems;
    if (bd->isEnum()) {
        auto ed = dynamic_cast<EnumDecl *>(bd);
        //ordinal, i32
        elems.push_back(getInt(32));
        //data, i8*
        elems.push_back(llvm::ArrayType::get(getInt(8), getSize(ed) / 8));
    } else {
        auto td = dynamic_cast<StructDecl *>(bd);
        for (auto &field : td->fields) {
            elems.push_back(mapType(field->type));
        }
    }
    auto mangled = mangle(bd->type);
    auto ty = llvm::StructType::create(*ctx, elems, mangled);
    classMap[mangled] = ty;
}

bool isSame(Type *type, BaseDecl *decl) {
    return type->print() == decl->type->print();
}

void sort(std::vector<BaseDecl *> &list) {
    std::sort(list.begin(), list.end(), [](BaseDecl *a, BaseDecl *b) {
        if (b->isEnum()) {
            auto ed = dynamic_cast<EnumDecl *>(b);
            for (auto variant : ed->variants) {
                for (auto &f : variant->fields) {
                    if (isSame(f->type, a)) return true;
                }
            }
        } else {
            auto td = dynamic_cast<StructDecl *>(b);
            for (auto &field : td->fields) {
                if (isSame(field->type, a)) {
                    return true;
                }
            }
        }
        return false;
    });
}

std::vector<Method *> getMethods(Unit *unit) {
    std::vector<Method *> list;
    for (auto &item : unit->items) {
        if (item->isMethod()) {
            auto m = dynamic_cast<Method *>(item.get());
            list.push_back(m);
        } else if (item->isImpl()) {
            auto impl = dynamic_cast<Impl *>(item.get());
            if (!impl->type->typeArgs.empty()) { continue; }
            for (auto &m : impl->methods) {
                list.push_back(m.get());
            }
        }
    }
    return list;
}

void Compiler::createProtos() {
    std::vector<BaseDecl *> list;
    for (auto bd : getTypes(unit.get())) {
        if (bd->isGeneric) continue;
        list.push_back(bd);
    }
    for (auto gt : resolv->genericTypes) {
        list.push_back(gt);
    }
    for (auto bd : resolv->usedTypes) {
        list.push_back(bd);
    }
    sort(list);
    for (auto bd : list) {
        makeDecl(bd);
    }
    //methods
    for (auto m : getMethods(unit.get())) {
        make_proto(m);
    }
    //generic methods from resolver
    for (auto gm : resolv->generatedMethods) {
        make_proto(gm);
    }
    for (auto m : resolv->usedMethods) {
        make_proto(m);
    }

    make_printf();
    make_exit();
    make_malloc();
}

void Compiler::initParams(Method *m) {
    //alloc
    auto ff = funcMap[mangle(m)];
    if (m->self) {
        llvm::Value *ptr = ff->getArg(0);
        if (isStruct(m->self->type.get())) {
        } else {
            auto ty = mapType(m->self->type.get());
            ptr = Builder->CreateAlloca(ty);
        }
        NamedValues[m->self->name] = ptr;
    }
    for (auto prm : m->params) {
        //non mut structs dont need alloc
        if (isStruct(prm->type.get()) && resolv->mut_params.count(prm) == 0) continue;
        auto ty = mapType(prm->type.get());
        auto ptr = Builder->CreateAlloca(ty);
        NamedValues[prm->name] = ptr;
    }
    //store
    int argIdx = 0;
    if (m->self) {
        if (!isStruct(m->self->type.get())) {
            auto ptr = NamedValues[m->self->name];
            auto val = ff->getArg(argIdx);
            Builder->CreateStore(val, ptr);
            print("store: " + mangle(m));
        }
        argIdx++;
    }
    for (auto i = 0; i < m->params.size(); i++) {
        auto prm = m->params[i];
        auto val = ff->getArg(argIdx++);
        if (isStruct(prm->type.get())) {
            if (resolv->mut_params.count(prm) == 0) {
                NamedValues[prm->name] = val;
            } else {
                //memcpy
                Builder->CreateMemCpy(NamedValues[prm->name], llvm::MaybeAlign(0), val, llvm::MaybeAlign(0), getSize(prm->type.get()) / 8);
            }
        } else {
            auto ptr = NamedValues[prm->name];
            Builder->CreateStore(val, ptr);
        }
    }
}

bool isReturnLast(Statement *stmt) {
    if (isRet(stmt)) {
        return true;
    }
    auto block = dynamic_cast<Block *>(stmt);
    if (block && !block->list.empty()) {
        auto &last = block->list.back();
        if (isRet(last.get())) {
            return true;
        }
    }
    return false;
}

bool doesAlloc(Expression *e) {
    auto obj = dynamic_cast<ObjExpr *>(e);
    if (obj) {
        return !obj->isPointer;
    }
    auto aa = dynamic_cast<ArrayAccess *>(e);
    if (aa) {
        return aa->index2.get() != nullptr;
    }
    return dynamic_cast<Type *>(e) || dynamic_cast<ArrayExpr *>(e);
}

class AllocCollector : public Visitor {
public:
    Compiler *compiler;

    void *visitVarDecl(VarDecl *node) override {
        for (auto f : node->decl->list) {
            auto type = f->type ? f->type.get() : compiler->resolv->resolve(f->rhs.get())->type;
            llvm::Value *ptr;
            if (doesAlloc(f->rhs.get())) {
                //auto alloc
                ptr = (llvm::Value *) f->rhs->accept(this);
            } else {
                //manual alloc, prims, struct copy
                auto ty = compiler->mapType(type);
                ptr = Builder->CreateAlloca(ty);
                allocArr.push_back(ptr);
            }
            ptr->setName(f->name);
            NamedValues[f->name] = ptr;
        }
        return nullptr;
    }
    void *visitType(Type *node) override {
        if (!node->scope) {
            return nullptr;
        }
        //todo
        if (node->isPointer()) {
            return nullptr;
        }
        auto r = compiler->resolv->resolve(node);
        auto ty = compiler->mapType(node->scope);
        auto ptr = Builder->CreateAlloca(ty, (unsigned) 0);
        allocArr.push_back(ptr);
        return ptr;
    }
    void *visitObjExpr(ObjExpr *node) override {
        if (node->isPointer) {
            //todo this too
            return nullptr;
        }
        auto ty = compiler->mapType(compiler->resolv->resolve(node)->type);
        auto ptr = Builder->CreateAlloca(ty, (unsigned) 0);
        allocArr.push_back(ptr);
        /*for (auto &e : node->entries) {
            e.value->accept(this);
        }*/
        return ptr;
    }
    void *visitArrayExpr(ArrayExpr *node) {
        auto r = compiler->resolv->resolve(node);
        auto ty = compiler->mapType(r->type);
        auto ptr = Builder->CreateAlloca(ty, (unsigned) 0);
        allocArr.push_back(ptr);
        for (auto e : node->list) {
            auto mc = dynamic_cast<MethodCall *>(e);
            if (mc) {
                //throw std:: runtime_error("mc to array");
            } else {
                //e->accept(this);
            }
        }
        return ptr;
    }
    void *visitArrayAccess(ArrayAccess *node) {
        if (node->index2) {
            auto ptr = Builder->CreateAlloca(sliceType, (unsigned) 0);
            allocArr.push_back(ptr);
            node->array->accept(this);
            node->index2->accept(this);
            node->index->accept(this);
            return ptr;
        } else {
            node->array->accept(this);
            node->index->accept(this);
        }
        return nullptr;
    }
    void *visitBlock(Block *node) override {
        for (auto &s : node->list) {
            s->accept(this);
        }
        return nullptr;
    }
    void *visitWhileStmt(WhileStmt *node) override {
        node->body->accept(this);
        return nullptr;
    }
    void *visitIfStmt(IfStmt *node) override {
        node->thenStmt->accept(this);
        if (node->elseStmt) {
            node->elseStmt->accept(this);
        }
        return nullptr;
    }
    void *visitReturnStmt(ReturnStmt *node) override {
        if (node->expr) {
            node->expr->accept(this);
        }
        return nullptr;
    }
    void *visitExprStmt(ExprStmt *node) override {
        node->expr->accept(this);
        return nullptr;
    }
    void *visitAssign(Assign *node) override {
        node->right->accept(this);
        return nullptr;
    }
    void *visitSimpleName(SimpleName *node) override {
        return nullptr;
    }
    void *visitInfix(Infix *node) {
        node->left->accept(this);
        node->right->accept(this);
        return nullptr;
    }
    void *visitAssertStmt(AssertStmt *node) {
        node->expr->accept(this);
        return nullptr;
    }
    void *visitLiteral(Literal *node) {
        return nullptr;
    }
    void *visitRefExpr(RefExpr *node) {
        node->expr->accept(this);
        return nullptr;
    }
    void *visitDerefExpr(DerefExpr *node) {
        node->expr->accept(this);
        return nullptr;
    }
    void *visitUnary(Unary *node) {
        node->expr->accept(this);
        return nullptr;
    }
    void *visitMethodCall(MethodCall *node) {
        if (node->scope) node->scope->accept(this);
        for (auto a : node->args) {
            a->accept(this);
        }
        return nullptr;
    }
    void *visitFieldAccess(FieldAccess *node) {
        node->scope->accept(this);
        return nullptr;
    }
    void *visitParExpr(ParExpr *node) {
        node->expr->accept(this);
        return nullptr;
    }
    void *visitAsExpr(AsExpr *node) {
        node->expr->accept(this);
        return nullptr;
    }
    void *visitIsExpr(IsExpr *node) {
        node->expr->accept(this);
        return nullptr;
    }
    void *visitIfLetStmt(IfLetStmt *node) {
        node->rhs->accept(this);
        node->thenStmt->accept(this);
        if (node->elseStmt) node->elseStmt->accept(this);
        return nullptr;
    }
    void *visitContinueStmt(ContinueStmt *node) {
        return nullptr;
    }
    void *visitBreakStmt(BreakStmt *node) {
        return nullptr;
    }
};

void Compiler::makeLocals(Statement *st) {
    allocIdx = 0;
    allocArr.clear();
    auto col = new AllocCollector;
    col->compiler = this;
    st->accept(col);
}

void Compiler::genCode(std::unique_ptr<Method> &m) {
    genCode(m.get());
}

void Compiler::genCode(Method *m) {
    if (m->isGeneric) {
        return;
    }
    resolv->curMethod = m;
    curMethod = m;
    resolv->scopes.push_back(resolv->methodScopes[m]);
    func = funcMap[mangle(m)];
    auto bb = llvm::BasicBlock::Create(*ctx, "", func);
    Builder->SetInsertPoint(bb);
    NamedValues.clear();
    initParams(m);
    makeLocals(m->body.get());
    m->body->accept(this);
    if (!isReturnLast(m->body.get()) && m->type->print() == "void") {
        Builder->CreateRetVoid();
    }
    llvm::verifyFunction(*func);
    resolv->dropScope();

    func = nullptr;
    curMethod = nullptr;
}

void Compiler::compileAll() {
    init();
    std::string cmd = "clang-13 ";
    for (const auto &e : fs::recursive_directory_iterator(srcDir)) {
        if (e.is_directory()) continue;
        auto obj = compile(e.path().string());
        if (obj) {
            cmd.append(obj.value());
            cmd.append(" ");
        }
    }
    system((cmd + " && ./a.out").c_str());
}

void Compiler::init() {
    TargetTriple = llvm::sys::getDefaultTargetTriple();
    llvm::InitializeAllTargetInfos();
    llvm::InitializeAllTargets();
    llvm::InitializeAllTargetMCs();
    llvm::InitializeAllAsmParsers();
    llvm::InitializeAllAsmPrinters();

    std::string Error;
    //llvm::TargetRegistry::printRegisteredTargetsForVersion(llvm::outs());
    auto Target = llvm::TargetRegistry::lookupTarget(TargetTriple, Error);
    std::cout << "triple: " << TargetTriple << std::endl;
    std::cout << "target: " << Target->getName() << std::endl;

    if (!Target) {
        throw std::runtime_error(Error);
    }
    auto CPU = "generic";
    auto Features = "";

    llvm::TargetOptions opt;
    auto RM = llvm::Optional<llvm::Reloc::Model>();
    TargetMachine = Target->createTargetMachine(TargetTriple, CPU, Features, opt, RM);
}

void Compiler::emit(std::string &Filename) {
    //todo init once
    mod->setDataLayout(TargetMachine->createDataLayout());
    mod->setTargetTriple(TargetTriple);

    std::error_code EC;
    llvm::raw_fd_ostream dest(Filename, EC, llvm::sys::fs::OF_None);

    if (EC) {
        std::cerr << "Could not open file: " << EC.message();
        exit(1);
    }

    //TargetMachine->setOptLevel(llvm::CodeGenOpt::Aggressive);
    llvm::legacy::PassManager pass;

    if (TargetMachine->addPassesToEmitFile(pass, dest, nullptr, llvm::CGFT_ObjectFile)) {
        std::cerr << "TargetMachine can't emit a file of this type";
        exit(1);
    }
    pass.run(*mod);

    dest.flush();
    dest.close();
    std::cout << "writing " << Filename << std::endl;
}

std::optional<std::string> Compiler::compile(const std::string &path) {
    auto name = getName(path);
    if (path.compare(path.size() - 2, 2, ".x") != 0) {
        //copy res
        std::ifstream src;
        src.open(path, src.binary);
        std::ofstream trg;
        trg.open(outDir + "/" + name, trg.binary);
        trg << src.rdbuf();
        return {};
    }
    std::cout << "compiling " << path << std::endl;
    resolv = Resolver::getResolver(path, srcDir);
    unit = resolv->unit;
    resolv->resolveAll();

    NamedValues.clear();
    InitializeModule(name);
    make_slice_type();
    createProtos();

    for (auto &m : getMethods(unit.get())) {
        genCode(m);
    }
    for (auto m : resolv->generatedMethods) {
        genCode(m);
    }
    std::error_code EC;
    auto noext = trimExtenstion(name);


    llvm::verifyModule(*mod, &llvm::outs());

    //todo fullpath
    auto outFile = noext + ".o";
    emit(outFile);

    auto llvm_file = noext + ".ll";
    llvm::raw_fd_ostream fd(llvm_file, EC);
    mod->print(fd, nullptr);
    print("writing " + llvm_file);
    return outFile;
}

llvm::Value *Compiler::gen(Expression *expr) {
    return (llvm::Value *) expr->accept(this);
}
llvm::Value *Compiler::gen(std::unique_ptr<Expression> &expr) {
    return (llvm::Value *) expr->accept(this);
}

llvm::BasicBlock *getBB() {
    return Builder->GetInsertBlock();
}

void *Compiler::visitBlock(Block *b) {
    for (auto &s : b->list) {
        s->accept(this);
    }
    return nullptr;
}

void *Compiler::visitReturnStmt(ReturnStmt *t) {
    if (t->expr) {
        if (isStruct(curMethod->type.get())) {
            //rvo
            if (dynamic_cast<ArrayExpr *>(t->expr.get()) || dynamic_cast<ObjExpr *>(t->expr.get())) {
                Builder->CreateRet(load(gen(t->expr.get())));
            } else {
                Builder->CreateRet(loadPtr(t->expr.get()));
            }
            //Builder->CreateRetVoid();
        } else {
            auto type = resolv->resolve(curMethod->type.get())->type;
            Builder->CreateRet(cast(t->expr.get(), type));
        }
    } else {
        Builder->CreateRetVoid();
    }
    return nullptr;
}

void *Compiler::visitExprStmt(ExprStmt *b) {
    return b->expr->accept(this);
}

void *Compiler::visitParExpr(ParExpr *i) {
    return i->expr->accept(this);
}

llvm::Value *Compiler::andOr(Expression *left, Expression *right, bool isand) {
    auto l = loadPtr(left);
    auto bb = getBB();
    auto then = llvm::BasicBlock::Create(*ctx, "", func);
    auto next = llvm::BasicBlock::Create(*ctx, "");
    if (isand) {
        Builder->CreateCondBr(branch(l), then, next);
    } else {
        Builder->CreateCondBr(branch(l), next, then);
    }
    Builder->SetInsertPoint(then);
    auto r = loadPtr(right);
    auto rbit = Builder->CreateTrunc(r, getInt(1));
    Builder->CreateBr(next);
    Builder->SetInsertPoint(next);
    func->getBasicBlockList().push_back(next);
    auto phi = Builder->CreatePHI(getInt(1), 2);
    phi->addIncoming(isand ? Builder->getFalse() : Builder->getTrue(), bb);
    phi->addIncoming(rbit, then);
    return Builder->CreateZExt(phi, getInt(1));
}

llvm::Value *extend(llvm::Value *val, Type *type, Compiler *c) {
    int src = val->getType()->getPrimitiveSizeInBits();
    int bits = c->getSize(type);
    if (src < bits) {
        return Builder->CreateZExt(val, getInt(bits));
    }
    if (src > bits) {
        return Builder->CreateTrunc(val, getInt(bits));
    }
    return val;
}

llvm::Value *Compiler::cast(Expression *expr, Type *type) {
    auto lit = dynamic_cast<Literal *>(expr);
    if (lit && lit->type == Literal::INT) {
        auto bits = getSize(type);
        if (lit->suffix) {
            bits = getSize(lit->suffix.get());
        }
        auto intType = llvm::IntegerType::get(*ctx, bits);
        return llvm::ConstantInt::get(intType, atoi(lit->val.c_str()));
    }
    auto val = loadPtr(expr);
    if (type->isPrim()) {
        return extend(val, type, this);
    }
    return val;
}

void *Compiler::visitInfix(Infix *i) {
    if (i->op == "&&") {
        return andOr(i->left, i->right, true);
    }
    if (i->op == "||") {
        return andOr(i->left, i->right, false);
    }
    //print("infix: " + i->print());
    auto t1 = resolv->resolve(i->left)->type->print();
    auto t2 = resolv->resolve(i->right)->type->print();
    auto t3 = t1 == "bool" ? new Type("i1") : binCast(t1, t2)->type;
    auto l = cast(i->left, t3);
    auto r = cast(i->right, t3);
    if (isComp(i->op)) {
        if (i->op == "==") {
            return Builder->CreateCmp(llvm::CmpInst::ICMP_EQ, l, r);
        }
        if (i->op == "!=") {
            return Builder->CreateCmp(llvm::CmpInst::ICMP_NE, l, r);
        }
        if (i->op == "<") {
            return Builder->CreateCmp(llvm::CmpInst::ICMP_SLT, l, r);
        }
        if (i->op == ">") {
            return Builder->CreateCmp(llvm::CmpInst::ICMP_SGT, l, r);
        }
        if (i->op == "<=") {
            return Builder->CreateCmp(llvm::CmpInst::ICMP_SLE, l, r);
        }
        if (i->op == ">=") {
            return Builder->CreateCmp(llvm::CmpInst::ICMP_SGE, l, r);
        }
    }
    if (i->op == "+") {
        return Builder->CreateNSWAdd(l, r);
    }
    if (i->op == "-") {
        return Builder->CreateNSWSub(l, r);
    }
    if (i->op == "*") {
        return Builder->CreateNSWMul(l, r);
    }
    if (i->op == "/") {
        return Builder->CreateSDiv(l, r);
    }
    if (i->op == "%") {
        return Builder->CreateSRem(l, r);
    }
    if (i->op == "^") {
        return Builder->CreateXor(l, r);
    }
    if (i->op == "&") {
        return Builder->CreateAnd(l, r);
    }
    if (i->op == "|") {
        return Builder->CreateOr(l, r);
    }
    if (i->op == "<<") {
        return Builder->CreateShl(l, r);
    }
    if (i->op == ">>") {
        return Builder->CreateAShr(l, r);
    }
    throw std::runtime_error("infix: " + i->print());
}

void *Compiler::visitUnary(Unary *u) {
    auto v = gen(u->expr);
    auto val = v;
    if (isVar(u->expr)) {
        val = load(v);
    }

    if (u->op == "+") return val;
    if (u->op == "-") {
        return Builder->CreateNSWSub(makeInt(0), val);
    }
    if (u->op == "++") {
        auto tmp = Builder->CreateNSWAdd(val, makeInt(1));
        Builder->CreateStore(tmp, v);
        return tmp;
    }
    if (u->op == "--") {
        auto tmp = Builder->CreateNSWSub(val, makeInt(1));
        Builder->CreateStore(tmp, v);
        return tmp;
    }
    if (u->op == "!") {
        auto trunc = Builder->CreateTrunc(val, getInt(1));
        auto xorr = Builder->CreateXor(trunc, Builder->getTrue());
        auto zext = Builder->CreateZExt(xorr, getInt(8));
        return zext;
    }
    if (u->op == "~") {
        return Builder->CreateXor(val, makeInt(-1));
    }
    throw std::runtime_error("Unary: " + u->print());
}

void *Compiler::visitAssign(Assign *i) {
    auto l = gen(i->left);
    auto val = l;
    auto lt = resolv->resolve(i->left);
    auto r = cast(i->right, lt->type);
    if (i->op == "=") {
        if (isStruct(lt->type)) {
            return Builder->CreateMemCpy(l, llvm::MaybeAlign(0), r, llvm::MaybeAlign(0), getSize(lt->type) / 8);
        } else {
            return Builder->CreateStore(r, l);
        }
    }
    if (isVar(i->left)) {
        val = load(l);
    }
    if (i->op == "+=") {
        auto tmp = Builder->CreateNSWAdd(val, r);
        return Builder->CreateStore(tmp, l);
    }
    if (i->op == "-=") {
        auto tmp = Builder->CreateNSWSub(val, r);
        return Builder->CreateStore(tmp, l);
    }
    if (i->op == "*=") {
        auto tmp = Builder->CreateNSWMul(val, r);
        return Builder->CreateStore(tmp, l);
    }
    if (i->op == "/=") {
        auto tmp = Builder->CreateSDiv(val, r);
        return Builder->CreateStore(tmp, l);
    }
    throw std::runtime_error("assign: " + i->print());
}

void *Compiler::visitSimpleName(SimpleName *n) {
    auto it = NamedValues.find(n->name);
    if (it != NamedValues.end()) {
        return it->second;
    }
    throw std::runtime_error("compiler bug; sym not found: " + n->name + " in " + curMethod->name);
}

llvm::Value *callMalloc(llvm::Value *sz) {
    std::vector<llvm::Value *> args;
    args.push_back(sz);
    return Builder->CreateCall(mallocf, args);
}

void *callPanic(MethodCall *mc, Compiler *c) {
    std::string message;
    if (mc->args.empty()) {
        message = "panic";
    } else {
        auto val = dynamic_cast<Literal *>(mc->args[0])->val;
        message = "panic: " + val.substr(1, val.size() - 2);
    }
    message.append("\n");
    auto str = Builder->CreateGlobalStringPtr(message);
    std::vector<llvm::Value *> args;
    args.push_back(str);
    if (!mc->args.empty()) {
        for (int i = 1; i < mc->args.size(); ++i) {
            auto a = mc->args[i];
            auto av = c->loadPtr(a);
            args.push_back(av);
        }
    }
    auto call = Builder->CreateCall(printf_proto, args);
    std::vector<llvm::Value *> exit_args = {makeInt(1)};
    Builder->CreateCall(exit_proto, exit_args);
    Builder->CreateUnreachable();
    return Builder->getVoidTy();
}

void *Compiler::visitMethodCall(MethodCall *mc) {
    llvm::Function *f;
    std::vector<llvm::Value *> args;
    Method *target = nullptr;
    if (mc->name == "print") {
        f = printf_proto;
    } else if (mc->name == "malloc") {
        f = mallocf;
        auto lt = new Type;
        lt->name = "i64";
        auto size = cast(mc->args[0], lt);
        if (!mc->typeArgs.empty()) {
            int typeSize = getSize(mc->typeArgs[0]) / 8;
            size = Builder->CreateNSWMul(size, makeInt(typeSize, 64));
        }
        auto call = callMalloc(size);
        auto rt = resolv->resolve(mc);
        return Builder->CreateBitCast(call, mapType(rt->type));
    } else if (mc->name == "panic") {
        return callPanic(mc, this);
    } else {
        auto rt = resolv->resolve(mc);
        target = rt->targetMethod;
        f = funcMap[mangle(target)];
    }
    int paramIdx = 0;
    if (target && target->self && !dynamic_cast<Type *>(mc->scope.get())) {
        //add this object
        auto obj = gen(mc->scope.get());
        auto scope_type = resolv->resolve(mc->scope.get())->type;
        if (scope_type->isPointer() || (scope_type->isPrim() && isVar(mc->scope.get()))) {
            //auto deref
            obj = Builder->CreateLoad(obj->getType()->getPointerElementType(), obj);
        }
        args.push_back(obj);
        paramIdx++;
    }
    std::vector<Param *> params;
    if (target) {
        if (target->self) {
            params.push_back(target->self.get());
        }
        for (auto p : target->params) {
            params.push_back(p);
        }
        for (int i = 0, e = mc->args.size(); i != e; ++i) {
            auto a = mc->args[i];
            llvm::Value *av;
            if (isStruct(params[paramIdx]->type.get())) {
                av = gen(a);
            } else {
                av = cast(a, params[paramIdx]->type.get());
            }
            args.push_back(av);
            paramIdx++;
        }
    } else {
        for (auto a : mc->args) {
            auto av = loadPtr(a);
            args.push_back(av);
        }
    }
    return Builder->CreateCall(f, args);
}

void *Compiler::visitLiteral(Literal *n) {
    if (n->type == Literal::STR) {
        auto trimmed = n->val.substr(1, n->val.size() - 2);
        return makeStr(trimmed);
    } else if (n->type == Literal::INT) {
        auto bits = 32;
        if (n->suffix) {
            bits = getSize(n->suffix.get());
        }
        auto intType = llvm::IntegerType::get(*ctx, bits);
        return llvm::ConstantInt::get(intType, atoi(n->val.c_str()));
    } else if (n->type == Literal::BOOL) {
        return n->val == "true" ? Builder->getTrue() : Builder->getFalse();
    }
    throw std::runtime_error("literal: " + n->print());
}

void *Compiler::visitAssertStmt(AssertStmt *n) {
    auto str = n->expr->print();
    auto cond = loadPtr(n->expr.get());
    auto then = llvm::BasicBlock::Create(*ctx, "", func);
    auto next = llvm::BasicBlock::Create(*ctx, "");
    Builder->CreateCondBr(branch(cond), next, then);
    Builder->SetInsertPoint(then);
    //print error and exit
    auto msg = std::string("assertion ") + str + " failed\n";
    std::vector<llvm::Value *> pr_args = {makeStr(msg)};
    Builder->CreateCall(printf_proto, pr_args, "");
    std::vector<llvm::Value *> args = {makeInt(1)};
    Builder->CreateCall(exit_proto, args);
    Builder->CreateUnreachable();
    Builder->SetInsertPoint(next);
    func->getBasicBlockList().push_back(next);
    return nullptr;
}

void *Compiler::visitVarDecl(VarDecl *n) {
    for (auto f : n->decl->list) {
        auto type = f->type ? f->type.get() : resolv->resolve(f->rhs.get())->type;
        auto ptr = NamedValues[f->name];
        //no unnecessary alloc
        if (doesAlloc(f->rhs.get())) {
            auto val = gen(f->rhs.get());
            continue;
        }
        allocIdx++;
        if (isStruct(type)) {
            //memcpy
            auto val = gen(f->rhs.get());
            if (val->getType()->isPointerTy()) {
                Builder->CreateMemCpy(ptr, llvm::MaybeAlign(0), val, llvm::MaybeAlign(0), getSize(type) / 8);
            } else {
                Builder->CreateStore(val, ptr);
            }
        } else {
            auto val = cast(f->rhs.get(), type);
            Builder->CreateStore(val, ptr);
        }
    }
    return nullptr;
}

void *Compiler::visitRefExpr(RefExpr *n) {
    auto inner = gen(n->expr);
    //todo rvalue
    auto pt = inner->getType();
    //todo not needed for name,already ptr
    return inner;
}

void *Compiler::visitDerefExpr(DerefExpr *n) {
    auto val = gen(n->expr);
    auto ty = val->getType()->getPointerElementType();
    //todo struct memcpy
    return Builder->CreateLoad(ty, val);
}

EnumDecl *findEnum(Type *type, Resolver *resolv) {
    auto rt = (RType *) type->accept(resolv);
    return dynamic_cast<EnumDecl *>(rt->targetDecl);
}

void setOrdinal(int index, llvm::Value *ptr) {
    auto ordPtr = Builder->CreateStructGEP(ptr->getType()->getPointerElementType(), ptr, 0);
    Builder->CreateStore(makeInt(index), ordPtr);
}

void *Compiler::visitObjExpr(ObjExpr *n) {
    auto tt = resolv->resolve(n);
    llvm::Value *ptr;
    if (n->isPointer) {
        auto ty = mapType(tt->type);
        ptr = callMalloc(makeInt(getSize(tt->targetDecl) / 8, 64));
        ptr = Builder->CreateBitCast(ptr, ty);
    } else {
        ptr = allocArr[allocIdx++];
    }
    object(n, ptr, tt);
    return ptr;
}

int Compiler::getOffset(EnumVariant *variant, int index) {
    int offset = 0;
    for (int i = 0; i < index; i++) {
        offset += getSize(variant->fields[i]->type) / 8;
    }
    return offset;
}

void Compiler::setField(Expression *expr, Type *type, bool do_cast, llvm::Value *entPtr) {
    auto targetTy = mapType(type);
    if (do_cast) {
        entPtr = Builder->CreateBitCast(entPtr, targetTy->getPointerTo());
    }
    if (doesAlloc(expr)) {
        child(expr, entPtr);
    } else if (isStruct(type)) {
        auto val = gen(expr);
        Builder->CreateMemCpy(entPtr, llvm::MaybeAlign(0), val, llvm::MaybeAlign(0), getSize(type) / 8);
    } else {
        auto val = cast(expr, type);
        Builder->CreateStore(val, entPtr);
    }
}

void Compiler::object(ObjExpr *n, llvm::Value *ptr, RType *tt) {
    auto ty = mapType(tt->type);
    if (tt->targetDecl->isEnum()) {
        //enum
        auto decl = dynamic_cast<EnumDecl *>(tt->targetDecl);
        auto variant_index = Resolver::findVariant(decl, n->type->name);

        setOrdinal(variant_index, ptr);
        auto dataPtr = Builder->CreateStructGEP(ptr->getType()->getPointerElementType(), ptr, 1);
        auto variant = decl->variants[variant_index];
        for (int i = 0; i < n->entries.size(); i++) {
            auto &e = n->entries[i];
            int index;
            if (e.hasKey()) {
                index = fieldIndex(variant->fields, e.key, new Type(decl->type, variant->name));
            } else {
                index = i;
            }
            auto &field = variant->fields[index];
            std::vector<llvm::Value *> entIdx = {makeInt(0), makeInt(getOffset(variant, index))};
            auto entPtr = Builder->CreateGEP(dataPtr->getType()->getPointerElementType(), dataPtr, entIdx);
            setField(e.value, field->type, true, entPtr);
        }
    } else {
        //class
        auto decl = dynamic_cast<StructDecl *>(tt->targetDecl);
        for (int i = 0; i < n->entries.size(); i++) {
            auto &e = n->entries[i];
            int index;
            if (e.hasKey()) {
                index = fieldIndex(decl->fields, e.key, decl->type);
            } else {
                index = i;
            }
            auto &field = decl->fields[index];
            auto eptr = Builder->CreateStructGEP(ptr->getType()->getPointerElementType(), ptr, index);
            setField(e.value, field->type, false, eptr);
        }
    }
}

void simpleVariant(Type *n, llvm::Value *ptr, Resolver *resolv) {
    auto decl = findEnum(n->scope, resolv);
    int index = Resolver::findVariant(decl, n->name);
    setOrdinal(index, ptr);
}

void *Compiler::visitType(Type *n) {
    if (!n->scope) {
        throw std::runtime_error("type has no scope");
    }
    //enum variant without struct
    auto ptr = allocArr[allocIdx++];
    simpleVariant(n, ptr, resolv.get());
    return ptr;
}

void *Compiler::visitFieldAccess(FieldAccess *n) {
    auto rt = resolv->resolve(n->scope);
    if (rt->type->isSlice()) {
        auto scopeVar = gen(n->scope);
        return Builder->CreateStructGEP(scopeVar->getType()->getPointerElementType(), scopeVar, SLICE_LEN_INDEX);
    }
    auto decl = rt->targetDecl;
    int index;
    if (decl->isEnum()) {
        index = 0;
    } else {
        auto td = dynamic_cast<StructDecl *>(decl);
        index = fieldIndex(td->fields, n->name, td->type);
    }
    auto scopeVar = gen(n->scope);
    auto ty = scopeVar->getType()->getPointerElementType();
    if (dynamic_cast<PointerType *>(rt->type)) {
        //auto deref
        auto load = Builder->CreateLoad(ty, scopeVar);
        return Builder->CreateStructGEP(load->getType()->getPointerElementType(), load, index);

    } else {
        return Builder->CreateStructGEP(scopeVar->getType()->getPointerElementType(), scopeVar, index);
    }
}

void *Compiler::visitIfStmt(IfStmt *b) {
    auto cond = branch(loadPtr(b->expr));
    auto then = llvm::BasicBlock::Create(*ctx, "", func);
    llvm::BasicBlock *elsebb;
    auto next = llvm::BasicBlock::Create(*ctx, "");
    if (b->elseStmt) {
        elsebb = llvm::BasicBlock::Create(*ctx, "");
        Builder->CreateCondBr(cond, then, elsebb);
    } else {
        Builder->CreateCondBr(cond, then, next);
    }
    Builder->SetInsertPoint(then);
    b->thenStmt->accept(this);
    if (!isReturnLast(b->thenStmt.get())) {
        Builder->CreateBr(next);
    }
    if (b->elseStmt) {
        Builder->SetInsertPoint(elsebb);
        func->getBasicBlockList().push_back(elsebb);
        b->elseStmt->accept(this);
        if (!isReturnLast(b->elseStmt.get())) {
            Builder->CreateBr(next);
        }
    }
    Builder->SetInsertPoint(next);
    func->getBasicBlockList().push_back(next);
    return nullptr;
}

void *Compiler::visitIfLetStmt(IfLetStmt *b) {
    auto rhs = gen(b->rhs);
    std::vector<llvm::Value *> idx = {makeInt(0), makeInt(0)};
    auto ty = rhs->getType()->getPointerElementType();
    auto ordptr = Builder->CreateStructGEP(ty, rhs, 0);
    auto ord = Builder->CreateLoad(getInt(32), ordptr);
    auto decl = findEnum(b->type->scope, resolv.get());
    auto index = Resolver::findVariant(decl, b->type->name);
    auto cmp = Builder->CreateCmp(llvm::CmpInst::ICMP_EQ, ord, makeInt(index));

    auto then = llvm::BasicBlock::Create(*ctx, "", func);
    llvm::BasicBlock *elsebb;
    auto next = llvm::BasicBlock::Create(*ctx, "");
    if (b->elseStmt) {
        elsebb = llvm::BasicBlock::Create(*ctx, "");
        Builder->CreateCondBr(branch(cmp), then, elsebb);
    } else {
        Builder->CreateCondBr(branch(cmp), then, next);
    }
    Builder->SetInsertPoint(then);

    auto variant = decl->variants[index];
    if (!variant->fields.empty()) {
        //declare vars
        auto &params = variant->fields;
        auto dataPtr = Builder->CreateStructGEP(ty, rhs, 1);
        int offset = 0;
        for (int i = 0; i < params.size(); i++) {
            //regular var decl
            auto &prm = params[i];
            auto argName = b->args[i];
            std::vector<llvm::Value *> idx = {makeInt(0), makeInt(offset)};
            auto ptr = Builder->CreateGEP(dataPtr->getType()->getPointerElementType(), dataPtr, idx);
            //bitcast to real type
            auto targetTy = mapType(prm->type)->getPointerTo();
            auto ptrReal = Builder->CreateBitCast(ptr, targetTy);
            NamedValues[argName] = ptrReal;
            offset += getSize(prm->type) / 8;
        }
    }
    b->thenStmt->accept(this);
    //clear params
    for (auto &p : b->args) {
        NamedValues.erase(p);
    }
    if (!isReturnLast(b->thenStmt.get())) {
        Builder->CreateBr(next);
    }
    if (b->elseStmt) {
        Builder->SetInsertPoint(elsebb);
        func->getBasicBlockList().push_back(elsebb);
        b->elseStmt->accept(this);
        if (!isReturnLast(b->elseStmt.get())) {
            Builder->CreateBr(next);
        }
    }
    Builder->SetInsertPoint(next);
    func->getBasicBlockList().push_back(next);
    return nullptr;
}

void *Compiler::visitIsExpr(IsExpr *ie) {
    auto decl = findEnum(ie->type->scope, resolv.get());
    auto val = gen(ie->expr);
    auto ordptr = Builder->CreateStructGEP(val->getType()->getPointerElementType(), val, 0);
    auto ord = Builder->CreateLoad(getInt(32), ordptr);
    auto index = Resolver::findVariant(decl, ie->type->name);
    return Builder->CreateCmp(llvm::CmpInst::ICMP_EQ, ord, makeInt(index));
}

void *Compiler::visitAsExpr(AsExpr *e) {
    auto val = gen(e->expr);
    auto ty = resolv->resolve(e->type);
    return extend(val, ty->type, this);
}

void *Compiler::visitArrayAccess(ArrayAccess *node) {
    auto arr = resolv->resolve(node->array);
    auto type = arr->type;
    if (node->index2) {
        auto sp = allocArr.at(allocIdx++);
        auto val_start = cast(node->index, new Type("i32"));
        //set array ptr
        auto pp = Builder->CreateStructGEP(sp->getType()->getPointerElementType(), sp, 0);
        auto src = gen(node->array);
        std::vector<llvm::Value *> off = {makeInt(0, 32), val_start};
        src = Builder->CreateGEP(src->getType()->getPointerElementType(), src, off, "off");
        src = Builder->CreateBitCast(src, getInt(8)->getPointerTo());
        Builder->CreateStore(src, pp);
        //set len
        auto lenp = Builder->CreateStructGEP(sp->getType()->getPointerElementType(), sp, SLICE_LEN_INDEX);
        auto val_end = cast(node->index2.get(), new Type("i32"));
        auto len = Builder->CreateSub(val_end, val_start);
        Builder->CreateStore(len, lenp);
        return sp;
    }
    auto src = gen(node->array);
    if (type->isPointer()) {
        auto pt = dynamic_cast<PointerType *>(type);
        if (pt->type->isArray() || pt->type->isSlice()) {
            src = load(src);
            type = pt->type;
        }
    }
    std::vector<llvm::Value *> idx = {cast(node->index, new Type("i32"))};
    if (type->isArray()) {
        auto ty = mapType(type);
        idx.insert(idx.begin(), makeInt(0, 32));
        ty = src->getType()->getPointerElementType();
        return Builder->CreateGEP(ty, src, idx);
    } else if (type->isSlice()) {
        auto elem = dynamic_cast<SliceType *>(type)->type;
        auto elemty = mapType(elem);
        auto sp = src;
        //read ptr
        auto arr = Builder->CreateStructGEP(sp->getType()->getPointerElementType(), sp, 0, "arr1");
        arr = Builder->CreateBitCast(arr, arr->getType()->getPointerTo());
        arr = Builder->CreateLoad(arr->getType()->getPointerElementType(), arr);
        arr = Builder->CreateBitCast(arr, elemty->getPointerTo());
        //idx.insert(idx.begin(), makeInt(0, 64));
        auto tt = arr->getType()->getPointerElementType();
        return Builder->CreateGEP(tt, arr, idx);
    } else {
        src = load(src);
        return Builder->CreateGEP(src->getType()->getPointerElementType(), src, idx);
    }
}

void *Compiler::visitWhileStmt(WhileStmt *node) {
    auto then = llvm::BasicBlock::Create(*ctx);
    auto condbb = llvm::BasicBlock::Create(*ctx, "", func);
    auto next = llvm::BasicBlock::Create(*ctx);
    Builder->CreateBr(condbb);
    Builder->SetInsertPoint(condbb);
    auto c = loadPtr(node->expr.get());
    Builder->CreateCondBr(branch(c), then, next);
    Builder->SetInsertPoint(then);
    func->getBasicBlockList().push_back(then);
    loops.push_back(condbb);
    loopNext.push_back(next);
    node->body->accept(this);
    loops.pop_back();
    loopNext.pop_back();
    Builder->CreateBr(condbb);
    Builder->SetInsertPoint(next);
    func->getBasicBlockList().push_back(next);
    return nullptr;
}

void *Compiler::visitContinueStmt(ContinueStmt *node) {
    Builder->CreateBr(loops.back());
    return nullptr;
}

void *Compiler::visitBreakStmt(BreakStmt *node) {
    Builder->CreateBr(loopNext.back());
    return nullptr;
}

void *Compiler::visitArrayExpr(ArrayExpr *node) {
    auto ptr = allocArr[allocIdx++];
    array(node, ptr);
    return ptr;
}

void Compiler::child(Expression *e, llvm::Value *ptr) {
    auto a = dynamic_cast<ArrayExpr *>(e);
    if (a) {
        array(a, ptr);
    }
    auto obj = dynamic_cast<ObjExpr *>(e);
    if (obj && !obj->isPointer) {
        object(obj, ptr, resolv->resolve(obj));
    }
    auto t = dynamic_cast<Type *>(e);
    if (t) {
        simpleVariant(t, ptr, resolv.get());
    }
}

void *Compiler::array(ArrayExpr *node, llvm::Value *ptr) {
    auto type = resolv->resolve(node->list[0])->type;
    if (node->isSized()) {
        //auto expr = cast(node->list[0], type);
        //create cons and memcpy
    } else {
        int i = 0;
        for (auto e : node->list) {
            std::vector<llvm::Value *> idx = {makeInt(0), makeInt(i++)};
            //getArrayElementType
            auto rt = resolv->resolve(e);
            auto elem_target = Builder->CreateGEP(ptr->getType()->getPointerElementType(), ptr, idx);
            if (doesAlloc(e)) {
                child(e, elem_target);
            } else if (isStruct(type)) {
                auto val = gen(e);
                Builder->CreateMemCpy(elem_target, llvm::MaybeAlign(0), val, llvm::MaybeAlign(0), getSize(rt->type) / 8);
            } else {
                Builder->CreateStore(cast(e, type), elem_target);
            }
        }
    }
    return ptr;
}