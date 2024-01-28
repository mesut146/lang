#include <llvm/IR/DIBuilder.h>
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Value.h>
#include <llvm/Target/TargetMachine.h>
#include "llvm/Transforms/IPO/PassManagerBuilder.h"
#include <llvm/IR/Attributes.h>
#include <llvm/IR/Constants.h>
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/LegacyPassManager.h>
#include <llvm/IR/Value.h>
#include <llvm/IR/Verifier.h>
#include <llvm/MC/TargetRegistry.h>
#include <llvm/Support/FileSystem.h>
#include <llvm/Support/Host.h>
#include <llvm/Support/TargetSelect.h>
#include <llvm/Target/TargetOptions.h>

#include <iostream>
#include <vector>


static llvm::IRBuilder<> *Builder = nullptr;
static llvm::LLVMContext *ctx = nullptr;
static llvm::Module *mod = nullptr;

extern "C" {

std::vector<llvm::Type *> *make_vec() {
    return new std::vector<llvm::Type *>();
}

void vec_push(std::vector<llvm::Type *> *vec, llvm::Type *type) {
    vec->push_back(type);
}

void setBuilder(llvm::IRBuilder<> *b) {
    Builder = b;
}
void setModule(llvm::Module *m) {
    mod = m;
}
void setCtx(llvm::LLVMContext *c) {
    ctx = c;
}

int getDefaultTargetTriple(char *ptr) {
    std::string res = llvm::sys::getDefaultTargetTriple();
    memcpy(ptr, res.data(), res.length());
    return res.length();
}

void InitializeAllTargetInfos() {
    llvm::InitializeAllTargetInfos();
}
void InitializeAllTargets() {
    llvm::InitializeAllTargets();
}
void InitializeAllTargetMCs() {
    llvm::InitializeAllTargetMCs();
}
void InitializeAllAsmParsers() {
    llvm::InitializeAllAsmParsers();
}
void InitializeAllAsmPrinters() {
    llvm::InitializeAllAsmPrinters();
}

const llvm::Target *lookupTarget(const char *triple) {
    std::string TargetTriple(triple);
    std::string Error;
    auto Target = llvm::TargetRegistry::lookupTarget(TargetTriple, Error);
    if (!Target) {
        throw std::runtime_error(Error);
    }
    return Target;
}

llvm::TargetMachine *createTargetMachine(const char *triple) {
    std::string TargetTriple(triple);
    auto Target = lookupTarget(triple);

    auto CPU = "generic";
    auto Features = "";
    llvm::TargetOptions opt;
    auto RM = std::optional<llvm::Reloc::Model>(llvm::Reloc::Model::PIC_);
    return Target->createTargetMachine(TargetTriple, CPU, Features, opt, RM);
}

void emit(const char *name, llvm::TargetMachine *TargetMachine, char *triple) {
    std::string TargetTriple(triple);
    std::string Filename(name);
    llvm::verifyModule(*mod, &llvm::outs());
    mod->setDataLayout(TargetMachine->createDataLayout());
    mod->setTargetTriple(TargetTriple);

    std::error_code EC;
    llvm::raw_fd_ostream dest(Filename, EC, llvm::sys::fs::OF_None);

    if (EC) {
        std::cerr << "Could not open file: " << EC.message();
        exit(1);
    }

    llvm::legacy::PassManager pass;
    if (TargetMachine->addPassesToEmitFile(pass, dest, nullptr, llvm::CGFT_ObjectFile)) {
        std::cerr << "TargetMachine can't emit a file of this type";
        exit(1);
    }
    pass.run(*mod);

    dest.flush();
    dest.close();
}

llvm::LLVMContext *make_ctx() {
    ctx = new llvm::LLVMContext();
    return ctx;
}

llvm::Module *make_module(char *name, llvm::TargetMachine *TargetMachine, char *triple) {
    std::string TargetTriple(triple);
    mod = new llvm::Module(name, *ctx);
    mod->setTargetTriple(TargetTriple);
    mod->setDataLayout(TargetMachine->createDataLayout());
    return mod;
}

llvm::IRBuilder<> *make_builder() {
    Builder = new llvm::IRBuilder<>(*ctx);
    return Builder;
}

void emit_llvm(char *llvm_file) {
    std::error_code ec;
    llvm::raw_fd_ostream fd(llvm_file, ec);
    mod->print(fd, nullptr);
}

llvm::Type *getVoidTy() {
    return Builder->getVoidTy();
}

llvm::FunctionType *make_ft(llvm::Type *retType, std::vector<llvm::Type *> *argTypes, bool vararg) {
    return llvm::FunctionType::get(retType, *argTypes, vararg);
}

llvm::Function *make_func(llvm::FunctionType *ft, llvm::GlobalValue::LinkageTypes *linkage, char *name) {
    return llvm::Function::Create(ft, *linkage, name, *mod);
}

void setCallingConv(llvm::Function *f) {
    f->setCallingConv(llvm::CallingConv::C);
}

llvm::GlobalValue::LinkageTypes ext() {
    return llvm::Function::ExternalLinkage;
}

llvm::GlobalValue::LinkageTypes odr() {
    return llvm::Function::LinkOnceODRLinkage;
}

llvm::Argument *get_arg(llvm::Function *f, int i) {
    return f->getArg(i);
}

void arg_setName(llvm::Argument *arg, char *name) {
    arg->setName(name);
}

void arg_attr(llvm::Argument *arg, llvm::Attribute::AttrKind *attr) {
    arg->addAttr(*attr);
}

llvm::Attribute::AttrKind get_sret() {
    return llvm::Attribute::StructRet;
}

llvm::StructType *make_struct_ty(char *name) {
    return llvm::StructType::create(*ctx, name);
}
llvm::StructType *make_struct_ty2(char *name, std::vector<llvm::Type *> *elems) {
    return llvm::StructType::create(*ctx, *elems, name);
}

int getSizeInBits(llvm::StructType *st) {
    return mod->getDataLayout().getStructLayout(st)->getSizeInBits();
}

llvm::ArrayType *get_arrty(llvm::Type *elem, int size) {
    return llvm::ArrayType::get(elem, size);
}

llvm::Type *getPtr() {
    return llvm::PointerType::getUnqual(*ctx);
}

llvm::GlobalVariable *make_stdout() {
    auto res = new llvm::GlobalVariable(*mod, getPtr(), false, llvm::GlobalValue::ExternalLinkage, nullptr, "stdout");
    res->addAttribute("global");
    return res;
}

llvm::AllocaInst *Builder_alloca(llvm::Type *ty) {
    return Builder->CreateAlloca(ty);
}

void Value_setName(llvm::Value *val, char *name) {
    val->setName(name);
}

void store(llvm::Value *val, llvm::Value *ptr) {
    Builder->CreateStore(val, ptr);
}

llvm::BasicBlock *create_bb2(llvm::Function *func) {
    return llvm::BasicBlock::Create(*ctx, "", func);
}

llvm::BasicBlock *create_bb() {
    return llvm::BasicBlock::Create(*ctx, "");
}

void set_insert(llvm::BasicBlock *bb) {
    Builder->SetInsertPoint(bb);
}

llvm::BasicBlock *get_insert() {
    return Builder->GetInsertBlock();
}

void call(llvm::Function *f, std::vector<llvm::Value *> *args) {
    Builder->CreateCall(f, *args);
}

void ret(llvm::Value *val) {
    Builder->CreateRet(val);
}

void ret_void() {
    Builder->CreateRetVoid();
}

void verify(llvm::Function *func) {
    llvm::verifyFunction(*func, &llvm::outs());
}

void CreateCondBr(llvm::Value *cond, llvm::BasicBlock *then, llvm::BasicBlock *next) {
    Builder->CreateCondBr(cond, then, next);
}

llvm::Value *CreateZExt(llvm::Value *val, llvm::Type *type) {
    return Builder->CreateZExt(val, type);
}

int getPrimitiveSizeInBits(llvm::Type *type) {
    return type->getPrimitiveSizeInBits();
}

llvm::Type *Value_getType(llvm::Value *val) {
    return val->getType();
}

void CreateBr(llvm::BasicBlock *bb) {
    Builder->CreateBr(bb);
}

llvm::PHINode *CreatePHI(llvm::Type *type) {
    return Builder->CreatePHI(type, 2);
}

void addIncoming(llvm::PHINode *phi, llvm::Value *val, llvm::BasicBlock *bb) {
    phi->addIncoming(val, bb);
}

llvm::CmpInst::Predicate get_comp_op(const std::string &op) {
    if (op == "==") {
        return llvm::CmpInst::ICMP_EQ;
    }
    if (op == "!=") {
        return llvm::CmpInst::ICMP_NE;
    }
    if (op == "<") {
        return llvm::CmpInst::ICMP_SLT;
    }
    if (op == ">") {
        return llvm::CmpInst::ICMP_SGT;
    }
    if (op == "<=") {
        return llvm::CmpInst::ICMP_SLE;
    }
    if (op == ">=") {
        return llvm::CmpInst::ICMP_SGE;
    }
    throw std::runtime_error("get_comp_op");
}

llvm::Value *CreateCmp(llvm::CmpInst::Predicate op, llvm::Value *l, llvm::Value *r) {
    return Builder->CreateCmp(op, l, r);
}

llvm::Value *CreateNSWAdd(llvm::Value *l, llvm::Value *r) {
    return Builder->CreateNSWAdd(l, r);
}
llvm::Value *CreateAdd(llvm::Value *l, llvm::Value *r) {
    return Builder->CreateAdd(l, r);
}
llvm::Value *CreateNSWSub(llvm::Value *l, llvm::Value *r) {
    return Builder->CreateNSWSub(l, r);
}
llvm::Value *CreateSub(llvm::Value *l, llvm::Value *r) {
    return Builder->CreateSub(l, r);
}
llvm::Value *CreateNSWMul(llvm::Value *l, llvm::Value *r) {
    return Builder->CreateNSWMul(l, r);
}
llvm::Value *CreateSDiv(llvm::Value *l, llvm::Value *r) {
    return Builder->CreateSDiv(l, r);
}
llvm::Value *CreateSRem(llvm::Value *l, llvm::Value *r) {
    return Builder->CreateSRem(l, r);
}
llvm::Value *CreateXor(llvm::Value *l, llvm::Value *r) {
    return Builder->CreateXor(l, r);
}
llvm::Value *CreateOr(llvm::Value *l, llvm::Value *r) {
    return Builder->CreateOr(l, r);
}
llvm::Value *CreateAnd(llvm::Value *l, llvm::Value *r) {
    return Builder->CreateAnd(l, r);
}
llvm::Value *CreateShl(llvm::Value *l, llvm::Value *r) {
    return Builder->CreateShl(l, r);
}
llvm::Value *CreateAShr(llvm::Value *l, llvm::Value *r) {
    return Builder->CreateAShr(l, r);
}

llvm::Value *CreateTrunc(llvm::Value *val, llvm::Type *type) {
    return Builder->CreateTrunc(val, type);
}

llvm::Constant *CreateGlobalStringPtr(char *str) {
    return Builder->CreateGlobalStringPtr(str);
}

bool isPointerTy(llvm::Type *type) {
    return type->isPointerTy();
}

llvm::UnreachableInst* CreateUnreachable() {
    return Builder->CreateUnreachable();
}

llvm::Constant *getConst(llvm::Type *type, int val) {
    return llvm::ConstantInt::get(type, val);
}

llvm::Constant *getConstF(llvm::Type *type, double val) {
    return llvm::ConstantFP::get(type, val);
}

void CreateMemCpy(llvm::Value *trg, llvm::Value *src, int size) {
    Builder->CreateMemCpy(trg, llvm::MaybeAlign(0), src, llvm::MaybeAlign(0), size);
}

llvm::Value *CreatePtrToInt(llvm::Value *val, llvm::Type *type) {
    return Builder->CreatePtrToInt(val, type);
}

llvm::ConstantInt *makeInt(int val, int bits) {
    auto intType = llvm::IntegerType::get(*ctx, bits);
    return llvm::ConstantInt::get(intType, val);
}

llvm::Type *getInt(int bit) {
    return llvm::IntegerType::get(*ctx, bit);
}

llvm::ArrayType *getArrTy(llvm::Type *elem, int size) {
    return llvm::ArrayType::get(elem, size);
}

llvm::PointerType *getPointerTo(llvm::Type *type) {
    return type->getPointerTo();
}

void setBody(llvm::StructType *st, std::vector<llvm::Type *> *elems) {
    st->setBody(*elems);
}
}