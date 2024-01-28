#include "bridge.h"
#include <iostream>


static llvm::IRBuilder<>* Builder = nullptr;
static llvm::LLVMContext* ctx = nullptr;
static llvm::Module* mod = nullptr;

extern "C" {
    
std::vector<llvm::Type*>* make_vec(){
    return new std::vector<llvm::Type*>();
}

void push(std::vector<llvm::Type*>* vec, llvm::Type* type){
    vec->push_back(type);
}

void setBuilder(llvm::IRBuilder<>* b){
    Builder = b;
}
void setModule(llvm::Module* m){
    mod = m;
}
void setCtx(llvm::LLVMContext* c){
    ctx = c;
}

int getDefaultTargetTriple(char *ptr) {
    std::string res = llvm::sys::getDefaultTargetTriple();
    memcpy(ptr, res.data(), res.length());
    return res.length();
}

void InitializeAllTargetInfos()
{
	llvm::InitializeAllTargetInfos();
}
void InitializeAllTargets(){
	llvm::InitializeAllTargets();
}
void InitializeAllTargetMCs(){
}
void InitializeAllAsmParsers(){
    llvm::InitializeAllAsmParsers();
}
void InitializeAllAsmPrinters(){
    llvm::InitializeAllAsmPrinters();
}

const void* lookupTarget(const char* triple)
{
	std::string TargetTriple(triple);
	std::string Error;
	auto Target = llvm::TargetRegistry::lookupTarget(TargetTriple, Error);
	if (!Target) {
        throw std::runtime_error(Error);
    }
    return Target;
}

void* createTargetMachine(const char* triple){
    std::string TargetTriple(triple);
    std::string Error;
	auto Target = llvm::TargetRegistry::lookupTarget(TargetTriple, Error);
	if (!Target) {
        throw std::runtime_error(Error);
    }
    
    auto CPU = "generic";
    auto Features = "";
    llvm::TargetOptions opt;
    auto RM = std::optional<llvm::Reloc::Model>(llvm::Reloc::Model::PIC_);
    return  Target->createTargetMachine(TargetTriple, CPU, Features, opt, RM);
}

void emit(const char* name, void* target, char* triple, void* module){
    std::string TargetTriple(triple);
    std::string Filename(name);
    auto TargetMachine=(llvm::TargetMachine*)target;
    auto mod = (llvm::Module*)module;
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

llvm::LLVMContext* make_ctx(){
    return new llvm::LLVMContext();
}

llvm::Module* make_module(char* name, void* ctx, void* target, char* triple){
    auto TargetMachine=(llvm::TargetMachine*)target;
    std::string TargetTriple(triple);
    auto mod= new llvm::Module(name, *(llvm::LLVMContext*)ctx);
    mod->setDataLayout(TargetMachine->createDataLayout());
    mod->setTargetTriple(TargetTriple);
    return mod;
}

llvm::IRBuilder<>* make_builder(){
    return new llvm::IRBuilder<>(*ctx);
}

void emit_llvm(char* llvm_file){
    std::error_code ec;
    llvm::raw_fd_ostream fd(llvm_file, ec);
    mod->print(fd, nullptr);
}

llvm::Type* getVoidTy(){
    return Builder->getVoidTy();
}

llvm::FunctionType* make_ft(llvm::Type* retType, std::vector<llvm::Type*> *argTypes, bool vararg){
    return llvm::FunctionType::get(retType, *argTypes, vararg);
}

llvm::Function* make_func(llvm::FunctionType* ft, llvm::GlobalValue::LinkageTypes* linkage, char* name, llvm::Module* mod){
    return llvm::Function::Create(ft, *linkage, name, *mod);
}

auto setCallingConv(llvm::Function* f){
    f->setCallingConv(llvm::CallingConv::C);
}

auto ext(){
    return llvm::Function::ExternalLinkage;
}

auto odr(){
    return llvm::Function::LinkOnceODRLinkage;
}

llvm::Argument* get_arg(llvm::Function* f, int i){
    return f->getArg(i);
}

void arg_setName(llvm::Argument* arg, char* name){
    arg->setName(name);
}

void arg_attr(llvm::Argument* arg, llvm::Attribute::AttrKind* attr){
    arg->addAttr(*attr);
}

llvm::Attribute::AttrKind get_sret(){
    return llvm::Attribute::StructRet;
}

auto make_struct_ty(char* name){
    return llvm::StructType::create(*ctx, name);
}
auto make_struct_ty2(char* name, std::vector<llvm::Type*> *elems){
    return llvm::StructType::create(*ctx, *elems, name);
}

auto getSizeInBits(llvm::StructType* st ){
    return mod->getDataLayout().getStructLayout(st)->getSizeInBits();
}

auto get_arrty(llvm::Type* elem, int size){
    return llvm::ArrayType::get(elem, size);
}

llvm::Type *getPtr() {
    return llvm::PointerType::getUnqual(*ctx);
}

auto make_stdout(){
    auto res = new llvm::GlobalVariable(*mod, getPtr(), false, llvm::GlobalValue::ExternalLinkage, nullptr, "stdout");
    res->addAttribute("global");
    return res;
}

auto Builder_alloca(llvm::Type* ty){
    return Builder->CreateAlloca(ty);
}

auto Value_setName(llvm::Value* val, char* name){
    val->setName(name);
}

void store(llvm::Value* val, llvm::Value* ptr){
    Builder->CreateStore(val, ptr);
}

auto create_bb2(llvm::Function* func){
    return llvm::BasicBlock::Create(*ctx, "", func);
}

auto create_bb(){
    return llvm::BasicBlock::Create(*ctx, "");
}

void set_insert(llvm::BasicBlock* bb){
    Builder->SetInsertPoint(bb);
}

llvm::BasicBlock* get_insert(){
    return Builder->GetInsertBlock();
}

void call(llvm:: Function* f, std::vector<llvm::Value*> *args){
  Builder->CreateCall(f, *args);
}

void ret(llvm:: Value* val){
    Builder->CreateRet(val);
}

void ret_void(){
    Builder->CreateRetVoid();
}

void verify(llvm:: Function* func){
    llvm::verifyFunction(*func, &llvm::outs());
}

auto CreateCondBr(llvm::Value* cond, llvm::BasicBlock* then, llvm::BasicBlock* next){
    Builder->CreateCondBr(cond, then, next);
}

auto CreateZExt(llvm::Value* val, llvm::Type* type){
    Builder->CreateZExt(val, type);
}

auto getPrimitiveSizeInBits(llvm::Type* type){
    return type->getPrimitiveSizeInBits();
}

auto Value_getType(llvm::Value* val){
    return val->getType();
}

void CreateBr(llvm::BasicBlock* bb){
    Builder->CreateBr(bb);
}

auto CreatePHI(llvm::Type* type){
    return Builder->CreatePHI(type, 2);
}

void addIncoming(llvm::PHINode* phi, llvm::Value* val, llvm::BasicBlock* bb){
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

auto CreateCmp(llvm::CmpInst::Predicate op, llvm::Value* l, llvm::Value* r){
    return Builder->CreateCmp(op,l,r);
}

auto CreateNSWAdd(llvm::Value* l, llvm::Value* r){
    return Builder->CreateNSWAdd(l, r);
}
auto CreateAdd(llvm::Value* l, llvm::Value* r){
    return Builder->CreateAdd(l, r);
}
auto CreateNSWSub(llvm::Value* l, llvm::Value* r){
    return Builder->CreateNSWSub(l, r);
}
auto CreateSub(llvm::Value* l, llvm::Value* r){
    return Builder->CreateSub(l, r);
}
auto CreateNSWMul(llvm::Value* l, llvm::Value* r){
    return Builder->CreateNSWMul(l, r);
}
auto CreateSDiv(llvm::Value* l, llvm::Value* r){
    return Builder->CreateSDiv(l, r);
}
auto CreateSRem(llvm::Value* l, llvm::Value* r){
    return Builder->CreateSRem(l, r);
}
auto CreateXor(llvm::Value* l, llvm::Value* r){
    return Builder->CreateXor(l, r);
}
auto CreateOr(llvm::Value* l, llvm::Value* r){
    return Builder->CreateOr(l, r);
}
auto CreateAnd(llvm::Value* l, llvm::Value* r){
    return Builder->CreateAnd(l, r);
}
auto CreateShl(llvm::Value* l, llvm::Value* r){
    return Builder->CreateShl(l, r);
}
auto CreateAShr(llvm::Value* l, llvm::Value* r){
    return Builder->CreateAShr(l, r);
}

auto CreateTrunc(llvm::Value* val, llvm::Type* type){
    return Builder->CreateTrunc(val, type);
}

auto CreateGlobalStringPtr(char* str){
    return Builder->CreateGlobalStringPtr(str);
}

auto isPointerTy(llvm::Type* type){
    return type->isPointerTy();
}

auto CreateUnreachable(){
    return Builder->CreateUnreachable();
}

auto getConst(llvm::Type* type, int val){
    return llvm::ConstantInt::get(type, val);
}

auto getConstF(llvm::Type* type, double val){
    return llvm::ConstantFP::get(type, val);
}

auto CreateMemCpy(llvm::Value* trg, llvm::Value* src, int size){
    Builder->CreateMemCpy(trg, llvm::MaybeAlign(0), src, llvm::MaybeAlign(0), size);
}

auto CreatePtrToInt(llvm::Value* val, llvm::Type* type){
    return Builder->CreatePtrToInt(val, type);
}

llvm::ConstantInt *makeInt(int val, int bits) {
    auto intType = llvm::IntegerType::get(*ctx, bits);
    return llvm::ConstantInt::get(intType, val);
}

llvm::Type *getInt(int bit) {
    return llvm::IntegerType::get(*ctx, bit);
}

auto getArrTy(llvm::Type* elem,int size){
    return llvm::ArrayType::get(elem, size);
}

auto getPointerTo(llvm::Type* type){
    return type->getPointerTo();
}

auto setBody(llvm::StructType *st, std::vector<llvm::Type*>* elems){
    st->setBody(*elems);
}



}