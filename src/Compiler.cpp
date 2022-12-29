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

static std::unique_ptr<llvm::LLVMContext> TheContext;
static std::unique_ptr<llvm::Module> TheModule;
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
    TheContext = std::make_unique<llvm::LLVMContext>();
    TheModule = std::make_unique<llvm::Module>("test", *TheContext);

    // Create a new builder for the module.
    Builder = std::make_unique<llvm::IRBuilder<>>(*TheContext);
}

llvm::Type *getTy() {
    return llvm::Type::getInt32Ty(*TheContext);
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
    if(!t->isPrim()){
        auto it = classMap.find(s);
        if(it!=classMap.end()){
            std::cout<<"found type: "<<it->second<<std::endl;
            return it->second;
        }
    }
    if (s == "int") return llvm::Type::getInt32Ty(*TheContext);
    if (s == "void") return llvm::Type::getVoidTy(*TheContext);
    throw std::runtime_error("mapType: " + s);
}

static void make_printf_prototype() {
    auto pty = llvm::PointerType::get(llvm::IntegerType::get(*TheContext, 8), 0);
    std::vector<llvm::Type *> args;
    args.push_back(pty);
    auto ret = llvm::IntegerType::get(*TheContext, 32);
    auto ft =
                llvm::FunctionType::get(ret, args, true);
        auto *f = llvm::Function::Create(ft, llvm::Function::ExternalLinkage, "printf", TheModule.get());
        f->setCallingConv(llvm::CallingConv::C);
    llvm::AttributeList attr;
    f->setAttributes(attr);
    printf_proto = f;
}

static  void exit_prototype() {
    //auto *Pty = llvm::PointerType::get(llvm::IntegerType::get(mod->getContext(), 8), 0);
    auto vt = llvm::Type::getVoidTy(*TheContext);
    auto ft = llvm::FunctionType::get(vt, llvm::IntegerType::get(*TheContext, 32), false);
    auto f = llvm::Function::Create(ft, llvm::GlobalValue::ExternalLinkage, "exit", TheModule.get());
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

void createProtos(Unit *unit) {
    for(auto bd:unit->types){
        if(bd->isEnum) throw std::runtime_error("enum");
        auto td = dynamic_cast<TypeDecl*>(bd);
        std::vector<llvm::Type*> elems;
        for(auto field:td->fields){
            elems.push_back(mapType(field->type));
        }
        auto ty = llvm::StructType::create(elems, td->name);
        classMap[td->name]=ty;
    }
    for (auto m : unit->methods) {
        std::vector<llvm::Type *> argTypes;
        for (auto &prm : m->params) {
            argTypes.push_back(mapType(prm->type));
        }
        auto retType = mapType(m->type);
        auto FT =
                llvm::FunctionType::get(retType, argTypes, false);
        auto *f = llvm::Function::Create(FT, llvm::Function::ExternalLinkage, m->name, TheModule.get());
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
        Locals[prm->name]=prm->type;
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
    //todo
    InitializeModule();
    createProtos(unit);
    resolv=new Resolver (unit);
    for (auto m : unit->methods) {
        resolv->curMethod=m;
        curMethod= m;
        func = funcMap[m];
        BB = llvm::BasicBlock::Create(*TheContext, "entry", func);
        Builder->SetInsertPoint(BB);
        NamedValues.clear();
        Locals.clear();
        initParams(m);
        /*for (auto &Arg : func->args())
    NamedValues[std::string(Arg.getName())] = &Arg;*/

        m->body->accept(this, nullptr);
        if (m->type->print() == "void") {
            //todo insert ret in ast in other pass
            Builder->CreateRetVoid();
        }
        llvm::verifyFunction(*func);
        std::cout << "verified: " << m->name << std::endl;
    }
    //TheModule->print(,nullptr);
    //TheModule->dump();
    llvm::verifyModule(*TheModule, &llvm::outs());
    
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
    TheModule->setDataLayout(TargetMachine->createDataLayout());
    TheModule->setTargetTriple(TargetTriple);

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
    pass.run(*TheModule);
    dest.flush();
}

void *Compiler::visitBlock(Block *b, void *arg) {
    for (auto &s : b->list) {
        s->accept(this, nullptr);
    }
    return nullptr;
}

void *Compiler::visitReturnStmt(ReturnStmt *t, void *arg) {
    auto val = (llvm::Value *) t->expr->accept(this, nullptr);
    Builder->CreateRet(val);
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

llvm::Value *Compiler::loadPtr( Expression *e) {
    auto val =(llvm::Value *)e->accept (this, nullptr);
    if (dynamic_cast<Name *>(e) || dynamic_cast<DerefExpr *>(e) || dynamic_cast<FieldAccess *>(e)) {
        return load(val);
    }
    return val;
}

void* Compiler::visitParExpr(ParExpr *i, void* arg){
    return i->expr->accept(this, nullptr);
}

void *Compiler::visitInfix(Infix *i, void *arg) {
    auto l = loadPtr(i->left);
    auto r = loadPtr(i->right);
    if (i->op == "+") {
        return Builder->CreateNSWAdd(l, r);
    }
    if (i->op == "*") {
        return Builder->CreateMul(l, r);
    }
    if (i->op == "/") {
        return Builder->CreateSDiv(l, r);
    }
    if (i->op == "-") {
        return Builder->CreateSub(l, r);
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
    throw std::runtime_error("infix: " + i->print());
}

void* Compiler::visitAssign(Assign *i, void* arg){
    auto l =(llvm:: Value*) i->left->accept (this, nullptr);
    auto r=(llvm:: Value*) i->right->accept (this, nullptr);
    if(i->op == "=") return Builder->CreateStore(r, l);
    
    throw std::runtime_error("assign: " + i->print());
}

void *Compiler::visitSimpleName(SimpleName *n, void *arg) {
    auto it = NamedValues.find(n->name);
    if (it == NamedValues.end()) {
        throw std::runtime_error("unknown ref: " + n->name);
    }
    auto v = it->second;
    return v;
}

void *Compiler::visitMethodCall(MethodCall *mc, void *arg) {
    llvm::Function *f;
    if (mc->name == "print") {
        f = printf_proto;
    } else {
        auto resolv = new Resolver(unit);
        auto rt = (RType *) mc->accept(resolv, nullptr);
        f = funcMap[rt->targetMethod];
    }
    std::vector<llvm::Value *> args;
    for (unsigned i = 0, e = mc->args.size(); i != e; ++i) {
        auto a = mc->args[i];
        auto av = loadPtr(a);
        args.push_back(av);
        if (!args.back())
            throw std::runtime_error("arg null: " + a->print());
    }
    return Builder->CreateCall(f, args);
}

llvm::Value *makeStr(std::string str) {
    //0. Def
    auto charType = llvm::IntegerType::get(*TheContext, 8);
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
    auto glob = (llvm::GlobalVariable *) TheModule->getOrInsertGlobal(name, stringType);
    glob->setInitializer(llvm::ConstantArray::get(stringType, chars));
    glob->setConstant(true);
    glob->setLinkage(llvm::GlobalValue::LinkageTypes::PrivateLinkage);
    glob->setUnnamedAddr(llvm::GlobalValue::UnnamedAddr::Global);
    //4. Return a cast to an i8*
    return llvm::ConstantExpr::getBitCast(glob, charType->getPointerTo());
}

llvm::ConstantInt *makeInt(int val) {
    auto intType = llvm::IntegerType::get(*TheContext, 32);
    return llvm::ConstantInt::get(intType, val);
}

void *Compiler::visitLiteral(Literal *n, void *arg) {
    if (n->isStr) {
        //auto ptr = llvm::PointerType::get(llvm::IntegerType::get(*TheContext, 8), 0);
        auto trimmed = n->val.substr(1, n->val.size() - 2);
        return makeStr(trimmed);
    }
    if (n->isInt) {
        auto intType = llvm::IntegerType::get(*TheContext, 32);
        return llvm::ConstantInt::get(intType, atoi(n->val.c_str()));
    }
    throw std::runtime_error("literal: " + n->print());
}

void *Compiler::visitAssertStmt(AssertStmt *n, void *arg) {
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
    return nullptr;
}

void *Compiler::visitVarDecl(VarDecl *n, void *arg) {
    for (auto f : n->decl->list) {
        if(!f->rhs) throw std:: runtime_error("var '"+f->name+"' has no initializer");
        auto val = (llvm::Value *) f->rhs->accept(this, nullptr);
        Locals[f->name]=f->type;
            //depends on rhs type; copy,ptr...
            if(dynamic_cast<ObjExpr*>(f->rhs)){
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
    auto ty = (val->getType())->getPointerElementType();
    return Builder->CreateLoad(ty, val);
}

void* Compiler::visitObjExpr(ObjExpr *n, void* arg){
    auto ty = mapType(n->type);
    auto ptr = Builder->CreateAlloca(ty, (unsigned)0);
    int i=0;
    for(auto &e:n->entries){
        std::vector<llvm:: Value*> idx;
        idx.push_back(makeInt(0));
        idx.push_back(makeInt(i));
        auto eptr=llvm::GetElementPtrInst::CreateInBounds(ty, ptr, idx,"", BB);
        auto val = (llvm::Value*)e.value->accept (this, nullptr);
        Builder->CreateStore (val, eptr);
        i++;
    }
    return ptr;
}

void* Compiler::visitFieldAccess(FieldAccess *n, void* arg){
    auto sc = (llvm::Value*)n->scope->accept(this, nullptr);
    auto ty = sc->getType ()->getPointerElementType();
    std::vector<llvm:: Value*> idx;
    idx.push_back(makeInt(0));
    auto sn = dynamic_cast<SimpleName*>( n->scope);
    if(!sn) throw std:: runtime_error("FA: "+n->print());
    int index = -1;
    //local,param
    auto it = Locals.find(sn->name);
    if(it==Locals.end()) throw std:: runtime_error(sn->name + " not found");
    auto sct=it->second;
    auto sctt=(RType*)sct->accept(resolv, nullptr);
    auto td=dynamic_cast<TypeDecl*>(sctt->targetDecl);
    for(int i=0;i<td->fields.size();i++){
        if(td->fields[i]->name==n->name){
            index=i;
            break;
        }
    }
    if(index == -1) throw std:: runtime_error("unknown field: "+n->name+ " of type "+sct->print());
    idx.push_back(makeInt(index));
    auto eptr=llvm::GetElementPtrInst::CreateInBounds(ty, sc, idx,"", BB);
    return eptr;
}