#include "Compiler.h"
#include "Resolver.h"
#include "parser/Ast.h"
#include "parser/Parser.h"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <unordered_map>
#include <variant>


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
#include <llvm/Target/TargetMachine.h>
#include <llvm/Target/TargetOptions.h>

namespace fs = std::filesystem;

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
llvm::Value *thisPtr = nullptr;
llvm::Function *printf_proto;
llvm::Function *exit_proto;
llvm::Function *mallocf;
int strCnt = 0;

static void InitializeModule(std::string &name) {
    ctx.release();
    mod.release();
    Builder.release();
    // Open a new context and module.
    ctx = std::make_unique<llvm::LLVMContext>();
    mod = std::make_unique<llvm::Module>(name, *ctx);

    // Create a new builder for the module.
    Builder = std::make_unique<llvm::IRBuilder<>>(*ctx);
    //strCnt = 0;
    funcMap.clear();
    classMap.clear();
}

llvm::ConstantInt *makeInt(int val) {
    auto intType = llvm::IntegerType::get(*ctx, 32);
    return llvm::ConstantInt::get(intType, val);
}

llvm::ConstantInt *makeInt(int val, int bits) {
    auto intType = llvm::IntegerType::get(*ctx, bits);
    return llvm::ConstantInt::get(intType, val);
}

llvm::Type *getTy() {
    return llvm::Type::getInt32Ty(*ctx);
}

llvm::Type *getInt(int bit) {
    return llvm::IntegerType::get(*ctx, bit);
}

Type *make(int bit) {
    auto res = new Type;
    res->name = "i" + std::to_string(bit);
    return res;
}

llvm::Type *Compiler::mapType(Type *type) {
    auto ptr = dynamic_cast<PointerType *>(type);
    if (ptr) {
        return mapType(ptr->type)->getPointerTo();
    }
    if (type->isVoid()) {
        return llvm::Type::getVoidTy(*ctx);
    }
    if (type->isPrim()) {
        auto bits = sizeMap[type->name];
        return getInt(bits);
    }
    auto s = resolv->resolveType(type)->targetDecl->name;
    auto it = classMap.find(s);
    if (it != classMap.end()) {
        return it->second;
    }
    throw std::runtime_error("mapType: " + s);
}

static int getSize(Type *type) {
    if (dynamic_cast<PointerType *>(type)) {
        return 64;
    }
    auto s = type->print();
    auto it = sizeMap.find(s);
    if (it != sizeMap.end()) return it->second;
    throw std::runtime_error("size(" + s + ")");
}

static int size(EnumDecl *e) {
    int res = 0;
    for (auto ev : e->variants) {
        if (ev->fields.empty()) continue;
        int cur = 0;
        for (auto f : ev->fields) {
            cur += getSize(f->type);
        }
        res = cur > res ? cur : res;
    }
    return res;
}
static int size(TypeDecl *td) {
    int res = 0;
    for (auto fd : td->fields) {
        res += getSize(fd->type);
    }
    return res;
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


void Compiler::make_proto(Method *m) {
    if (!m->typeArgs.empty()) {
        return;
    }
    std::vector<llvm::Type *> argTypes;
    if (isMember(m)) {
        argTypes.push_back(classMap[m->parent->name]->getPointerTo());
    }
    for (auto &prm : m->params) {
        argTypes.push_back(mapType(prm->type));
    }
    auto retType = mapType(m->type);
    auto fr = llvm::FunctionType::get(retType, argTypes, false);
    auto f = llvm::Function::Create(fr, llvm::Function::ExternalLinkage, mangle(m), mod.get());
    unsigned i = 0;
    int pi = 0;
    for (auto &a : f->args()) {
        if (i == 0 && isMember(m)) {
            a.setName("this");
        } else {
            a.setName(m->params[pi++]->name);
        }
        i++;
    }
    f->dump();
    funcMap[mangle(m)] = f;
}

void Compiler::makeDecl(BaseDecl *bd) {
    if (!bd->isResolved) {
        return;
    }
    std::vector<llvm::Type *> elems;
    auto ed = dynamic_cast<EnumDecl *>(bd);
    if (ed) {
        int sz = size(ed) / 8;
        elems.push_back(getTy());
        auto charType = llvm::IntegerType::get(*ctx, 8);
        auto stringType = llvm::ArrayType::get(charType, sz);
        elems.push_back(stringType);
    } else {
        auto td = dynamic_cast<TypeDecl *>(bd);
        for (auto field : td->fields) {
            elems.push_back(mapType(field->type));
        }
    }
    auto ty = llvm::StructType::create(*ctx, elems, bd->name);
    classMap[bd->name] = ty;
}

void Compiler::createProtos() {
    for (auto bd : unit->types) {
        makeDecl(bd);
    }
    for (auto gt : resolv->genericTypes) {
        makeDecl(gt);
    }
    for (auto m : unit->methods) {
        make_proto(m);
    }
    for (auto bd : unit->types) {
        for (auto m : bd->methods) {
            make_proto(m);
        }
    }
    //generic methods from resolver
    for (auto gm : resolv->genericMethods) {
        make_proto(gm);
    }

    make_printf();
    make_exit();
    make_malloc();
}

void Compiler::initParams(Method *m) {
    //alloc
    auto ff = funcMap[mangle(m)];
    if (isMember(m)) {
        thisPtr = ff->getArg(0);
    } else {
        thisPtr = nullptr;
    }
    for (auto prm : m->params) {
        auto ty = mapType(prm->type);
        auto ptr = Builder->CreateAlloca(ty);
        NamedValues[prm->name] = ptr;
    }
    //store
    int argIdx = isMember(m) ? 1 : 0;
    for (auto i = 0; i < m->params.size(); i++) {
        auto prm = m->params[i];
        auto ptr = NamedValues[prm->name];
        auto val = ff->getArg(argIdx++);
        Builder->CreateStore(val, ptr);
    }
}

bool isRet(Statement *stmt) {
    return dynamic_cast<ReturnStmt *>(stmt) || dynamic_cast<ContinueStmt *>(stmt);
}

bool isReturnLast(Statement *stmt) {
    if (isRet(stmt)) {
        return true;
    }
    auto block = dynamic_cast<Block *>(stmt);
    if (block && !block->list.empty()) {
        auto last = block->list.back();
        if (isRet(last)) {
            return true;
        }
    }
    return false;
}

void Compiler::genCode(Method *m) {
    if (!m->typeArgs.empty()) {
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
    m->body->accept(this);
    if (!isReturnLast(m->body) && m->type->print() == "void") {
        Builder->CreateRetVoid();
    }
    llvm::verifyFunction(*func);
    std::cout << "verified: " << m->name << std::endl;
    resolv->dropScope();
    func = nullptr;
    curMethod = nullptr;
}

void Compiler::compileAll() {
    for (const auto &e : fs::recursive_directory_iterator(srcDir)) {
        if (e.is_directory()) continue;
        compile(e.path().string());
    }
}

void emit(std::string &Filename) {
    auto TargetTriple = llvm::sys::getDefaultTargetTriple();
    llvm::InitializeAllTargetInfos();
    llvm::InitializeAllTargets();
    llvm::InitializeAllTargetMCs();
    llvm::InitializeAllAsmParsers();
    llvm::InitializeAllAsmPrinters();
    std::string Error;
    auto Target = llvm::TargetRegistry::lookupTarget(TargetTriple, Error);

    if (!Target) {
        throw std::runtime_error(Error);
    }
    auto CPU = "generic";
    auto Features = "";

    llvm::TargetOptions opt;
    auto RM = llvm::Optional<llvm::Reloc::Model>();
    auto TargetMachine = Target->createTargetMachine(TargetTriple, CPU, Features, opt, RM);
    mod->setDataLayout(TargetMachine->createDataLayout());
    mod->setTargetTriple(TargetTriple);

    std::error_code EC;
    llvm::raw_fd_ostream dest(Filename, EC, llvm::sys::fs::OF_None);

    if (EC) {
        std::cerr << "Could not open file: " << EC.message();
        exit(1);
    }

    llvm::legacy::PassManager pass;
    auto FileType = llvm::CGFT_ObjectFile;

    if (TargetMachine->addPassesToEmitFile(pass, dest, nullptr, FileType)) {
        std::cerr << "TargetMachine can't emit a file of this type";
        exit(1);
    }
    pass.run(*mod);
    dest.flush();
    std::cout << "writing " << Filename << std::endl;
}

void Compiler::compile(const std::string &path) {
    auto name = getName(path);
    if (path.compare(path.size() - 2, 2, ".x") != 0) {
        //copy res
        std::ifstream src;
        src.open(path, src.binary);
        std::ofstream trg;
        trg.open(outDir + "/" + name, trg.binary);
        trg << src.rdbuf();
        return;
    }
    std::cout << "compiling " << path << std::endl;
    Lexer lexer(path);
    Parser parser(lexer);
    unit = parser.parseUnit();
    resolv = new Resolver(unit);
    resolv->resolveAll();

    NamedValues.clear();
    InitializeModule(name);
    createProtos();

    resolv->scopes.push_back(resolv->globalScope);
    for (auto m : unit->methods) {
        genCode(m);
    }
    for (auto m : resolv->genericMethods) {
        genCode(m);
    }
    for (auto bd : unit->types) {
        for (auto m : bd->methods) {
            genCode(m);
        }
    }
    //mod->dump();
    std::error_code EC;
    auto noext = trimExtenstion(name);
    llvm::raw_fd_ostream fd(noext + ".ll", EC);
    mod->print(fd, nullptr);
    llvm::verifyModule(*mod, &llvm::outs());

    auto outFile = noext + ".o";
    emit(outFile);
    for (auto m : unit->methods) {
        if (m->name == "main") {
            system(("clang-13 " + outFile + " && ./a.out").c_str());
            break;
        }
    }
}

llvm::Value *Compiler::gen(Expression *expr) {
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
        //auto val = (llvm::Value *) t->expr->accept(this);
        auto type = resolv->resolve(curMethod->type)->type;
        Builder->CreateRet(cast(t->expr, type));
    } else {
        Builder->CreateRetVoid();
    }
    return nullptr;
}

void *Compiler::visitExprStmt(ExprStmt *b) {
    return b->expr->accept(this);
}

llvm::Value *load(llvm::Value *val) {
    auto ty = val->getType()->getPointerElementType();
    return Builder->CreateLoad(ty, val);
}

bool isVar(Expression *e) {
    return dynamic_cast<Name *>(e) || dynamic_cast<DerefExpr *>(e) || dynamic_cast<FieldAccess *>(e) || dynamic_cast<ArrayAccess *>(e);
}

llvm::Value *Compiler::loadPtr(Expression *e) {
    auto val = gen(e);
    if (isVar(e)) {
        return load(val);
    }
    return val;
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

llvm::Value *extend(llvm::Value *val, Type *type) {
    int src = val->getType()->getPrimitiveSizeInBits();
    int bits = getSize(type);
    if (src < bits) {
        return Builder->CreateZExt(val, getInt(bits));
    }
    return val;
}

llvm::Value *Compiler::cast(Expression *expr, Type *type) {
    auto lit = dynamic_cast<Literal *>(expr);
    if (lit && lit->type == Literal::INT) {
        auto bits = getSize(type);
        auto intType = llvm::IntegerType::get(*ctx, bits);
        return llvm::ConstantInt::get(intType, atoi(lit->val.c_str()));
    }
    auto val = loadPtr(expr);
    if (type->isPrim()) {
        return extend(val, type);
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
    auto t3 = t1 == "bool" ? make(1) : binCast(t1, t2)->type;
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
    //auto r = (llvm::Value *) i->right->accept(this);
    auto lt = resolv->resolve(i->left);
    auto r = cast(i->right, lt->type);
    if (i->op == "=") {
        return Builder->CreateStore(r, l);
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
    if (!isMember(curMethod)) {
        throw std::runtime_error("unknown ref: " + n->name);
    }
    auto rt = resolv->resolve(n);
    if (!rt->vh) {
        throw std::runtime_error("unknown ref: " + n->name);
    }
    auto fd = *std::get_if<FieldDecl *>(rt->vh);
    auto decl = fd->parent;
    auto idx = fieldIndex(decl, n->name);
    //auto ty = thisPtr->getType()->getPointerElementType();
    auto ty = thisPtr->getType();
    // auto load = Builder->CreateLoad(ty, thisPtr);
    auto load = thisPtr;
    auto gep = Builder->CreateStructGEP(load->getType()->getPointerElementType(), load, idx);
    //auto gep = Builder->CreateStructGEP(load->getType(), load, idx);
    return gep;
}

llvm::Value *callMalloc(llvm::Value *sz) {
    std::vector<llvm::Value *> args;
    args.push_back(sz);
    auto call = Builder->CreateCall(mallocf, args);
    return call;
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
            int bytes = getSize(mc->typeArgs[0]) / 8;
            auto amount = Builder->CreateNSWMul(size, makeInt(bytes));
            args.push_back(amount);
        } else {
            args.push_back(size);
        }

        auto call = Builder->CreateCall(f, args);
        auto rt = resolv->resolve(mc);
        return Builder->CreateBitCast(call, mapType(rt->type));
    } else {
        auto rt = resolv->resolve(mc);
        target = rt->targetMethod;
        f = funcMap[mangle(target)];
    }

    for (unsigned i = 0, e = mc->args.size(); i != e; ++i) {
        auto a = mc->args[i];
        //auto av = loadPtr(a);
        if (target) {
            auto av = cast(a, target->params[i]->type);
            args.push_back(av);
        } else {
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
        auto intType = llvm::IntegerType::get(*ctx, bits);
        return llvm::ConstantInt::get(intType, atoi(n->val.c_str()));
    } else if (n->type == Literal::BOOL) {
        return n->val == "true" ? Builder->getTrue() : Builder->getFalse();
    }
    throw std::runtime_error("literal: " + n->print());
}

void *Compiler::visitAssertStmt(AssertStmt *n) {
    auto str = n->expr->print();
    auto cond = loadPtr(n->expr);
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
        //auto val = (llvm::Value *) f->rhs->accept(this);
        auto type = f->type ? f->type : resolv->resolve(f->rhs)->type;
        //auto val = f->type ? cast(f->rhs, type) : (llvm::Value *) f->rhs->accept(this);
        auto val = cast(f->rhs, type);

        //no unnecessary alloc
        auto obj = dynamic_cast<ObjExpr *>(f->rhs);
        // if (llvm::isa<llvm::AllocaInst>(val)) {
        //     throw std::runtime_error("var alloc");
        //     NamedValues[f->name] = val;
        //     continue;
        // }
        if (obj && !obj->isPointer || dynamic_cast<Type *>(f->rhs)) {
            NamedValues[f->name] = val;
            continue;
        }
        auto ty = mapType(type);
        auto ptr = Builder->CreateAlloca(ty);
        Builder->CreateStore(val, ptr);
        NamedValues[f->name] = ptr;
    }
    return nullptr;
}

void *Compiler::visitRefExpr(RefExpr *n) {
    auto inner = gen(n->expr);
    //todo rvalue
    //auto pt = llvm::PointerType::get(inner->getType(), 0);
    auto pt = inner->getType();
    //todo not needed for name,already ptr
    //return Builder->CreateLoad(pt, inner);
    return inner;
}

void *Compiler::visitDerefExpr(DerefExpr *n) {
    auto val = gen(n->expr);
    auto ty = val->getType()->getPointerElementType();
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

int fieldIndex(TypeDecl *decl, const std::string &name) {
    int i = 0;
    for (auto fd : decl->fields) {
        if (fd->name == name) {
            return i;
        }
        i++;
    }
    throw std::runtime_error("unknown field: " + name + " of type " + decl->name);
}

int fieldIndex(EnumVariant *variant, const std::string &name) {
    int i = 0;
    for (auto fd : variant->fields) {
        if (fd->name == name) {
            return i;
        }
        i++;
    }
    throw std::runtime_error("unknown field: " + name + " of variant " + variant->name);
}

void *Compiler::visitObjExpr(ObjExpr *n) {
    //enum or class
    if (n->type->scope) {
        //enum
        auto enumTy = mapType(n->type->scope);
        auto decl = findEnum(n->type->scope, resolv);
        auto index = Resolver::findVariant(decl, n->type->name);
        llvm::Value *ptr;
        if (n->isPointer) {
            ptr = callMalloc(makeInt(size(decl) / 8, 64));
            ptr = Builder->CreateBitCast(ptr, enumTy);
            //ptr = Builder->CreateLoad(mapType(rt->type), ptr);
        } else {
            ptr = Builder->CreateAlloca(enumTy, (unsigned) 0);
        }

        setOrdinal(index, ptr);
        auto dataPtr = Builder->CreateStructGEP(ptr->getType()->getPointerElementType(), ptr, 1);
        auto variant = decl->variants[index];
        int offset = 0;
        for (int i = 0; i < variant->fields.size(); i++) {
            auto cons = variant->fields[i];
            std::vector<llvm::Value *> entIdx = {makeInt(0), makeInt(offset)};
            auto entPtr = Builder->CreateGEP(dataPtr->getType()->getPointerElementType(), dataPtr, entIdx);
            auto targetTy = mapType(cons->type);
            auto val = cast(n->entries[i].value, cons->type);
            auto cast = Builder->CreateBitCast(entPtr, targetTy->getPointerTo());
            Builder->CreateStore(val, cast);
            offset += getSize(cons->type) / 8;
        }
        return ptr;
    } else {
        //class
        auto rt = (RType *) n->type->accept(resolv);
        auto decl = dynamic_cast<TypeDecl *>(rt->targetDecl);
        auto ty = mapType(resolv->resolve(n)->type);
        llvm::Value *ptr;
        if (n->isPointer) {
            ptr = callMalloc(makeInt(size(decl) / 8, 64));
            ptr = Builder->CreateBitCast(ptr, ty);
            //ptr = Builder->CreateLoad(mapType(rt->type), ptr);
        } else {
            ptr = Builder->CreateAlloca(ty, (unsigned) 0);
        }
        int i = 0;
        for (auto &e : n->entries) {
            int index;
            if (e.hasKey()) {
                index = fieldIndex(decl, e.key);
            } else {
                index = i;
            }
            auto eptr = Builder->CreateStructGEP(ptr->getType()->getPointerElementType(), ptr, index);
            auto field = decl->fields[index];
            auto val = cast(e.value, field->type);
            //auto val = (llvm::Value *) e.value->accept(this);
            Builder->CreateStore(val, eptr);
            i++;
        }
        return ptr;
    }
}

void *Compiler::visitType(Type *n) {
    if (!n->scope) throw std::runtime_error("type has no scope");
    //enum variant without struct
    auto enumTy = mapType(n->scope);
    auto ptr = Builder->CreateAlloca(enumTy, (unsigned) 0);
    int index = Resolver::findVariant(findEnum(n->scope, resolv), n->name);
    setOrdinal(index, ptr);
    return ptr;
}

void *Compiler::visitFieldAccess(FieldAccess *n) {
    auto rt = resolv->resolve(n->scope);
    auto decl = rt->targetDecl;
    int index;
    if (decl->isEnum) {
        index = 0;
    } else {
        auto td = dynamic_cast<TypeDecl *>(decl);
        index = fieldIndex(td, n->name);
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
    if (!isReturnLast(b->thenStmt)) {
        Builder->CreateBr(next);
    }
    if (b->elseStmt) {
        Builder->SetInsertPoint(elsebb);
        func->getBasicBlockList().push_back(elsebb);
        b->elseStmt->accept(this);
        if (!isReturnLast(b->elseStmt)) {
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
    auto decl = findEnum(b->type->scope, resolv);
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
            auto prm = params[i];
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
    Builder->CreateBr(next);
    if (b->elseStmt) {
        Builder->SetInsertPoint(elsebb);
        func->getBasicBlockList().push_back(elsebb);
        b->elseStmt->accept(this);
        Builder->CreateBr(next);
    }
    Builder->SetInsertPoint(next);
    func->getBasicBlockList().push_back(next);
    return nullptr;
}

void *Compiler::visitIsExpr(IsExpr *ie) {
    auto decl = findEnum(ie->type->scope, resolv);
    auto val = gen(ie->expr);
    auto ordptr = Builder->CreateStructGEP(val->getType()->getPointerElementType(), val, 0);
    auto ord = Builder->CreateLoad(getInt(32), ordptr);
    auto index = Resolver::findVariant(decl, ie->type->name);
    return Builder->CreateCmp(llvm::CmpInst::ICMP_EQ, ord, makeInt(index));
}

void *Compiler::visitAsExpr(AsExpr *e) {
    auto val = gen(e->expr);
    auto ty = resolv->resolve(e->type);
    return extend(val, ty->type);
}

void *Compiler::visitArrayAccess(ArrayAccess *node) {
    auto src = loadPtr(node->array);
    std::vector<llvm::Value *> idx = {loadPtr(node->index)};
    return Builder->CreateGEP(src->getType()->getPointerElementType(), src, idx);
}

void *Compiler::visitWhileStmt(WhileStmt *node) {
    auto then = llvm::BasicBlock::Create(*ctx, "");
    auto condbb = llvm::BasicBlock::Create(*ctx, "", func);
    auto next = llvm::BasicBlock::Create(*ctx, "");
    loops.push_back(condbb);
    Builder->CreateBr(condbb);
    Builder->SetInsertPoint(condbb);
    auto c = loadPtr(node->expr);
    Builder->CreateCondBr(branch(c), then, next);
    Builder->SetInsertPoint(then);
    func->getBasicBlockList().push_back(then);
    node->body->accept(this);
    Builder->CreateBr(condbb);
    Builder->SetInsertPoint(next);
    func->getBasicBlockList().push_back(next);
    loops.pop_back();
    return nullptr;
}

void *Compiler::visitContinueStmt(ContinueStmt *node) {
    Builder->CreateBr(loops.back());
    return nullptr;
}