#include "Compiler.h"
#include "Resolver.h"
#include "parser/Ast.h"
#include "parser/Parser.h"
#include <filesystem>
#include <iostream>
#include <unordered_map>

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

//using namespace llvm;

std::string getName(const std::string &path) {
    auto i = path.rfind('/');
    return path.substr(i + 1);
}

void Compiler::compileAll() {
    for (const auto &e : fs::recursive_directory_iterator(srcDir)) {
        if (e.is_directory()) continue;
        compile(e.path().string());
    }
}

static std::unique_ptr<llvm::LLVMContext> ctx;
static std::unique_ptr<llvm::Module> mod;
static std::unique_ptr<llvm::IRBuilder<>> Builder;
static std::map<std::string, Type *> Locals;
static std::map<std::string, llvm::Value *> NamedValues;
std::map<Method *, llvm::Function *> funcMap;
std::map<std::string, llvm::Type *> classMap;
llvm::BasicBlock *BB;
llvm::Function *printf_proto;
llvm::Function *exit_proto;
int strCnt = 0;

static void InitializeModule() {
    // Open a new context and module.
    ctx = std::make_unique<llvm::LLVMContext>();
    mod = std::make_unique<llvm::Module>("test", *ctx);

    // Create a new builder for the module.
    Builder = std::make_unique<llvm::IRBuilder<>>(*ctx);
}

llvm::Value *makeStr(std::string str) {
    //0. Def
    auto charType = llvm::IntegerType::get(*ctx, 8);
    //1. Initialize chars vector
    std::vector<llvm::Constant *> chars(str.length());
    for (unsigned int i = 0; i < str.size(); i++) {
        chars[i] = llvm::ConstantInt::get(charType, str[i]);
    }
    //1b. add a zero terminator too
    chars.push_back(llvm::ConstantInt::get(charType, 0));
    //2. Initialize the string from the characters
    auto stringType = llvm::ArrayType::get(charType, chars.size());

    //3. Create the declaration statement
    auto name = std::string(".str") + std::to_string(++strCnt);
    auto glob = (llvm::GlobalVariable *) mod->getOrInsertGlobal(name, stringType);
    glob->setInitializer(llvm::ConstantArray::get(stringType, chars));
    glob->setConstant(true);
    glob->setLinkage(llvm::GlobalValue::LinkageTypes::PrivateLinkage);
    glob->setUnnamedAddr(llvm::GlobalValue::UnnamedAddr::Global);
    //4. Return a cast to an i8*
    return llvm::ConstantExpr::getBitCast(glob, charType->getPointerTo());
}

llvm::ConstantInt *makeInt(int val) {
    auto intType = llvm::IntegerType::get(*ctx, 32);
    return llvm::ConstantInt::get(intType, val);
}

llvm::Type *getTy() {
    return llvm::Type::getInt32Ty(*ctx);
}

llvm::Type *getInt(int bit) {
    return llvm::IntegerType::get(*ctx, bit);
}

llvm::Type *getElem(llvm::Type *t) {
    if (t->isPointerTy()) return getTy();
    t->dump();
    throw std::runtime_error("getElem: ");
}

llvm::Type *mapType(Type *t) {
    auto ptr = dynamic_cast<PointerType *>(t);
    if (ptr) {
        return llvm::PointerType::get(mapType(ptr->type), 0);
    }
    auto s = t->print();
    if (t->isVoid()) return llvm::Type::getVoidTy(*ctx);
    if (t->isPrim()) {
        if (s == "byte" || s == "i8" || s=="bool") return getInt(8);
        if (s == "short" || s == "i16") return getInt(16);
        if (s == "int" || s == "i32") return getInt(32);
        if (s == "long" || s == "i64") return getInt(64);
    } else {
        auto it = classMap.find(s);
        if (it != classMap.end()) {
            return it->second;
        }
    }
    throw std::runtime_error("mapType: " + s);
}

llvm::Value* branch(llvm::Value* val){
    auto ty = llvm::cast<llvm::IntegerType>(val->getType());
    if(ty){
       auto w = ty->getBitWidth();
       if(w!=1){
           return Builder->CreateTrunc(val, getInt(1));
       }
    }
    return val;
}

static void make_printf_prototype() {
    auto pty = llvm::PointerType::get(llvm::IntegerType::get(*ctx, 8), 0);
    std::vector<llvm::Type *> args;
    args.push_back(pty);
    auto ret = llvm::IntegerType::get(*ctx, 32);
    auto ft =
            llvm::FunctionType::get(ret, args, true);
    auto *f = llvm::Function::Create(ft, llvm::Function::ExternalLinkage, "printf", mod.get());
    f->setCallingConv(llvm::CallingConv::C);
    llvm::AttributeList attr;
    f->setAttributes(attr);
    printf_proto = f;
}

static void exit_prototype() {
    //auto *Pty = llvm::PointerType::get(llvm::IntegerType::get(mod->getContext(), 8), 0);
    auto vt = llvm::Type::getVoidTy(*ctx);
    auto ft = llvm::FunctionType::get(vt, llvm::IntegerType::get(*ctx, 32), false);
    auto f = llvm::Function::Create(ft, llvm::GlobalValue::ExternalLinkage, "exit", mod.get());
    f->setCallingConv(llvm::CallingConv::C);
    llvm::AttributeList attr;
    f->setAttributes(attr);
    exit_proto = f;
}

/*void init_assert(){
    auto vt = llvm::Type::getVoidTy(*TheContext);
    auto ft = llvm::FunctionType::get(vt, llvm::IntegerType::get(*TheContext, 32), false);
    std::vector<llvm::Type *> argTypes;
    
    auto str = n->expr->print();
    auto cond = loadPtr(n->expr);
    auto then = llvm::BasicBlock::Create(*TheContext, "lb1", func);
    auto next = llvm::BasicBlock::Create(*TheContext, "lb2");
    Builder->CreateCondBr(cond, next, then);

    Builder->SetInsertPoint(then);
    //print error and exit
    auto msg = std::string("assertion ") + str + " failed\n";
    std::vector<llvm::Value *> pr_args = {makeStr(msg)};
    Builder->CreateCall(printf_proto, pr_args, "calltmp");
    std::vector<llvm::Value *> args = {makeInt(1)};
    Builder->CreateCall(exit_proto, args);
    Builder->CreateUnreachable();

    Builder->SetInsertPoint(next);
    func->getBasicBlockList().push_back(next);
    BB = next;
}*/
static int size(Type *type) {
    auto s = type->print();
    if (s == "byte" || s=="bool") return 1;
    if (s == "int") return 4;
    if (s == "long") return 8;
    throw std::runtime_error("size(" + s + ")");
}

static int size(EnumDecl *e) {
    int res = 0;
    for (auto ee : e->variants) {
        if (ee->params.empty()) continue;
        int cur = 0;
        for (auto ep : ee->params) {
            cur += size(ep->type);
        }
        res = cur > res ? cur : res;
    }
    return res;
}
void print(const std::string &msg) {
    std::cout << msg << std::endl;
}

void createProtos(Unit *unit) {
    for (auto bd : unit->types) {
        std::vector<llvm::Type *> elems;
        auto ed = dynamic_cast<EnumDecl *>(bd);
        print("proto " + bd->name);
        if (ed) {
            int sz = size(ed);
            std::cout << "sizeof enum=" << sz << std::endl;
            elems.push_back(getTy());
            auto charType = llvm::IntegerType::get(*ctx, 8);
            auto stringType = llvm::ArrayType::get(charType, sz);
            elems.push_back(stringType);
        } else {
            auto td = dynamic_cast<TypeDecl *>(bd);
            for (auto field : td->fields) {
                elems.push_back(mapType(field->type));
            }
            print(std::to_string(td->fields.size()) + " fields");
        }
        auto ty = llvm::StructType::create(*ctx, elems, bd->name);
        classMap[bd->name] = ty;
        ty->dump();
    }
    for (auto m : unit->methods) {
        std::vector<llvm::Type *> argTypes;
        for (auto &prm : m->params) {
            argTypes.push_back(mapType(prm->type));
        }
        auto retType = mapType(m->type);
        auto FT =
                llvm::FunctionType::get(retType, argTypes, false);
        auto *f = llvm::Function::Create(FT, llvm::Function::ExternalLinkage, m->name, mod.get());
        unsigned Idx = 0;
        for (auto &Arg : f->args()) {
            Arg.setName(m->params[Idx++]->name);
        }
        funcMap[m] = f;
    }
    make_printf_prototype();
    exit_prototype();
}

void initParams(Method *m) {
    int i = 0;
    for (auto &arg : funcMap[m]->args()) {
        auto prm = m->params[i];
        auto ty = mapType(prm->type);
        auto ptr = Builder->CreateAlloca(ty);
        auto val = &arg;
        Builder->CreateStore(val, ptr);
        NamedValues[prm->name] = ptr;
        Locals[prm->name] = prm->type;
        i++;
    }
}

void Compiler::compile(const std::string &path) {
    auto name = getName(path);
    if (path.rfind(".x") == std::string::npos) {
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

    InitializeModule();
    createProtos(unit);
    resolv = new Resolver(unit);
    for (auto m : unit->methods) {
        resolv->curMethod = m;
        curMethod = m;
        func = funcMap[m];
        BB = llvm::BasicBlock::Create(*ctx, "entry", func);
        Builder->SetInsertPoint(BB);
        NamedValues.clear();
        Locals.clear();
        initParams(m);
        //        for (auto &Arg : func->args()){
        //            NamedValues[std::string(Arg.getName())] = &Arg;
        //        }
        m->body->accept(this, nullptr);
        if (m->type->print() == "void") {
            //todo insert ret in ast in other pass
            Builder->CreateRetVoid();
        }
        llvm::verifyFunction(*func);
        std::cout << "verified: " << m->name << std::endl;
    }
    //TheModule->print(,nullptr);
    mod->dump();
    llvm::verifyModule(*mod, &llvm::outs());

    auto TargetTriple = llvm::sys::getDefaultTargetTriple();
    llvm::InitializeAllTargetInfos();
    llvm::InitializeAllTargets();
    llvm::InitializeAllTargetMCs();
    llvm::InitializeAllAsmParsers();
    llvm::InitializeAllAsmPrinters();
    std::string Error;
    auto Target = llvm::TargetRegistry::lookupTarget(TargetTriple, Error);

    // Print an error and exit if we couldn't find the requested target.
    // This generally occurs if we've forgotten to initialise the
    // TargetRegistry or we have a bogus target triple.
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

    auto Filename = name + ".o";
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

llvm::BasicBlock *getBB() {
    return Builder->GetInsertBlock();
}

void *Compiler::visitBlock(Block *b, void *arg) {
    for (auto &s : b->list) {
        s->accept(this, nullptr);
    }
    /*if(!dynamic_cast<ReturnStmt*>(b->list.back())){
        if(curMethod->type->print() == "void"){
            Builder->CreateRetVoid ();
        }else{
            throw std:: runtime_error("non void function doesn't have return as last statement");
        }
    }*/
    return nullptr;
}

void *Compiler::visitReturnStmt(ReturnStmt *t, void *arg) {
    if (t->expr) {
        expect = func->getReturnType();
        auto val = (llvm::Value *) t->expr->accept(this, nullptr);
        Builder->CreateRet(val);
    } else {
        Builder->CreateRetVoid();
    }
    return nullptr;
}

void *Compiler::visitExprStmt(ExprStmt *b, void *arg) {
    return b->expr->accept(this, nullptr);
}

llvm::Value *load(llvm::Value *val) {
    //auto ty = getElem(val->getType ());
    auto ty = val->getType()->getPointerElementType();
    return Builder->CreateLoad(ty, val);
}

llvm::Value *Compiler::loadPtr(Expression *e) {
    auto val = (llvm::Value *) e->accept(this, nullptr);
    if (dynamic_cast<Name *>(e) || dynamic_cast<DerefExpr *>(e) || dynamic_cast<FieldAccess *>(e)) {
        return load(val);
    }
    return val;
}

void *Compiler::visitParExpr(ParExpr *i, void *arg) {
    return i->expr->accept(this, nullptr);
}

llvm::Value* Compiler::andOr(llvm::Value* l, llvm::Value* r, bool isand){
    auto bb=getBB();
        auto then = llvm::BasicBlock::Create(*ctx, "", func);
        auto next = llvm::BasicBlock::Create(*ctx, "");
        if(isand){
            Builder->CreateCondBr(branch(l), then, next);
        }else{
            Builder->CreateCondBr(branch(l), next, then);
        }
        Builder->SetInsertPoint(then);
        BB=then;
        //Builder->CreateLoad();
        //auto rr=load(r);
        auto rbit=Builder->CreateTrunc(r, getInt(1));
        Builder->CreateBr(next);
        Builder->SetInsertPoint(next);
        func->getBasicBlockList().push_back(next);
        BB=next;
        auto phi=Builder->CreatePHI(getInt(1), 2);
        phi->addIncoming(isand?Builder->getFalse():Builder->getTrue(), bb);
        phi->addIncoming(rbit, then);
        auto ext=Builder->CreateZExt(phi, getInt(8));
    return ext;
}

void *Compiler::visitInfix(Infix *i, void *arg) {
    auto l = loadPtr(i->left);
    auto r = loadPtr(i->right);
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
    if(i->op == "&&"){
        //res=(l==true?r:false)
        return andOr(l,r,true);
    }
    if(i->op== "||"){
        //res=(l==true?true:r)
        return andOr(l,r,false);
    }
    throw std::runtime_error("infix: " + i->print());
}

void *Compiler::visitAssign(Assign *i, void *arg) {
    auto l = (llvm::Value *) i->left->accept(this, nullptr);
    expect = l->getType()->getPointerElementType();
    auto r = (llvm::Value *) i->right->accept(this, nullptr);
    if (i->op == "=") return Builder->CreateStore(r, l);

    throw std::runtime_error("assign: " + i->print());
}

void *Compiler::visitSimpleName(SimpleName *n, void *arg) {
    auto it = NamedValues.find(n->name);
    if (it == NamedValues.end()) {
        for(auto &[n,v]:NamedValues){
            std::cout << n<<", ";
        }
        throw std::runtime_error("unknown ref: " + n->name);
    }
    return it->second;
}

void *Compiler::visitMethodCall(MethodCall *mc, void *arg) {
    llvm::Function *f;
    if (mc->name == "print") {
        f = printf_proto;
    } else {
        auto rt = (RType *) mc->accept(resolv, nullptr);
        f = funcMap[rt->targetMethod];
    }
    std::vector<llvm::Value *> args;
    for (unsigned i = 0, e = mc->args.size(); i != e; ++i) {
        auto a = mc->args[i];
        auto av = loadPtr(a);
        args.push_back(av);
        if (!args.back()) {
            throw std::runtime_error("arg null: " + a->print());
        }
    }
    return Builder->CreateCall(f, args);
}

void *Compiler::visitLiteral(Literal *n, void *arg) {
    if (n->isStr) {
        auto trimmed = n->val.substr(1, n->val.size() - 2);
        return makeStr(trimmed);
    }else if (n->isInt) {
        auto bits = expect->getScalarSizeInBits();
        std::cout << "expect: " << bits << std::endl;

        auto intType = llvm::IntegerType::get(*ctx, bits);
        return llvm::ConstantInt::get(intType, atoi(n->val.c_str()));
    }else if(n->isBool){
        auto intType = llvm::IntegerType::get(*ctx, 8);
        auto bval = n->val == "true" ? 1:0;
        return llvm::ConstantInt::get(intType, bval);
    }
    throw std::runtime_error("literal: " + n->print());
}

void *Compiler::visitAssertStmt(AssertStmt *n, void *arg) {
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
    BB = next;
    return nullptr;
}

void *Compiler::visitVarDecl(VarDecl *n, void *arg) {
    for (auto f : n->decl->list) {
        if (!f->rhs) throw std::runtime_error("var '" + f->name + "' has no initializer");
        auto val = (llvm::Value *) f->rhs->accept(this, nullptr);
        Locals[f->name] = f->type;
        //depends on rhs type; copy,ptr...
        /*if(llvm::dyn_cast<llvm::AllocaInst>(val)){
                NamedValues[f->name] = val;
                continue;
            }*/
        if (dynamic_cast<ObjExpr *>(f->rhs) || dynamic_cast<Type *>(f->rhs)) {
            NamedValues[f->name] = val;
            continue;
        }

        auto ty = mapType(f->type);
        auto ptr = Builder->CreateAlloca(ty);
        Builder->CreateStore(val, ptr);
        NamedValues[f->name] = ptr;
    }
    return nullptr;
}

void *Compiler::visitRefExpr(RefExpr *n, void *arg) {
    auto inner = (llvm::Value *) n->expr->accept(this, nullptr);
    //todo rvalue
    //auto pt = llvm::PointerType::get(inner->getType(), 0);
    auto pt = inner->getType();
    //todo not needed for name,already ptr
    //return Builder->CreateLoad(pt, inner);
    return inner;
}

void *Compiler::visitDerefExpr(DerefExpr *n, void *arg) {
    auto val = (llvm::Value *) n->expr->accept(this, nullptr);
    auto ty = val->getType()->getPointerElementType();
    return Builder->CreateLoad(ty, val);
}

EnumDecl *findEnum(Type *type, Resolver *resolv) {
    auto rt = (RType *) type->accept(resolv, nullptr);
    return dynamic_cast<EnumDecl *>(rt->targetDecl);
}

int findVariant(EnumDecl *decl, std::string name) {
    for (int i = 0; i < decl->variants.size(); i++) {
        if (decl->variants[i]->name == name) {
            return i;
        }
    }
    throw std::runtime_error("unknown variant: " + name + " of type " + decl->name);
}

void setOrdinal(int index, llvm::Value *ptr, llvm::Type *ty) {
    //ty->print(llvm::outs(), true, true);
    //ty->dump();
    //ptr->dump();
    std::vector<llvm::Value *> ordidx = {makeInt(0), makeInt(0)};
    auto ordPtr = llvm::GetElementPtrInst::CreateInBounds(ty, ptr, ordidx, "", BB);
    Builder->CreateStore(makeInt(index), ordPtr);
}

/*llvm::Value *implicit(llvm::Value *val, llvm::Type *target) {
    auto src = val->getType();
    if (src->isIntegerTy()) {
        if (!target->isIntegerTy()) {
            throw std::runtime_error("src is integer but target is not");
        }
        if (llvm::isa<llvm::Constant>(val)) {
            std::cout << "isa" << std::endl;
        }
        return Builder->CreateBitCast(val, target->getPointerTo());
    }
    throw std::runtime_error("cant do implicit cast from ");
}*/

void *Compiler::visitObjExpr(ObjExpr *n, void *arg) {
    //enum or class
    if (n->type->scope) {
        auto enumTy = mapType(n->type->scope);
        auto decl = findEnum(n->type->scope, resolv);
        auto index = findVariant(decl, n->type->name);
        auto ptr = Builder->CreateAlloca(enumTy, (unsigned) 0);

        setOrdinal(index, ptr, enumTy);
        std::vector<llvm::Value *> dataIdx = {makeInt(0), makeInt(1)};
        auto dataPtr = llvm::GetElementPtrInst::CreateInBounds(enumTy, ptr, dataIdx, "", BB);
        auto variant = decl->variants[index];
        int offset = 0;
        for (int i = 0; i < variant->params.size(); i++) {
            auto cons = variant->params[i];
            std::vector<llvm::Value *> entIdx = {makeInt(0), makeInt(offset)};

            auto entPtr = llvm::GetElementPtrInst::CreateInBounds(dataPtr->getType()->getPointerElementType(), dataPtr, entIdx, "", BB);
            auto targetTy = mapType(cons->type);
            expect = targetTy;
            auto val = (llvm::Value *) n->entries[i].value->accept(this, nullptr);
            //todo bitcast to target type
            //auto val2 = implicit(val, targetTy);
            auto cast = Builder->CreateBitCast(entPtr, targetTy->getPointerTo());
            Builder->CreateStore(val, cast);
            offset += size(cons->type);
        }
        return ptr;
    } else {
        auto ty = mapType(n->type);
        auto ptr = Builder->CreateAlloca(ty, (unsigned) 0);
        int i = 0;
        for (auto &e : n->entries) {
            std::vector<llvm::Value *> idx = {makeInt(0), makeInt(i)};
            auto eptr = llvm::GetElementPtrInst::CreateInBounds(ty, ptr, idx, "", BB);
            auto val = (llvm::Value *) e.value->accept(this, nullptr);
            Builder->CreateStore(val, eptr);
            i++;
        }
        return ptr;
    }
}

int findIndex(Type *type, std::string name, Resolver *resolv) {
    auto sctt = (RType *) type->accept(resolv, nullptr);
    auto td = dynamic_cast<TypeDecl *>(sctt->targetDecl);
    for (int i = 0; i < td->fields.size(); i++) {
        if (td->fields[i]->name == name) {
            return i;
        }
    }
    throw std::runtime_error("unknown field: " + name + " of type " + type->print());
}

void *Compiler::visitType(Type *n, void *arg) {
    if (!n->scope) throw std::runtime_error("type has no scope");
    //todo scope, resolv
    auto enumTy = mapType(n->scope);
    if (!enumTy) throw std::runtime_error("type not found: " + n->scope->print());
    //enum variant without struct
    auto ptr = Builder->CreateAlloca(enumTy, (unsigned) 0);
    int index = findVariant(findEnum(n->scope, resolv), n->name);
    setOrdinal(index, ptr, enumTy);
    return ptr;
}

void *Compiler::visitFieldAccess(FieldAccess *n, void *arg) {
    auto sc = (llvm::Value *) n->scope->accept(this, nullptr);
    auto ty = sc->getType()->getPointerElementType();
    auto sn = dynamic_cast<SimpleName *>(n->scope);
    if (!sn) throw std::runtime_error("FA: " + n->print());
    //local,param
    auto it = Locals.find(sn->name);
    if (it == Locals.end()) throw std::runtime_error(sn->name + " not found");
    auto sct = it->second;
    int index = findIndex(sct, n->name, resolv);

    std::vector<llvm::Value *> idx = {makeInt(0), makeInt(index)};
    auto eptr = llvm::GetElementPtrInst::CreateInBounds(ty, sc, idx, "", BB);
    return eptr;
}

void *Compiler::visitIfStmt(IfStmt *b, void *arg) {
    auto cond =  branch(loadPtr(b->expr));

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
    b->thenStmt->accept(this, nullptr);
    Builder->CreateBr(next);
    if (b->elseStmt) {
        Builder->SetInsertPoint(elsebb);
        func->getBasicBlockList().push_back(elsebb);
        b->elseStmt->accept(this, nullptr);
        Builder->CreateBr(next);
    }
    Builder->SetInsertPoint(next);
    func->getBasicBlockList().push_back(next);
    BB = next;
    return nullptr;
}

void *Compiler::visitIfLetStmt(IfLetStmt *b, void *arg) {
    auto rhs = (llvm::Value *) b->rhs->accept(this, nullptr);
    std::vector<llvm::Value *> idx = {makeInt(0), makeInt(0)};
    auto ty = rhs->getType()->getPointerElementType();
    auto ordptr = llvm::GetElementPtrInst::CreateInBounds(ty, rhs, idx, "", BB);
    auto ord = Builder->CreateLoad(getTy(), ordptr);
    auto decl = findEnum(b->type->scope, resolv);
    auto index = findVariant(decl, b->type->name);
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
    BB=then;

    auto variant = decl->variants[index];
    if (!variant->params.empty()) {
        //declare vars
        auto &params = variant->params;
        std::vector<llvm::Value *> dataIdx = {makeInt(0), makeInt(1)};
        auto dataPtr = llvm::GetElementPtrInst::CreateInBounds(ty, rhs, dataIdx, "", getBB());
        int offset = 0;
        for (int i = 0; i < params.size(); i++) {
            //regular var decl
            auto prm = params[i];
            auto argName = b->args[i];
            std::vector<llvm::Value *> idx = {makeInt(0), makeInt(offset)};
            auto ptr = llvm::GetElementPtrInst::CreateInBounds(dataPtr->getType()->getPointerElementType(), dataPtr, idx, "", getBB ());
            //bitcast to real type
            auto targetTy = mapType(prm->type);
            auto ptrReal = Builder->CreateBitCast(ptr, targetTy->getPointerTo());
            NamedValues[argName] = ptrReal;
            
            offset+= size(prm->type);
        }
    }
    b->thenStmt->accept(this, nullptr);
    //clear params
    for(auto &p:b->args){
        NamedValues.erase(p);
    }
    Builder->CreateBr(next);
    if (b->elseStmt) {
        Builder->SetInsertPoint(elsebb);
        func->getBasicBlockList().push_back(elsebb);
        b->elseStmt->accept(this, nullptr);
        Builder->CreateBr(next);
    }
    Builder->SetInsertPoint(next);
    func->getBasicBlockList().push_back(next);
    BB = next;
    return nullptr;
}