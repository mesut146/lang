#include <llvm/IR/DIBuilder.h>
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/LegacyPassManager.h>
#include "llvm/IR/Module.h"
#include <llvm/IR/Value.h>
#include <llvm/IR/Verifier.h>
#include <llvm/MC/TargetRegistry.h>
#include <llvm/Support/FileSystem.h>
#include <llvm/TargetParser/Host.h>
#include <llvm/Support/TargetSelect.h>
#include <llvm/Target/TargetMachine.h>
#include <llvm/Target/TargetOptions.h>

#include <filesystem>
#include <iostream>
#include <vector>

extern "C" {

std::vector<llvm::Type *> *vector_Type_new() {
  return new std::vector<llvm::Type *>();
}
void vector_Type_push(std::vector<llvm::Type *> *vec, llvm::Type *type) {
  vec->push_back(type);
}
void vector_Type_delete(std::vector<llvm::Type *> *vec) { delete vec; }
void Function_delete(llvm::Function *f) { delete f; }

std::vector<llvm::Value *> *vector_Value_new() {
  return new std::vector<llvm::Value *>();
}
void vector_Value_push(std::vector<llvm::Value *> *vec, llvm::Value *val) {
  vec->push_back(val);
}
void vector_Value_delete(std::vector<llvm::Value *> *vec) { delete vec; }

std::vector<llvm::Metadata *> *vector_Metadata_new() {
  return new std::vector<llvm::Metadata *>();
}
void vector_Metadata_push(std::vector<llvm::Metadata *> *vec,
                          llvm::Metadata *md) {
  vec->push_back(md);
}
void vector_Metadata_delete(std::vector<llvm::Metadata *> *vec) { delete vec; }

std::vector<llvm::Constant *> *vector_Constant_new() {
  return new std::vector<llvm::Constant *>();
}

void vector_Constant_push(std::vector<llvm::Constant *> *vec,
                          llvm::Constant *elem) {
  vec->push_back(elem);
}
void vector_Constant_delete(std::vector<llvm::Constant *> *vec) { delete vec; }

/*void printDefaultTargetAndDetectedCPU() {
  llvm::sys::printDefaultTargetAndDetectedCPU(llvm::outs());
}*/

int getDefaultTargetTriple(char *ptr) {
  std::string res = llvm::sys::getDefaultTargetTriple();
  memcpy(ptr, res.data(), res.length());
  return res.length();
}

//void InitializeAllTargets() { llvm::InitializeAllTargets(); }
//void InitializeAllTargetInfos() { llvm::InitializeAllTargetInfos(); }
//void InitializeAllTargetMCs() { llvm::InitializeAllTargetMCs(); }
//void InitializeAllAsmParsers() { llvm::InitializeAllAsmParsers(); }
//void InitializeAllAsmPrinters() { llvm::InitializeAllAsmPrinters(); }

const llvm::Target *lookupTarget(const char *triple) {
  std::string TargetTriple(triple);
  std::string Error;
  auto Target = llvm::TargetRegistry::lookupTarget(TargetTriple, Error);
  if (!Target) {
    throw std::runtime_error(Error);
  }
  return Target;
}

llvm::TargetMachine *createTargetMachine(const char *triple, int reloc) {
  std::string TargetTriple(triple);
  auto Target = lookupTarget(triple);

  auto CPU = "generic";
  auto Features = "";
  llvm::TargetOptions opt;
  //llvm::Reloc::Model::PIC_
  auto RM = std::optional<llvm::Reloc::Model>((llvm::Reloc::Model)reloc);
  return Target->createTargetMachine(TargetTriple, CPU, Features, opt, RM);
}

bool verifyModule(llvm::Module* mod) { return llvm::verifyModule(*mod, &llvm::outs()); }

char* Module_emit(llvm::Module* mod, char *llvm_file) {
  std::error_code ec;
  llvm::raw_fd_ostream fd(llvm_file, ec);
  mod->print(fd, nullptr);
  if(ec.value() != 0){
    char* buf = new char[ec.message().size() + 1];
    strcpy(buf, ec.message().c_str());
    return buf;
  }
  return nullptr;
}

void emit_object(llvm::Module *mod, const char *name, llvm::TargetMachine *TargetMachine,
                 char *triple) {
  std::string TargetTriple(triple);
  std::string Filename(name);
  if (llvm::verifyModule(*mod, &llvm::outs())) {
    llvm::errs() << "Module verification failed!\n";
    exit(1);
  }
  mod->setDataLayout(TargetMachine->createDataLayout());
  mod->setTargetTriple(TargetTriple);

  std::error_code EC;
  llvm::raw_fd_ostream dest(Filename, EC, llvm::sys::fs::OF_None);

  if (EC) {
    std::cerr << "Could not open file: " << EC.message();
    exit(1);
  }

  llvm::legacy::PassManager pass;
  if (TargetMachine->addPassesToEmitFile(pass, dest, nullptr, llvm::CodeGenFileType::ObjectFile)) {
    std::cerr << "TargetMachine can't emit a file of this type triple=" << triple << "\nfile=" << name;
    std::cerr << std::endl;
    exit(1);
  }
  pass.run(*mod);

  dest.flush();
  dest.close();
}

void destroy_llvm(llvm::TargetMachine *tm) { delete tm; }

void LLVMContext_delete(llvm::LLVMContext* ctx) {
  /*if (mod != nullptr) {
    delete mod;
    mod = nullptr;
  }
  if (Builder != nullptr) {
    delete Builder;
    Builder = nullptr;
  }
  if (dbuilder != nullptr) {
    delete dbuilder;
    dbuilder = nullptr;
  }*/
  delete ctx;
}

llvm::LLVMContext *LLVMContext_new() {
  return new llvm::LLVMContext();
}

llvm::Module *Module_new(char *name, llvm::LLVMContext* ctx, llvm::TargetMachine *TargetMachine, char *triple) {
  auto mod = new llvm::Module(name, *ctx);
  mod->setTargetTriple(triple);
  mod->setDataLayout(TargetMachine->createDataLayout());
  return mod;
}

llvm::IRBuilder<>* IRBuilder_new(llvm::LLVMContext* ctx) {
  return new llvm::IRBuilder<>(*ctx);
}

llvm::DIBuilder* init_dbg(llvm::Module *mod) {
  auto res = new llvm::DIBuilder(*mod);
  mod->addModuleFlag(llvm::Module::Max, "Dwarf Version", 4);
  mod->addModuleFlag(llvm::Module::Warning, "Debug Info Version", 3);
  mod->addModuleFlag(llvm::Module::Min, "PIC Level", 2);
  mod->addModuleFlag(llvm::Module::Max, "PIE Level", 2);
  return res;
}

llvm::DIFile *createFile(llvm::DIBuilder* dbuilder, char *path, char *dir) {
  return dbuilder->createFile(path, dir);
}

int get_dwarf_cpp(){
    return llvm::dwarf::DW_LANG_C_plus_plus;
}
int get_dwarf_cpp20(){
    return llvm::dwarf::DW_LANG_C_plus_plus_20;
}
int get_dwarf_c(){
    return llvm::dwarf::DW_LANG_C;
}
int get_dwarf_c17(){
    return llvm::dwarf::DW_LANG_C17;
}
int get_dwarf_rust(){
    return llvm::dwarf::DW_LANG_Rust;
}
int get_dwarf_zig(){
    return llvm::dwarf::DW_LANG_Zig;
}
int get_dwarf_swift(){
    return llvm::dwarf::DW_LANG_Swift;
}

llvm::DICompileUnit *createCompileUnit(llvm::DIBuilder* dbuilder, int lang, llvm::DIFile *file) {
  return dbuilder->createCompileUnit(
      lang, file, "lang dbg", false, "", 0, "",
      llvm::DICompileUnit::DebugEmissionKind::FullDebug, 0, true, false,
      llvm::DICompileUnit::DebugNameTableKind::None);
}

void replaceGlobalVariables(llvm::LLVMContext* ctx, llvm::DICompileUnit *cu,
                            std::vector<llvm::Metadata *> *vec) {
  llvm::MDTuple *tuple = llvm::MDTuple::get(*ctx, *vec);
  llvm::MDTupleTypedArrayWrapper<llvm::DIGlobalVariableExpression> w(tuple);
  cu->replaceGlobalVariables(w);
}

llvm::DILexicalBlock *createLexicalBlock(llvm::DIBuilder* dbuilder, llvm::DIScope *scope,
                                         llvm::DIFile *file, int line,
                                         int col) {
  return dbuilder->createLexicalBlock(scope, file, line, col);
}

void SetCurrentDebugLocation(llvm::IRBuilder<>* builder, llvm::DIScope *scope, int line, int pos) {
  builder->SetCurrentDebugLocation(
      llvm::DILocation::get(scope->getContext(), line, pos, scope));
}

int make_spflags(bool is_main) {
  auto spflags = llvm::DISubprogram::SPFlagDefinition;
  if (is_main) {
    spflags |= llvm::DISubprogram::SPFlagMainSubprogram;
  }
  return spflags;
}

llvm::DISubroutineType *
createSubroutineType(llvm::DIBuilder* dbuilder, std::vector<llvm::Metadata *> *types) {
  return dbuilder->createSubroutineType(dbuilder->getOrCreateTypeArray(*types));
}

llvm::Function *getFunction(llvm::Module *mod, char *name) { return mod->getFunction(name); }

void setSection(llvm::Function *f, char *sec) { f->setSection(sec); }

llvm::DISubprogram *createFunction(llvm::DIBuilder* dbuilder, llvm::DIScope *scope, char *name,
                                   char *linkage_name, llvm::DIFile *file,
                                   int line, llvm::DISubroutineType *ft,
                                   int spflags) {
  // std::cout << "createFunction " << name << ", " << linkage_name << "\n";
  return dbuilder->createFunction(scope, name, linkage_name, file, line, ft,
                                  line, llvm::DINode::FlagPrototyped,
                                  (llvm::DISubprogram::DISPFlags)spflags);
}

void setSubprogram(llvm::Function *f, llvm::DISubprogram *sp) {
  f->setSubprogram(sp);
}

llvm::DILocalVariable *createParameterVariable(llvm::DIBuilder* dbuilder, llvm::DIScope *scope, char *name,
                                               int idx, llvm::DIFile *file,
                                               int line, llvm::DIType *type,
                                               bool preserve, bool is_self) {
                                                auto flags = llvm::DINode::DIFlags::FlagZero;
                                                if(is_self){
                                                   flags |= llvm::DINode::DIFlags::FlagArtificial;
                                                   flags |= llvm::DINode::DIFlags::FlagObjectPointer;
                                                }
  return dbuilder->createParameterVariable(scope, name, idx, file, line, type,
                                           preserve, flags);
}

llvm::DILocalVariable *createAutoVariable(llvm::DIBuilder* dbuilder, llvm::DIScope *scope, char *name,
                                          llvm::DIFile *file, int line,
                                          llvm::DIType *ty) {
  return dbuilder->createAutoVariable(scope, name, file, line, ty);
}

llvm::DIExpression *createExpression(llvm::DIBuilder* dbuilder) { return dbuilder->createExpression(); }

llvm::DILocation *DILocation_get(llvm::DIScope *scope, int line, int pos) {
  return llvm::DILocation::get(scope->getContext(), line, pos, scope);
}

void insertDeclare(llvm::DIBuilder* dbuilder, llvm::Value *value, llvm::DILocalVariable *var_info,
                   llvm::DIExpression *expr, llvm::DILocation *loc,
                   llvm::BasicBlock *bb) {
  dbuilder->insertDeclare(value, var_info, expr, loc, bb);
}

llvm::DICompositeType *createStructType(llvm::DIBuilder* dbuilder, llvm::LLVMContext* ctx, llvm::DIScope *scope, char *name,
                                        llvm::DIFile *file, int line, int size,
                                        std::vector<llvm::Metadata *> *elems) {
  auto arr = llvm::DINodeArray(llvm::MDTuple::get(*ctx, *elems));
  auto align = 0;
  return dbuilder->createStructType(scope, name, file, line, size, align,
                                    llvm::DINode::FlagZero, nullptr, arr);
}

llvm::DICompositeType *createStructType_ident(llvm::DIBuilder* dbuilder, llvm::LLVMContext* ctx, llvm::DIScope *scope, char *name,
  llvm::DIFile *file, int line, int size,
  std::vector<llvm::Metadata *> *elems, char* ident) {
  auto arr = llvm::DINodeArray(llvm::MDTuple::get(*ctx, *elems));
  auto align = 0;
  auto RunTimeLang = 0;
  llvm::DIType *VTableHolder = nullptr;
  return dbuilder->createStructType(scope, name, file, line, size, align,
  llvm::DINode::FlagZero, nullptr, arr, RunTimeLang, VTableHolder, ident);
}

const llvm::StructLayout *getStructLayout(llvm::Module *mod, llvm::StructType *st) {
  return mod->getDataLayout().getStructLayout(st);
}

uint64_t DataLayout_getTypeSizeInBits(llvm::Module *mod, llvm::Type *ty) {
  return mod->getDataLayout().getTypeSizeInBits(ty);
}

int64_t getElementOffsetInBits(llvm::StructLayout *sl, int idx) {
  return sl->getElementOffsetInBits(idx);
}

llvm::DIType *get_di_null() { return nullptr; }

int64_t DIType_getSizeInBits(llvm::DIType *ty) { return ty->getSizeInBits(); }

void replaceElements(llvm::LLVMContext* ctx, llvm::DICompositeType *st,
                     std::vector<llvm::Metadata *> *elems) {
  auto arr = llvm::DINodeArray(llvm::MDTuple::get(*ctx, *elems));
  st->replaceElements(arr);
}

llvm::DICompositeType *createVariantPart(llvm::DIBuilder* dbuilder, llvm::LLVMContext* ctx, llvm::DIScope *scope, char *name,
                                         llvm::DIFile *file, int line,
                                         int64_t size,
                                         llvm::DIDerivedType *disc,
                                         std::vector<llvm::Metadata *> *elems) {
  auto arr = llvm::DINodeArray(llvm::MDTuple::get(*ctx, *elems));
  return dbuilder->createVariantPart(scope, name, file, line, size, 0,
                                     llvm::DINode::FlagZero, disc, arr);
}

llvm::DIDerivedType *createVariantMemberType(llvm::DIBuilder* dbuilder, llvm::LLVMContext* ctx, llvm::DIScope *scope, char *name,
                                             llvm::DIFile *file, int line,
                                             int64_t size, int64_t off, int idx,
                                             llvm::DIType *ty) {
  auto intType = llvm::IntegerType::get(*ctx, 32);
  auto disc = llvm::ConstantInt::getSigned(intType, idx);
  return dbuilder->createVariantMemberType(
      scope, name, file, line, size, 0, off, disc, llvm::DINode::FlagZero, ty);
}

llvm::DIType *createBasicType(llvm::DIBuilder* dbuilder, char *name, uint64_t size, int encoding) {
  return dbuilder->createBasicType(name, size, encoding);
}

int DW_ATE_boolean() { return llvm::dwarf::DW_ATE_boolean; }

int DW_ATE_signed() { return llvm::dwarf::DW_ATE_signed; }

int DW_ATE_unsigned() { return llvm::dwarf::DW_ATE_unsigned; }

int DW_ATE_float() { return llvm::dwarf::DW_ATE_float; }

llvm::DIType *createPointerType(llvm::DIBuilder* dbuilder, llvm::DIType *elem, int64_t size) {
  return dbuilder->createPointerType(elem, size);
}

llvm::Metadata *getOrCreateSubrange(llvm::DIBuilder* dbuilder, int64_t lo, int64_t count) {
  return dbuilder->getOrCreateSubrange(lo, count);
}

llvm::DIType *createArrayType(llvm::DIBuilder* dbuilder, llvm::LLVMContext* ctx, int64_t size, llvm::DIType *ty,
                              std::vector<llvm::Metadata *> *elems) {
  llvm::DINodeArray subs(llvm::MDTuple::get(*ctx, *elems));
  return dbuilder->createArrayType(size, 0, ty, subs);
}

uint32_t make_di_flags(bool artificial) {
  if (artificial) {
    return llvm::DINode::FlagArtificial;
  }
  return llvm::DINode::FlagZero;
}

llvm::DIDerivedType *createMemberType(llvm::DIBuilder* dbuilder, llvm::DIScope *scope, char *name,
                                      llvm::DIFile *file, int line,
                                      int64_t size, int64_t off, uint32_t flags,
                                      llvm::DIType *ty) {
  int align = 0;                                      
  return dbuilder->createMemberType(scope, name, file, line, size, align, off,
                                    (llvm::DINode::DIFlags)flags, ty);
}

llvm::DIScope *get_null_scope() { return nullptr; }

llvm::DIType *createObjectPointerType(llvm::DIType *ty) {
  #if LLVM20
  return llvm::DIBuilder::createObjectPointerType(ty, true);
  #else
  return llvm::DIBuilder::createObjectPointerType(ty);
  #endif
}

llvm::DIGlobalVariableExpression *
createGlobalVariableExpression(llvm::DIBuilder* dbuilder, llvm::DIScope *scope, char *name, char *lname,
                               llvm::DIFile *file, int line,
                               llvm::DIType *type) {
  return dbuilder->createGlobalVariableExpression(scope, name, lname, file,
                                                  line, type, false, true);
}

void addDebugInfo(llvm::GlobalVariable *gv,
                  llvm::DIGlobalVariableExpression *gve) {
  gv->addDebugInfo(gve);
}

void finalizeSubprogram(llvm::DIBuilder* dbuilder, llvm::DISubprogram *sp) {
  dbuilder->finalizeSubprogram(sp);
}

void setCallingConv(llvm::Function *f) {
  f->setCallingConv(llvm::CallingConv::C);
}

int ext() { return llvm::Function::ExternalLinkage; }
int odr() { return llvm::Function::LinkOnceODRLinkage; }
int internal() { return llvm::Function::InternalLinkage; }
/*llvm::GlobalValue::LinkageTypes ext() {
    return llvm::Function::ExternalLinkage;
}
llvm::GlobalValue::LinkageTypes odr() {
    return llvm::Function::LinkOnceODRLinkage;
}*/

llvm::Type *getVoidTy(llvm::IRBuilder<>* builder) { return builder->getVoidTy(); }

llvm::FunctionType *make_ft(llvm::Type *retType, llvm::Type** argTypes, int len, bool vararg) {
  llvm::ArrayRef<llvm::Type*> ref(argTypes, len);
  return llvm::FunctionType::get(retType, ref, vararg);
}

llvm::Function *make_func(llvm::FunctionType *ft, int linkage, char *name, llvm::Module* mod) {
  return llvm::Function::Create(ft, (llvm::GlobalValue::LinkageTypes)linkage,
                                name, *mod);
}

llvm::Argument *Function_get_arg(llvm::Function *f, int i) { return f->getArg(i); }

void Argument_setname(llvm::Argument *arg, char *name) { arg->setName(name); }

void Argument_setsret(llvm::LLVMContext* ctx, llvm::Argument *arg, llvm::Type *ty) {
  auto attr = llvm::Attribute::get(*ctx, llvm::Attribute::StructRet, ty);
  arg->addAttr(attr);
}

llvm::Attribute::AttrKind get_sret() { return llvm::Attribute::StructRet; }

void Function_print(llvm::Function *f) { f->print(llvm::errs()); }

llvm::StructType *make_struct_ty(llvm::LLVMContext* ctx, char *name, llvm::Type** elems, int len) {
  return llvm::StructType::create(*ctx, *elems, name);
}
llvm::StructType *make_struct_ty2(llvm::LLVMContext* ctx, char *name) {
  return llvm::StructType::create(*ctx, name);
}
llvm::StructType *make_struct_ty_noname(llvm::LLVMContext* ctx, std::vector<llvm::Type *> *elems) {
  return llvm::StructType::create(*ctx, *elems);
}

int getSizeInBits(llvm::Module *mod, llvm::StructType *st) {
  int res = mod->getDataLayout().getStructLayout(st)->getSizeInBits();
  return res;
}

int StructType_getNumElements(llvm::StructType *st) {
  return st->getNumElements();
}

llvm::ArrayType *ArrayType_get(llvm::Type *elem, int size) {
  return llvm::ArrayType::get(elem, size);
}

llvm::Type *getPtr(llvm::LLVMContext* ctx) { return llvm::PointerType::getUnqual(*ctx); }

int GlobalValue_ext() { return llvm::GlobalValue::ExternalLinkage; }
int GlobalValue_appending() { return llvm::GlobalValue::AppendingLinkage; }

llvm::GlobalVariable *make_global(llvm::Module* mod, llvm::Type *ty, llvm::Constant *init, int linkage, const char *name) {
  auto res = new llvm::GlobalVariable(
      *mod, ty, false, (llvm::GlobalValue::LinkageTypes)linkage, init, name);
  return res;
}

llvm::Constant *ConstantStruct_get(llvm::StructType *ty) {
  return llvm::ConstantStruct::get(ty);
}

llvm::Constant *ConstantStruct_get_elems(llvm::StructType *ty, llvm::Constant** elems, int len) {
  llvm::ArrayRef<llvm::Constant*> ref(elems, len);
  return llvm::ConstantStruct::get(ty, ref);
}

llvm::Constant *ConstantStruct_getAnon(llvm::Constant** elems, int len) {
  llvm::ArrayRef<llvm::Constant*> ref(elems, len);
  return llvm::ConstantStruct::getAnon(ref);
}

llvm::Constant *ConstantArray_get(llvm::ArrayType *ty, llvm::Constant** elems, int len) {
  llvm::ArrayRef<llvm::Constant*> ref(elems, len);
  return llvm::ConstantArray::get(ty, ref);
}

llvm::Value *CreateAlloca(llvm::IRBuilder<>* builder, llvm::Type *ty) { return builder->CreateAlloca(ty); }

void Value_setName(llvm::Value *val, char *name) { val->setName(name); }

llvm::Value *CreateFPCast(llvm::IRBuilder<>* builder, llvm::Value *val, llvm::Type *trg_type) {
  return builder->CreateFPCast(val, trg_type);
}
llvm::Value *CreateSIToFP(llvm::IRBuilder<>* builder, llvm::Value *val, llvm::Type *trg_type) {
  return builder->CreateSIToFP(val, trg_type);
}
llvm::Value *CreateUIToFP(llvm::IRBuilder<>* builder, llvm::Value *val, llvm::Type *trg_type) {
  return builder->CreateUIToFP(val, trg_type);
}
llvm::Value *CreateFPToSI(llvm::IRBuilder<>* builder, llvm::Value *val, llvm::Type *trg_type) {
  return builder->CreateFPToSI(val, trg_type);
}
llvm::Value *CreateFPToUI(llvm::IRBuilder<>* builder, llvm::Value *val, llvm::Type *trg_type) {
  return builder->CreateFPToUI(val, trg_type);
}

void CreateStore(llvm::IRBuilder<>* builder, llvm::Value *val, llvm::Value *ptr) {
  builder->CreateStore(val, ptr);
}

llvm::BasicBlock *create_bb(llvm::LLVMContext* ctx, const char *name, llvm::Function *func) {
  return llvm::BasicBlock::Create(*ctx, name, func);
}

void SetInsertPoint(llvm::IRBuilder<>* builder, llvm::BasicBlock *bb) { builder->SetInsertPoint(bb); }

llvm::BasicBlock *GetInsertBlock(llvm::IRBuilder<>* builder) { return builder->GetInsertBlock(); }

void func_insert(llvm::Function *f, llvm::BasicBlock *bb) {
  f->insert(f->end(), bb);
}

llvm::SwitchInst *CreateSwitch(llvm::IRBuilder<>* builder, llvm::Value *cond, llvm::BasicBlock *default_bb,
                               int num_cases) {
  return builder->CreateSwitch(cond, default_bb, num_cases);
}

void SwitchInst_addCase(llvm::SwitchInst* node, llvm::ConstantInt *OnVal, llvm::BasicBlock *Dest) {
  node->addCase(OnVal, Dest);
}

llvm::Value *CreateCall(llvm::IRBuilder<>* builder, llvm::Function *f, llvm::Value** args, int len) {
  llvm::ArrayRef ref(args, len);
  return builder->CreateCall(f, ref);
}

llvm::Value *CreateCall_ft(llvm::IRBuilder<>* builder, llvm::FunctionType *ft, llvm::Value* val, llvm::Value** args, int len) {
  llvm::ArrayRef ref(args, len);
  return builder->CreateCall(ft, val, ref);
}

void CreateRet(llvm::IRBuilder<>* builder, llvm::Value *val) { builder->CreateRet(val); }

void CreateRetVoid(llvm::IRBuilder<>* builder) { builder->CreateRetVoid(); }

bool verifyFunction(llvm::Function *func) {
  return llvm::verifyFunction(*func, &llvm::outs());
}

void CreateCondBr(llvm::IRBuilder<>* builder, llvm::Value *cond, llvm::BasicBlock *then,
                  llvm::BasicBlock *next) {
  builder->CreateCondBr(cond, then, next);
}

int getPrimitiveSizeInBits(llvm::Type *type) {
  return type->getPrimitiveSizeInBits();
}

llvm::Type *Value_getType(llvm::Value *val) { return val->getType(); }

void CreateBr(llvm::IRBuilder<>* builder, llvm::BasicBlock *bb) { builder->CreateBr(bb); }

llvm::PHINode *CreatePHI(llvm::IRBuilder<>* builder, llvm::Type *type, int cnt) {
  return builder->CreatePHI(type, cnt);
}

void phi_addIncoming(llvm::PHINode *phi, llvm::Value *val,
                     llvm::BasicBlock *bb) {
  phi->addIncoming(val, bb);
}

int get_comp_op(char *ops) {
  std::string op(ops);
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

int get_comp_op_float(char *ops) {
  std::string op(ops);
  if (op == "==") {
    return llvm::CmpInst::FCMP_OEQ;
  }
  if (op == "!=") {
    return llvm::CmpInst::FCMP_ONE;
  }
  if (op == "<") {
    return llvm::CmpInst::FCMP_OLT;
  }
  if (op == ">") {
    return llvm::CmpInst::FCMP_OGT;
  }
  if (op == "<=") {
    return llvm::CmpInst::FCMP_OLE;
  }
  if (op == ">=") {
    return llvm::CmpInst::FCMP_OGE;
  }
  throw std::runtime_error("get_comp_op");
}

llvm::Value *CreateCmp(llvm::IRBuilder<>* builder, int op, llvm::Value *l, llvm::Value *r) {
  return builder->CreateCmp((llvm::CmpInst::Predicate)op, l, r);
}

llvm::Value *CreateNSWAdd(llvm::IRBuilder<>* builder, llvm::Value *l, llvm::Value *r) {
  return builder->CreateNSWAdd(l, r);
}
llvm::Value *CreateAdd(llvm::IRBuilder<>* builder, llvm::Value *l, llvm::Value *r) {
  return builder->CreateAdd(l, r);
}
llvm::Value *CreateFAdd(llvm::IRBuilder<>* builder, llvm::Value *l, llvm::Value *r) {
  return builder->CreateFAdd(l, r);
}
llvm::Value *CreateNSWSub(llvm::IRBuilder<>* builder, llvm::Value *l, llvm::Value *r) {
  return builder->CreateNSWSub(l, r);
}
llvm::Value *CreateSub(llvm::IRBuilder<>* builder, llvm::Value *l, llvm::Value *r) {
  return builder->CreateSub(l, r);
}
llvm::Value *CreateFSub(llvm::IRBuilder<>* builder, llvm::Value *l, llvm::Value *r) {
  return builder->CreateFSub(l, r);
}
llvm::Value *CreateNSWMul(llvm::IRBuilder<>* builder, llvm::Value *l, llvm::Value *r) {
  return builder->CreateNSWMul(l, r);
}
llvm::Value *CreateFMul(llvm::IRBuilder<>* builder, llvm::Value *l, llvm::Value *r) {
  return builder->CreateFMul(l, r);
}
llvm::Value *CreateSDiv(llvm::IRBuilder<>* builder, llvm::Value *l, llvm::Value *r) {
  return builder->CreateSDiv(l, r);
}
llvm::Value *CreateFDiv(llvm::IRBuilder<>* builder, llvm::Value *l, llvm::Value *r) {
  return builder->CreateFDiv(l, r);
}
llvm::Value *CreateSRem(llvm::IRBuilder<>* builder, llvm::Value *l, llvm::Value *r) {
  return builder->CreateSRem(l, r);
}
llvm::Value *CreateFRem(llvm::IRBuilder<>* builder, llvm::Value *l, llvm::Value *r) {
  return builder->CreateFRem(l, r);
}
llvm::Value *CreateXor(llvm::IRBuilder<>* builder, llvm::Value *l, llvm::Value *r) {
  return builder->CreateXor(l, r);
}
llvm::Value *CreateOr(llvm::IRBuilder<>* builder, llvm::Value *l, llvm::Value *r) {
  return builder->CreateOr(l, r);
}
llvm::Value *CreateAnd(llvm::IRBuilder<>* builder, llvm::Value *l, llvm::Value *r) {
  return builder->CreateAnd(l, r);
}
llvm::Value *CreateShl(llvm::IRBuilder<>* builder, llvm::Value *l, llvm::Value *r) {
  return builder->CreateShl(l, r);
}
llvm::Value *CreateAShr(llvm::IRBuilder<>* builder, llvm::Value *l, llvm::Value *r) {
  return builder->CreateAShr(l, r);
}
llvm::Value *CreateTrunc(llvm::IRBuilder<>* builder, llvm::Value *val, llvm::Type *type) {
  return builder->CreateTrunc(val, type);
}
llvm::Value *CreateNeg(llvm::IRBuilder<>* builder, llvm::Value *val) { return builder->CreateNeg(val); }

llvm::Value *CreateFNeg(llvm::IRBuilder<>* builder, llvm::Value *val) { return builder->CreateFNeg(val); }

llvm::Constant *CreateGlobalStringPtr(llvm::IRBuilder<>* builder, char *str) {
  return builder->CreateGlobalStringPtr(str);
}

llvm::GlobalVariable* CreateGlobalString(llvm::IRBuilder<>* builder, char* str){
  return builder->CreateGlobalString(str);
}

bool isPointerTy(llvm::Type *type) { return type->isPointerTy(); }

bool Value_isPointerTy(llvm::Value *val) {
  return val->getType()->isPointerTy();
}

llvm::UnreachableInst *CreateUnreachable(llvm::IRBuilder<>* builder) {
  return builder->CreateUnreachable();
}

llvm::Constant *getConst(llvm::Type *type, int val) {
  return llvm::ConstantInt::get(type, val);
}

llvm::Constant *getConstF(llvm::Type *type, double val) {
  return llvm::ConstantFP::get(type, val);
}

void CreateMemCpy(llvm::IRBuilder<>* builder, llvm::Value *trg, llvm::Value *src, uint64_t size) {
  builder->CreateMemCpy(trg, llvm::MaybeAlign(0), src, llvm::MaybeAlign(0),
                        size);
}

llvm::Value *CreatePtrToInt(llvm::IRBuilder<>* builder, llvm::Value *val, llvm::Type *type) {
  return builder->CreatePtrToInt(val, type);
}

llvm::ConstantInt *makeInt(llvm::LLVMContext* ctx, int64_t val, int bits) {
  auto intType = llvm::IntegerType::get(*ctx, bits);
  return llvm::ConstantInt::getSigned(intType, val);
}

llvm::Type *intTy(llvm::LLVMContext* ctx, int bit) { return llvm::IntegerType::get(*ctx, bit); }

llvm::Type *getFloatTy(llvm::LLVMContext* ctx) { return llvm::Type::getFloatTy(*ctx); }

llvm::Type *getDoubleTy(llvm::LLVMContext* ctx) { return llvm::Type::getDoubleTy(*ctx); }

llvm::Constant *makeFloat(llvm::LLVMContext* ctx, float val) {
  return llvm::ConstantFP::get(getFloatTy(ctx), val);
}

llvm::Constant *makeDouble(llvm::LLVMContext* ctx, double val) {
  return llvm::ConstantFP::get(getDoubleTy(ctx), val);
}

llvm::ArrayType *getArrTy(llvm::Type *elem, int size) {
  return llvm::ArrayType::get(elem, size);
}

llvm::PointerType *getPointerTo(llvm::Type *type) {
  int adds = 0;
  return llvm::PointerType::get(type, adds);
}

llvm::Value *ConstantPointerNull_get(llvm::PointerType *ty) {
  return llvm::ConstantPointerNull::get(ty);
}

bool isVoidTy(llvm::Type *type) { return type->isVoidTy(); }

void setBody(llvm::StructType *st, std::vector<llvm::Type *> *elems) {
  st->setBody(*elems);
}

//void Value_dump(llvm::Value *v) { v->dump(); }

//void Type_dump(llvm::Type *v) { v->dump(); }

llvm::Value *CreateSExt(llvm::IRBuilder<>* builder, llvm::Value *val, llvm::Type *type) {
  return builder->CreateSExt(val, type);
}
llvm::Value *CreateZExt(llvm::IRBuilder<>* builder, llvm::Value *val, llvm::Type *type) {
  return builder->CreateZExt(val, type);
}
llvm::Value *CreateFPExt(llvm::IRBuilder<>* builder, llvm::Value *val, llvm::Type *type) {
  return builder->CreateFPExt(val, type);
}
llvm::Value *CreateFPTrunc(llvm::IRBuilder<>* builder, llvm::Value *val, llvm::Type *type) {
  return builder->CreateFPTrunc(val, type);
}

llvm::Value *CreateStructGEP(llvm::IRBuilder<>* builder, llvm::Type *type, llvm::Value *ptr, int idx) {
  return builder->CreateStructGEP(type, ptr, idx);
}
llvm::Value *CreateInBoundsGEP(llvm::IRBuilder<>* builder, llvm::Type *type, llvm::Value *ptr,
                               llvm::Value** idx, int len) {
  llvm::ArrayRef<llvm::Value*> arr(idx, len);       
  return builder->CreateInBoundsGEP(type, ptr, arr);
}

llvm::Value *CreateGEP(llvm::IRBuilder<>* builder, llvm::Type *type, llvm::Value *ptr, llvm::Value** idx, int len) {
  llvm::ArrayRef<llvm::Value*> arr(idx, len);  
  return builder->CreateGEP(type, ptr, arr);
}

llvm::Value *CreateLoad(llvm::IRBuilder<>* builder, llvm::Type *type, llvm::Value *val) {
  auto val_type = val->getType();
  if (val_type->isVoidTy()) {
    llvm::errs() << "Error: Cannot load from void type\n";
    exit(1);
  }
  return builder->CreateLoad(type, val);
}

llvm::Value *getTrue(llvm::IRBuilder<>* builder) { return builder->getTrue(); }

llvm::Value *getFalse(llvm::IRBuilder<>* builder) { return builder->getFalse(); }

int64_t get_last_write_time(const char *path) {
  auto time = std::filesystem::last_write_time(path).time_since_epoch() /
              std::chrono::milliseconds(1);
  return time;
}

/*void set_as_executable(const char *path) {
  std::filesystem::permissions(path,
                               std::filesystem::perms::owner_all |
                                   std::filesystem::perms::group_read |
                                   std::filesystem::perms::others_read,
                               std::filesystem::perm_options::add);
}*/
}
