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
#include <llvm/IR/Constants.h>
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

void initModule(std::string &name, Compiler *c) {
    c->mod = std::make_unique<llvm::Module>(name, c->ctx);
    c->Builder = std::make_unique<llvm::IRBuilder<>>(c->ctx);
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

llvm::Value *Compiler::branch(llvm::Value *val) {
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

llvm::Value *Compiler::load(llvm::Value *val) {
    auto ty = val->getType()->getPointerElementType();
    return Builder->CreateLoad(ty, val);
}

bool isVar(Expression *e) {
    if (dynamic_cast<DerefExpr *>(e)) {
        return true;
    }
    return dynamic_cast<SimpleName *>(e) || dynamic_cast<FieldAccess *>(e) || dynamic_cast<ArrayAccess *>(e);
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

void Compiler::make_proto(std::unique_ptr<Method> &m) {
    make_proto(m.get());
}

void Compiler::make_proto(Method *m) {
    if (m->isGeneric) {
        return;
    }
    resolv->curMethod = m;
    std::vector<llvm::Type *> argTypes;
    bool rvo = isRvo(m);
    if (rvo) {
        argTypes.push_back(mapType(m->type.get())->getPointerTo());
    }
    if (m->self) {
        auto p = m->self->type.get();
        auto ty = mapType(p);
        if (isStruct(p)) {
            ty = ty->getPointerTo();
        }
        argTypes.push_back(ty);
    }
    for (auto &prm : m->params) {
        auto ty = mapType(prm->type.get());
        if (isStruct(prm->type.get())) {
            //structs are always pass by ptr
            ty = ty->getPointerTo();
        }
        argTypes.push_back(ty);
    }
    auto retType = mapType(m->type.get());
    if (rvo) {
        //retType=getInt(32);
        retType = Builder->getVoidTy();
    }
    auto mangled = mangle(m);
    auto fr = llvm::FunctionType::get(retType, argTypes, false);
    auto linkage = llvm::Function::ExternalLinkage;
    if (!m->typeArgs.empty()) {
        linkage = llvm::Function::LinkOnceODRLinkage;
    }
    auto f = llvm::Function::Create(fr, linkage, mangled, *mod);
    //f->addTypeMetadata(0, llvm::MDNode::get(ctx, llvm::MDString::get(ctx, m->name)));
    int i = 0;
    if (rvo) {
        f->getArg(0)->setName("ret");
        i++;
    }
    if (m->self) {
        f->getArg(i)->setName("self");
        i++;
    }
    for (int pi = 0; i < f->arg_size(); i++) {
        f->getArg(i)->setName(m->params[pi++]->name);
    }
    funcMap[mangled] = f;
    resolv->curMethod = nullptr;
    if(m->isVirtual) virtuals.push_back(m);
}

std::vector<Method*> getVirtual(StructDecl* decl, Unit* unit){
    std::vector<Method*> arr;
    for(auto &item:unit->items){
        if(!item->isImpl()) continue;        
        auto imp = (Impl*)item.get();
        if(imp->type->name != decl->type->name) continue;
        for(auto &m:imp->methods){
            if(m->isVirtual){
                arr.push_back(m.get());
            }
        }
    }
    return arr;
}

llvm::StructType *Compiler::makeDecl(BaseDecl *bd) {
    if (bd->isGeneric) {
        return nullptr;
    }
    if (bd->type->print() == "str") {
        return stringType;
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
        if(td->base){
            elems.push_back(mapType(td->base.get()));
        }
        for (auto &field : td->fields) {
            elems.push_back(mapType(field->type));
        }
        if(!getVirtual(td, unit.get()).empty()){
            elems.push_back(getInt(8)->getPointerTo()->getPointerTo());
        }
    }
    auto mangled = bd->type->print();
    auto ty = llvm::StructType::create(ctx, elems, mangled);
    classMap[mangled] = ty;
    return ty;
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

    printf_proto = make_printf();
    exit_proto = make_exit();
    mallocf = make_malloc();
    if (!sliceType) {
        sliceType = make_slice_type();
    }
    if (!stringType) {
        stringType = make_string_type();
    }
}
void Compiler::make_vtables(){
    std::map<std::string, std::vector<Method*>> map;
    for(auto m : virtuals){
        auto p = m->self->type->print();
        map[p].push_back(m);
    }
    for(auto &[k, v] : map){
        auto i8p = getInt(8)->getPointerTo();
        auto arrt = llvm::ArrayType::get(i8p, 1);
        auto linkage = llvm::GlobalValue::ExternalLinkage;
        std::vector<llvm::Constant*> arr;
        for(auto m:v){
            auto f = funcMap[mangle(m)];
            auto fcast=llvm::ConstantExpr::getCast(llvm::Instruction::BitCast, f, i8p);
            arr.push_back(fcast);
        }
        auto init = llvm::ConstantArray::get(arrt, arr);
        auto vt = new llvm::GlobalVariable(*mod, arrt, true, linkage, init, k + ".vt");
        vtables[k] = vt;
    }
    for(){
    }
}

void Compiler::initParams(Method *m) {
    //alloc
    auto ff = funcMap[mangle(m)];
    if (m->self) {
        llvm::Value *ptr = isRvo(m) ? ff->getArg(1) : ff->getArg(0);
        if (isStruct(m->self->type.get())) {
        } else {
            auto ty = mapType(m->self->type.get());
            ptr = Builder->CreateAlloca(ty);
        }
        NamedValues[m->self->name] = ptr;
    }
    for (auto &prm : m->params) {
        //non mut structs dont need alloc
        if (isStruct(prm->type.get()) && resolv->mut_params.count(prm.get()) == 0) continue;
        auto ty = mapType(prm->type.get());
        auto ptr = Builder->CreateAlloca(ty);
        NamedValues[prm->name] = ptr;
    }
}

void storeParams(Method *m, Compiler *c) {
    auto ff = c->funcMap[mangle(m)];
    int argIdx = isRvo(m) ? 1 : 0;
    if (m->self) {
        if (!isStruct(m->self->type.get())) {
            auto ptr = c->NamedValues[m->self->name];
            auto val = ff->getArg(argIdx);
            c->Builder->CreateStore(val, ptr);
        }
        argIdx++;
    }
    for (auto i = 0; i < m->params.size(); i++) {
        auto prm = m->params[i].get();
        auto val = ff->getArg(argIdx++);
        auto ptr = c->NamedValues[prm->name];
        if (isStruct(prm->type.get())) {
            if (c->resolv->mut_params.count(prm) == 0) {
                c->NamedValues[prm->name] = val;
            } else {
                //memcpy
                c->Builder->CreateMemCpy(ptr, llvm::MaybeAlign(0), val, llvm::MaybeAlign(0), c->getSize(prm->type.get()) / 8);
            }
        } else {
            c->Builder->CreateStore(val, ptr);
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

void Compiler::genCode(std::unique_ptr<Method> &m) {
    genCode(m.get());
}

void Compiler::genCode(Method *m) {
    if (m->isGeneric || !m->body) {
        return;
    }
    resolv->curMethod = m;
    curMethod = m;
    resolv->scopes.push_back(resolv->methodScopes[m]);
    func = funcMap[mangle(m)];
    NamedValues.clear();
    if (m->body) {
        auto bb = llvm::BasicBlock::Create(ctx, "", func);
        Builder->SetInsertPoint(bb);
        initParams(m);
        makeLocals(m->body.get());
        storeParams(curMethod, this);
        m->body->accept(this);
        if (!isReturnLast(m->body.get()) && m->type->print() == "void") {
            Builder->CreateRetVoid();
        }
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
    system("rm a.out");
    system((cmd + " && ./a.out").c_str());
    for (auto &[k, v] : Resolver::resolverMap) {
        v.reset();
        //v->unit.reset();
    }
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

    initModule(name, this);
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

    //emit llvm
    auto llvm_file = noext + ".ll";
    llvm::raw_fd_ostream fd(llvm_file, EC);
    mod->print(fd, nullptr);
    print("writing " + llvm_file);

    //todo fullpath
    auto outFile = noext + ".o";
    emit(outFile);
    cleanup();
    return outFile;
}

void Compiler::cleanup() {
    // for (auto &[k, v] : funcMap) {
    //     v->eraseFromParent();
    // }
    funcMap.clear();
    classMap.clear();
    // for (auto &[k, v] : NamedValues) {
    //     v->deleteValue();
    // }
    NamedValues.clear();
    mod.reset();
    Builder.reset();
    virtuals.clear();
    //allocArr;
}

llvm::Value *Compiler::gen(Expression *expr) {
    auto val = expr->accept(this);
    auto res = std::any_cast<llvm::Value *>(val);
    if (!res) error("val null " + expr->print() + " " + val.type().name());
    return res;
}
llvm::Value *Compiler::gen(std::unique_ptr<Expression> &expr) {
    return gen(expr.get());
}

std::any Compiler::visitBlock(Block *b) {
    for (auto &s : b->list) {
        s->accept(this);
    }
    return nullptr;
}

std::any Compiler::visitReturnStmt(ReturnStmt *t) {
    if (t->expr) {
        if (isStruct(curMethod->type.get())) {
            //rvo            
            auto ptr = func->getArg(0);
            if (doesAlloc(t->expr.get())) {
                child(t->expr.get(), ptr);
                Builder->CreateRetVoid();
                return nullptr;
            }
            auto val = gen(t->expr.get());
            auto size = getSize(resolv->getType(t->expr.get())) / 8;
            Builder->CreateMemCpy(ptr, llvm::MaybeAlign(0), val, llvm::MaybeAlign(0), size);
            Builder->CreateRetVoid();
        } else {
            auto type = resolv->getType(curMethod->type.get());
            Builder->CreateRet(cast(t->expr.get(), type));
        }
    } else {
        Builder->CreateRetVoid();
    }
    return nullptr;
}

std::any Compiler::visitExprStmt(ExprStmt *b) {
    return b->expr->accept(this);
}

std::any Compiler::visitParExpr(ParExpr *i) {
    return i->expr->accept(this);
}

llvm::Value *Compiler::andOr(Expression *left, Expression *right, bool isand) {
    auto l = loadPtr(left);
    auto bb = Builder->GetInsertBlock();
    auto then = llvm::BasicBlock::Create(ctx, "", func);
    auto next = llvm::BasicBlock::Create(ctx, "");
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
        return c->Builder->CreateZExt(val, c->getInt(bits));
    }
    if (src > bits) {
        return c->Builder->CreateTrunc(val, c->getInt(bits));
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
        auto intType = llvm::IntegerType::get(ctx, bits);
        return llvm::ConstantInt::get(intType, atoi(lit->val.c_str()));
    }
    auto val = loadPtr(expr);
    if (type->isPrim()) {
        return extend(val, type, this);
    }
    return val;
}

std::any Compiler::visitInfix(Infix *i) {
    if (i->op == "&&") {
        return andOr(i->left, i->right, true);
    }
    if (i->op == "||") {
        return andOr(i->left, i->right, false);
    }
    auto t1 = resolv->resolve(i->left).type->print();
    auto t2 = resolv->resolve(i->right).type->print();
    auto t3 = t1 == "bool" ? new Type("i1") : binCast(t1, t2).type;
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

std::any Compiler::visitUnary(Unary *u) {
    auto v = gen(u->expr);
    auto val = v;
    if (isVar(u->expr)) {
        val = load(v);
    }
    llvm::Value *res;
    if (u->op == "+") {
        res = val;
    } else if (u->op == "-") {
        res = (llvm::Value *) Builder->CreateNSWSub(makeInt(0), val);
    } else if (u->op == "++") {
        auto bits = val->getType()->getPrimitiveSizeInBits();
        res = Builder->CreateNSWAdd(val, makeInt(1, bits));
        Builder->CreateStore(res, v);
    } else if (u->op == "--") {
        res = Builder->CreateNSWSub(val, makeInt(1));
        Builder->CreateStore(res, v);
    } else if (u->op == "!") {
        res = Builder->CreateTrunc(val, getInt(1));
        res = Builder->CreateXor(res, Builder->getTrue());
        res = Builder->CreateZExt(res, getInt(8));
    } else if (u->op == "~") {
        res = (llvm::Value *) Builder->CreateXor(val, makeInt(-1));
    } else {
        throw std::runtime_error("Unary: " + u->print());
    }
    return res;
}

std::any Compiler::visitAssign(Assign *i) {
    auto l = gen(i->left);
    auto val = l;
    auto lt = resolv->resolve(i->left).type;
    auto r = cast(i->right, lt);
    if (i->op == "=") {
        if (isStruct(lt)) {
            return (llvm::Value *) Builder->CreateMemCpy(l, llvm::MaybeAlign(0), r, llvm::MaybeAlign(0), getSize(lt) / 8);
        } else {
            return (llvm::Value *) Builder->CreateStore(r, l);
        }
    }
    if (isVar(i->left)) {
        val = load(l);
    }
    if (i->op == "+=") {
        auto tmp = Builder->CreateNSWAdd(val, r);
        return (llvm::Value *) Builder->CreateStore(tmp, l);
    }
    if (i->op == "-=") {
        auto tmp = Builder->CreateNSWSub(val, r);
        return (llvm::Value *) Builder->CreateStore(tmp, l);
    }
    if (i->op == "*=") {
        auto tmp = Builder->CreateNSWMul(val, r);
        return (llvm::Value *) Builder->CreateStore(tmp, l);
    }
    if (i->op == "/=") {
        auto tmp = Builder->CreateSDiv(val, r);
        return (llvm::Value *) Builder->CreateStore(tmp, l);
    }
    throw std::runtime_error("assign: " + i->print());
}

std::any Compiler::visitSimpleName(SimpleName *n) {
    auto it = NamedValues.find(n->name);
    if (it != NamedValues.end()) {
        return it->second;
    }
    throw std::runtime_error("compiler bug; sym not found: " + n->name + " in " + curMethod->name);
}

llvm::Value *callMalloc(llvm::Value *sz, Compiler *c) {
    std::vector<llvm::Value *> args = {sz};
    return (llvm::Value *) c->Builder->CreateCall(c->mallocf, args);
}

std::any callPanic(MethodCall *mc, Compiler *c) {
    std::string message;
    if (mc->args.empty()) {
        message = "panic";
    } else {
        auto val = dynamic_cast<Literal *>(mc->args[0])->val;
        message = "panic: " + val.substr(1, val.size() - 2);
    }
    message.append("\n");
    auto str = c->Builder->CreateGlobalStringPtr(message);
    std::vector<llvm::Value *> args;
    args.push_back(str);
    if (!mc->args.empty()) {
        for (int i = 1; i < mc->args.size(); ++i) {
            auto a = mc->args[i];
            auto av = c->loadPtr(a);
            args.push_back(av);
        }
    }
    auto call = c->Builder->CreateCall(c->printf_proto, args);
    std::vector<llvm::Value *> exit_args = {c->makeInt(1)};
    c->Builder->CreateCall(c->exit_proto, exit_args);
    c->Builder->CreateUnreachable();
    return (llvm::Value *) c->Builder->getVoidTy();
}

void callPrint(MethodCall *mc, Compiler *c) {
    std::vector<llvm::Value *> args;
    for (auto a : mc->args) {
        if (isStrLit(a)) {
            auto l = dynamic_cast<Literal *>(a);
            auto str = c->Builder->CreateGlobalStringPtr(l->val.substr(1, l->val.size() - 2));
            args.push_back(str);
        } else {
            auto arg_type = c->resolv->getType(a);
            if (arg_type->isString()) {
                auto src = c->gen(a);
                //get ptr to inner char array
                if (src->getType()->isPointerTy()) {
                    auto slice = c->Builder->CreateStructGEP(src->getType()->getPointerElementType(), src, 0);
                    auto str = c->Builder->CreateLoad(c->getInt(8)->getPointerTo(), slice);
                    args.push_back(str);
                } else {
                    args.push_back(src);
                }
            } else {
                auto av = c->loadPtr(a);
                args.push_back(av);
            }
        }
    }
    c->Builder->CreateCall(c->printf_proto, args);
}

std::any Compiler::visitMethodCall(MethodCall *mc) {
    if (mc->name == "print") {
        callPrint(mc, this);
        return nullptr;
    } else if (mc->name == "malloc") {
        auto lt = new Type("i64");
        auto size = cast(mc->args[0], lt);
        if (!mc->typeArgs.empty()) {
            int typeSize = getSize(mc->typeArgs[0]) / 8;
            size = Builder->CreateNSWMul(size, makeInt(typeSize, 64));
        }
        auto call = callMalloc(size, this);
        auto rt = resolv->getType(mc);
        return Builder->CreateBitCast(call, mapType(rt));
    } else if (mc->name == "panic") {
        return callPanic(mc, this);
    }
    auto rt = resolv->resolve(mc);
    auto target = rt.targetMethod;
    auto f = funcMap[mangle(target)];
    std::vector<llvm::Value *> args;
    int paramIdx = 0;
    if (isRvo(target)) {
        args.push_back(getAlloc(mc));
    }
    llvm::Value* obj = nullptr;
    if (target->self && !dynamic_cast<Type *>(mc->scope.get())) {
        //add this object
        obj = gen(mc->scope.get());
        auto scope_type = resolv->getType(mc->scope.get());
        if (scope_type->isPointer() || (scope_type->isPrim() && isVar(mc->scope.get()))) {
            //auto deref
            obj = Builder->CreateLoad(obj->getType()->getPointerElementType(), obj);
        }
        //base method
        if(!target->self->type->isPrim()){
            obj = Builder->CreateBitCast(obj, mapType(target->self->type.get())->getPointerTo());
        }
        args.push_back(obj);
        paramIdx++;
    }
    std::vector<Param *> params;
    if (target->self) {
        params.push_back(target->self.get());
    }
    for (auto &p : target->params) {
        params.push_back(p.get());
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
    llvm::Value *res;
    if(target->isVirtual){//todo and this not derived 
        auto bd = resolv->resolve(mc->scope.get()).targetDecl;
        auto decl = (StructDecl*)bd;
        int vt_index = decl->fields.size() + (decl->base ? 1: 0);
        auto vt = Builder->CreateStructGEP(obj->getType()->getPointerElementType(), obj, vt_index , "vtptr");
        vt = load(vt);
        auto ft = f->getType();
        auto real = llvm::ArrayType::get(ft, 1)->getPointerTo();
        
        vt = Builder->CreateBitCast(vt, real);
        auto index = 0;
        auto fptr=load(gep(vt, 0, index));
        auto ff=(llvm::FunctionType*)f->getFunctionType();
        res= (llvm::Value *) Builder->CreateCall(ff, fptr, args);        
    }else{
        res=(llvm::Value *) Builder->CreateCall(f, args);
    }
    if (isRvo(target)){
        return args[0];
    }
    return res;
}

llvm::Value *Compiler::call(MethodCall *mc, llvm::Value *ptr) {
    auto rt = resolv->resolve(mc);
    auto target = rt.targetMethod;
    auto f = funcMap[mangle(target)];
    std::vector<llvm::Value *> args;
    int paramIdx = 0;
    if (isRvo(target)) {
        args.push_back(ptr);
    }
    if (target->self && !dynamic_cast<Type *>(mc->scope.get())) {
        //add this object
        auto obj = gen(mc->scope.get());
        auto scope_type = resolv->getType(mc->scope.get());
        if (scope_type->isPointer() || (scope_type->isPrim() && isVar(mc->scope.get()))) {
            //auto deref
            obj = Builder->CreateLoad(obj->getType()->getPointerElementType(), obj);
        }
        args.push_back(obj);
        paramIdx++;
    }
    std::vector<Param *> params;
    if (target->self) {
        params.push_back(target->self.get());
    }
    for (auto &p : target->params) {
        params.push_back(p.get());
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

    auto res = (llvm::Value *) Builder->CreateCall(f, args);
    if (isRvo(target)) return args[0];
    return res;
}

std::any Compiler::visitLiteral(Literal *n) {
    if (n->type == Literal::STR) {
        auto trimmed = n->val.substr(1, n->val.size() - 2);
        auto src = Builder->CreateGlobalStringPtr(trimmed);
        auto str_slice_ptr = getAlloc(n);
        auto slice_ptr = Builder->CreateBitCast(str_slice_ptr, sliceType->getPointerTo());
        //store s in slice_ptr
        auto data_target = Builder->CreateStructGEP(slice_ptr->getType()->getPointerElementType(), slice_ptr, 0);
        Builder->CreateStore(src, data_target);
        //store len in slice_ptr
        auto len_target = Builder->CreateStructGEP(slice_ptr->getType()->getPointerElementType(), slice_ptr, 1);
        auto len = makeInt(trimmed.size(), 32);
        Builder->CreateStore(len, len_target);
        return (llvm::Value *) str_slice_ptr;
    } else if (n->type == Literal::CHAR) {
        auto trimmed = n->val.substr(1, n->val.size() - 2);
        auto chr = trimmed[0];
        return (llvm::Value *) llvm::ConstantInt::get(getInt(32), chr);
    } else if (n->type == Literal::INT) {
        auto bits = 32;
        if (n->suffix) {
            bits = getSize(n->suffix.get());
        }
        auto intType = llvm::IntegerType::get(ctx, bits);
        return (llvm::Value *) llvm::ConstantInt::get(intType, atoi(n->val.c_str()));
    } else if (n->type == Literal::BOOL) {
        return (llvm::Value *) (n->val == "true" ? Builder->getTrue() : Builder->getFalse());
    }
    throw std::runtime_error("literal: " + n->print());
}

std::any Compiler::visitAssertStmt(AssertStmt *n) {
    auto str = n->expr->print();
    auto cond = loadPtr(n->expr.get());
    auto then = llvm::BasicBlock::Create(ctx, "", func);
    auto next = llvm::BasicBlock::Create(ctx, "");
    Builder->CreateCondBr(branch(cond), next, then);
    Builder->SetInsertPoint(then);
    //print error and exit
    auto msg = std::string("assertion ") + str + " failed\n";
    std::vector<llvm::Value *> pr_args = {Builder->CreateGlobalStringPtr(msg)};
    Builder->CreateCall(printf_proto, pr_args, "");
    std::vector<llvm::Value *> args = {makeInt(1)};
    Builder->CreateCall(exit_proto, args);
    Builder->CreateUnreachable();
    Builder->SetInsertPoint(next);
    func->getBasicBlockList().push_back(next);
    return nullptr;
}
std::any Compiler::visitVarDecl(VarDecl *node) {
    node->decl->accept(this);
    return {};
}
std::any Compiler::visitVarDeclExpr(VarDeclExpr *n) {
    for (auto f : n->list) {
        auto rhs = f->rhs.get();
        //no unnecessary alloc
        if (doesAlloc(rhs)) {
            gen(rhs);
            continue;
        }
        auto type = f->type ? f->type.get() : resolv->getType(rhs);
        auto ptr = NamedValues[f->name];
        allocIdx++;
        if (isStruct(type)) {
            //memcpy
            auto val = gen(rhs);
            if (val->getType()->isPointerTy()) {
                Builder->CreateMemCpy(ptr, llvm::MaybeAlign(0), val, llvm::MaybeAlign(0), getSize(type) / 8);
            } else {
                Builder->CreateStore(val, ptr);
            }
        } else {
            auto val = cast(rhs, type);
            Builder->CreateStore(val, ptr);
        }
    }
    return nullptr;
}

std::any Compiler::visitRefExpr(RefExpr *n) {
    auto inner = gen(n->expr);
    //todo rvalue
    return inner;
}

std::any Compiler::visitDerefExpr(DerefExpr *n) {
    auto val = gen(n->expr);
    auto ty = val->getType()->getPointerElementType();
    //todo struct memcpy
    return (llvm::Value *) Builder->CreateLoad(ty, val);
}

EnumDecl *findEnum(Type *type, Resolver *resolv) {
    auto rt = resolv->resolve(type);
    return dynamic_cast<EnumDecl *>(rt.targetDecl);
}

std::any Compiler::visitObjExpr(ObjExpr *n) {
    auto tt = resolv->resolve(n);
    llvm::Value *ptr;
    if (n->isPointer) {
        auto ty = mapType(tt.type);
        ptr = callMalloc(makeInt(getSize(tt.targetDecl) / 8, 64), this);
        ptr = Builder->CreateBitCast(ptr, ty);
    } else {
        ptr = getAlloc(n);
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
    if (do_cast) {
        auto targetTy = mapType(type);
        entPtr = Builder->CreateBitCast(entPtr, targetTy->getPointerTo());
    }
    if (doesAlloc(expr)) {
        child(expr, entPtr);
    } else if (isStruct(type) && !dynamic_cast<MethodCall *>(expr)) {//todo mc
        auto val = gen(expr);
        Builder->CreateMemCpy(entPtr, llvm::MaybeAlign(0), val, llvm::MaybeAlign(0), getSize(type) / 8);
    } else {
        auto val = cast(expr, type);
        Builder->CreateStore(val, entPtr);
    }
}

void Compiler::object(ObjExpr *n, llvm::Value *ptr, const RType &tt) {
    auto ty = mapType(tt.type);
    if (tt.targetDecl->isEnum()) {
        //enum
        auto decl = dynamic_cast<EnumDecl *>(tt.targetDecl);
        auto variant_index = Resolver::findVariant(decl, n->type->name);

        setOrdinal(variant_index, ptr);
        auto dataPtr = Builder->CreateStructGEP(ptr->getType()->getPointerElementType(), ptr, 1);
        auto variant = decl->variants[variant_index];
        for (int i = 0; i < n->entries.size(); i++) {
            auto &e = n->entries[i];
            int index;
            if (e.key) {
                index = fieldIndex(variant->fields, e.key.value(), new Type(decl->type, variant->name));
            } else {
                index = i;
            }
            auto &field = variant->fields[index];
            auto entPtr = gep(dataPtr, 0, getOffset(variant, index));
            setField(e.value, field->type, true, entPtr);
        }
    } else {
        //class
        auto decl = dynamic_cast<StructDecl *>(tt.targetDecl);
        if(!getVirtual(decl, unit.get()).empty()){
            //set vtable
            auto vt = vtables[decl->type->print()];
            int vt_index = decl->fields.size() + (decl->base ? 1: 0);
            auto vt_target = Builder->CreateStructGEP(ptr->getType()->getPointerElementType(), ptr, vt_index , "vtptr");
            auto casted = Builder->CreateBitCast(vt, getInt(8)->getPointerTo()->getPointerTo());
            Builder->CreateStore(casted, vt_target);
        }
        int field_idx = 0;
        for (int i = 0; i < n->entries.size(); i++) {
            auto &e = n->entries[i];
            if(e.isBase){
                auto eptr = Builder->CreateStructGEP(ptr->getType()->getPointerElementType(), ptr, 0, "base");
                object(dynamic_cast<ObjExpr*>(e.value), eptr, resolv->resolve(e.value));
                continue;
            }
            FieldDecl* field;
            int real_idx;
            if (e.key) {
                auto index = fieldIndex(decl->fields, e.key.value(), decl->type);
                field = decl->fields[index].get();
                real_idx =  index;
            } else {
                real_idx = field_idx;
                field = decl->fields[field_idx++].get();
            }
            if(decl->base) real_idx++;
            auto eptr = Builder->CreateStructGEP(ptr->getType()->getPointerElementType(), ptr, real_idx, "field_" + field->name);
            setField(e.value, field->type, true, eptr);
        }
    }
}


std::any Compiler::visitType(Type *n) {
    if (!n->scope) {
        throw std::runtime_error("type has no scope");
    }
    //enum variant without struct
    auto ptr = getAlloc(n);
    simpleVariant(n, ptr);
    return ptr;
}

std::any Compiler::visitFieldAccess(FieldAccess *n) {
    auto rt = resolv->resolve(n->scope);
    if (rt.type->isSlice()) {
        auto scopeVar = gen(n->scope);
        return Builder->CreateStructGEP(scopeVar->getType()->getPointerElementType(), scopeVar, SLICE_LEN_INDEX);
        //todo load since cant mutate
    }
    if (rt.type->isString()) {
        rt = resolv->resolve(rt.type);
    }
    auto decl = rt.targetDecl;
    int index;
    if (decl->isEnum()) {
        index = 0;
    } else {
        auto td = dynamic_cast<StructDecl *>(decl);
        index = fieldIndex(td->fields, n->name, td->type);
        if(td->base) index++;
    }
    auto scopeVar = gen(n->scope);
    auto ty = scopeVar->getType()->getPointerElementType();
    if (rt.type->isPointer()) {
        //auto deref
        scopeVar = Builder->CreateLoad(ty, scopeVar);
    }
    return (llvm::Value *) Builder->CreateStructGEP(scopeVar->getType()->getPointerElementType(), scopeVar, index);
}

std::any Compiler::visitIfStmt(IfStmt *b) {
    auto cond = branch(loadPtr(b->expr));
    auto then = llvm::BasicBlock::Create(ctx, "body", func);
    llvm::BasicBlock *elsebb = nullptr;
    auto next = llvm::BasicBlock::Create(ctx, "next");
    if (b->elseStmt) {
        elsebb = llvm::BasicBlock::Create(ctx, "else");
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

std::any Compiler::visitIfLetStmt(IfLetStmt *b) {
    auto rhs = gen(b->rhs);
    std::vector<llvm::Value *> idx = {makeInt(0), makeInt(0)};
    auto ty = rhs->getType()->getPointerElementType();
    auto ordptr = Builder->CreateStructGEP(ty, rhs, 0);
    auto ord = Builder->CreateLoad(getInt(32), ordptr);
    auto decl = findEnum(b->type.get(), resolv.get());
    auto index = Resolver::findVariant(decl, b->type->name);
    auto cmp = Builder->CreateCmp(llvm::CmpInst::ICMP_EQ, ord, makeInt(index));

    auto then = llvm::BasicBlock::Create(ctx, "", func);
    llvm::BasicBlock *elsebb;
    auto next = llvm::BasicBlock::Create(ctx, "");
    if (b->elseStmt) {
        elsebb = llvm::BasicBlock::Create(ctx, "");
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
            auto ptr = gep(dataPtr, 0, offset);
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

std::any Compiler::visitIsExpr(IsExpr *ie) {
    auto decl = findEnum(ie->type->scope.get(), resolv.get());
    auto val = gen(ie->expr);
    auto ordptr = Builder->CreateStructGEP(val->getType()->getPointerElementType(), val, 0);
    auto ord = Builder->CreateLoad(getInt(32), ordptr);
    auto index = Resolver::findVariant(decl, ie->type->name);
    return (llvm::Value *) Builder->CreateCmp(llvm::CmpInst::ICMP_EQ, ord, makeInt(index));
}

std::any Compiler::visitAsExpr(AsExpr *e) {
    auto val = gen(e->expr);
    auto ty = resolv->getType(e->type);
    if(ty->isPrim()){
        return extend(val, ty, this);
    }
    //derived to base
    return Builder->CreateStructGEP(val->getType()->getPointerElementType(), val, 0);
}


std::any Compiler::slice(ArrayAccess *node, llvm::Value *sp, Type *arrty) {
    auto val_start = cast(node->index, new Type("i32"));
    //set array ptr
    llvm::Value *src;
    if (doesAlloc(node->array)) {
        child(node->array, sp);
        src = sp;
    } else {
        src = gen(node->array);
    }
    Type *elemty;
    if (arrty->isSlice()) {
        //deref inner pointer
        src = Builder->CreateBitCast(src, src->getType()->getPointerTo());
        src = load(src);
        elemty = dynamic_cast<SliceType *>(arrty)->type;
    } else if (arrty->isArray()) {
        elemty = dynamic_cast<ArrayType *>(arrty)->type;
    } else {
        elemty = dynamic_cast<PointerType *>(arrty)->type;
        src = load(src);
    }
    src = Builder->CreateBitCast(src, mapType(elemty)->getPointerTo());
    //shift by start
    std::vector<llvm::Value *> shift_idx = {val_start};
    src = Builder->CreateGEP(src->getType()->getPointerElementType(), src, shift_idx, "shifted");
    //i8*
    src = Builder->CreateBitCast(src, getInt(8)->getPointerTo());
    auto ptr_target = Builder->CreateStructGEP(sp->getType()->getPointerElementType(), sp, 0);
    Builder->CreateStore(src, ptr_target);
    //set len
    auto len_target = Builder->CreateStructGEP(sp->getType()->getPointerElementType(), sp, SLICE_LEN_INDEX);
    auto val_end = cast(node->index2.get(), new Type("i32"));
    auto len = Builder->CreateSub(val_end, val_start);
    Builder->CreateStore(len, len_target);
    return sp;
}

std::any Compiler::visitArrayAccess(ArrayAccess *node) {
    auto type = resolv->getType(node->array);
    if (node->index2) {
        auto sp = getAlloc(node);
        slice(node, sp, type);
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
    if (type->isArray()) {
        //regular array access
        return gep(src, 0, node->index);
    } else if (type->isSlice()) {
        //slice access
        auto elem = dynamic_cast<SliceType *>(type)->type;
        auto elemty = mapType(elem);
        //read array ptr
        auto arr = Builder->CreateStructGEP(src->getType()->getPointerElementType(), src, 0, "arr1");
        arr = Builder->CreateBitCast(arr, arr->getType()->getPointerTo());
        arr = Builder->CreateLoad(arr->getType()->getPointerElementType(), arr);
        arr = Builder->CreateBitCast(arr, elemty->getPointerTo());
        return gep(arr, node->index);
    } else {
        //pointer access
        src = load(src);
        return gep(src, node->index);
    }
}

std::any Compiler::visitWhileStmt(WhileStmt *node) {
    auto then = llvm::BasicBlock::Create(ctx, "body");
    auto condbb = llvm::BasicBlock::Create(ctx, "cont_test", func);
    auto next = llvm::BasicBlock::Create(ctx, "next");
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

std::any Compiler::visitForStmt(ForStmt *node) {
    if (node->decl) {
        node->decl->accept(this);
    }
    auto then = llvm::BasicBlock::Create(ctx, "body");
    auto condbb = llvm::BasicBlock::Create(ctx, "cont_test", func);
    auto updatebb = llvm::BasicBlock::Create(ctx, "update", func);
    auto next = llvm::BasicBlock::Create(ctx, "next");
    Builder->CreateBr(condbb);
    Builder->SetInsertPoint(condbb);
    if (node->cond) {
        auto c = loadPtr(node->cond.get());
        Builder->CreateCondBr(branch(c), then, next);
    } else {
        Builder->CreateBr(then);
    }

    Builder->SetInsertPoint(then);
    func->getBasicBlockList().push_back(then);
    loops.push_back(updatebb);
    loopNext.push_back(next);
    node->body->accept(this);
    Builder->CreateBr(updatebb);
    Builder->SetInsertPoint(updatebb);
    for (auto &u : node->updaters) {
        u->accept(this);
    }
    loops.pop_back();
    loopNext.pop_back();
    Builder->CreateBr(condbb);
    Builder->SetInsertPoint(next);
    func->getBasicBlockList().push_back(next);
    return {};
}

std::any Compiler::visitContinueStmt(ContinueStmt *node) {
    Builder->CreateBr(loops.back());
    return nullptr;
}

std::any Compiler::visitBreakStmt(BreakStmt *node) {
    Builder->CreateBr(loopNext.back());
    return nullptr;
}

std::any Compiler::visitArrayExpr(ArrayExpr *node) {
    auto ptr = getAlloc(node);
    array(node, ptr);
    return ptr;
}

void Compiler::child(Expression *e, llvm::Value *ptr) {
    ptr = Builder->CreateBitCast(ptr, mapType(resolv->getType(e))->getPointerTo());
    auto a = dynamic_cast<ArrayExpr *>(e);
    if (a) {
        array(a, ptr);
        return;
    }
    auto aa = dynamic_cast<ArrayAccess *>(e);
    if (aa) {
        auto arrty = resolv->getType(aa->array);
        slice(aa, ptr, arrty);
        return;
    }
    auto obj = dynamic_cast<ObjExpr *>(e);
    if (obj && !obj->isPointer) {
        object(obj, ptr, resolv->resolve(obj));
        return;
    }
    auto t = dynamic_cast<Type *>(e);
    if (t) {
        simpleVariant(t, ptr);
        return;
    }
    auto mc = dynamic_cast<MethodCall *>(e);
    if (mc) {
        call(mc, ptr);
        return;
    }
    error("child: " + e->print());
}

std::any Compiler::array(ArrayExpr *node, llvm::Value *ptr) {
    auto type = resolv->getType(node->list[0]);
    if(ptr->getType()->isArrayTy()){}
    if (node->isSized()) {
        print(node->print());
        ptr->getType()->dump();
        auto bb = Builder->GetInsertBlock();
        auto cur=gep(ptr, 0, 0);
        auto end=gep(ptr, 0, node->size.value());
        
        //create cons and memcpy
        auto condbb = llvm::BasicBlock::Create(ctx, "cond");
        auto setbb = llvm::BasicBlock::Create(ctx, "set");
        auto nextbb = llvm::BasicBlock::Create(ctx, "next");
        Builder->CreateBr(condbb);
        func->getBasicBlockList().push_back(condbb);
        Builder->SetInsertPoint(condbb);
        auto phi = Builder->CreatePHI(mapType(type)->getPointerTo(), 2);
        auto step=gep(phi, 1);
        cur->getType()->dump();
        step->getType()->dump();
        phi->addIncoming(cur, bb);
        phi->addIncoming(step, setbb);
        auto ne = Builder->CreateCmp(llvm::CmpInst::ICMP_NE, phi, end);
        Builder->CreateCondBr(branch(ne), setbb, nextbb);
        Builder->SetInsertPoint(setbb);
        func->getBasicBlockList().push_back(setbb);
        if(doesAlloc(node->list[0])){
            child(node->list[0], phi);
        }else{
            auto val = cast(node->list[0], type);
            Builder->CreateStore(val, phi);
        }
        Builder->CreateBr(condbb);
        //node->size.value()
        func->getBasicBlockList().push_back(nextbb);
        Builder->SetInsertPoint(nextbb);
    } else {
        int i = 0;
        for (auto e : node->list) {
            auto elem_target = gep(ptr, 0, i++);
            if (doesAlloc(e)) {
                child(e, elem_target);
            } else if (isStruct(type)) {
                auto val = gen(e);
                auto rt = resolv->getType(e);
                Builder->CreateMemCpy(elem_target, llvm::MaybeAlign(0), val, llvm::MaybeAlign(0), getSize(rt) / 8);
            } else {
                Builder->CreateStore(cast(e, type), elem_target);
            }
        }
    }
    return ptr;
}