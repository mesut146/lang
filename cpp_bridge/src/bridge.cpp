#include "llvm/Transforms/IPO/PassManagerBuilder.h"
#include <llvm/IR/Attributes.h>
#include <llvm/IR/Constants.h>
#include <llvm/IR/DIBuilder.h>
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/LegacyPassManager.h>
#include <llvm/IR/Value.h>
#include <llvm/IR/Verifier.h>
#include <llvm/MC/TargetRegistry.h>
#include <llvm/Support/FileSystem.h>
#include <llvm/Support/Host.h>
#include <llvm/Support/TargetSelect.h>
#include <llvm/Target/TargetMachine.h>
#include <llvm/Target/TargetOptions.h>

#include <filesystem>
#include <iostream>
#include <vector>

static llvm::IRBuilder<> *Builder = nullptr;
static llvm::LLVMContext *ctx = nullptr;
static llvm::Module *mod = nullptr;
static llvm::DIBuilder *DBuilder = nullptr;

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

void setBuilder(llvm::IRBuilder<> *b) { Builder = b; }
void setModule(llvm::Module *m) { mod = m; }
void setCtx(llvm::LLVMContext *c) { ctx = c; }

void printDefaultTargetAndDetectedCPU() {
  llvm::sys::printDefaultTargetAndDetectedCPU(llvm::outs());
}

int getDefaultTargetTriple(char *ptr) {
  std::string res = llvm::sys::getDefaultTargetTriple();
  memcpy(ptr, res.data(), res.length());
  return res.length();
}

void InitializeAllTargetInfos() { llvm::InitializeAllTargetInfos(); }
void InitializeAllTargets() { llvm::InitializeAllTargets(); }
void InitializeAllTargetMCs() { llvm::InitializeAllTargetMCs(); }
void InitializeAllAsmParsers() { llvm::InitializeAllAsmParsers(); }
void InitializeAllAsmPrinters() { llvm::InitializeAllAsmPrinters(); }

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

bool verifyModule() { return llvm::verifyModule(*mod, &llvm::outs()); }

void emit_object(const char *name, llvm::TargetMachine *TargetMachine,
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
  if (TargetMachine->addPassesToEmitFile(pass, dest, nullptr,
                                         llvm::CGFT_ObjectFile)) {
    std::cerr << "TargetMachine can't emit a file of this type";
    exit(1);
  }
  pass.run(*mod);

  dest.flush();
  dest.close();
}

void destroy_llvm(llvm::TargetMachine *tm) { delete tm; }

void destroy_ctx() {
  if (mod != nullptr) {
    delete mod;
    mod = nullptr;
  }
  if (Builder != nullptr) {
    delete Builder;
    Builder = nullptr;
  }
  if (DBuilder != nullptr) {
    delete DBuilder;
    DBuilder = nullptr;
  }
  if (ctx != nullptr) {
    delete ctx;
    ctx = nullptr;
  }
}

llvm::LLVMContext *make_ctx() {
  if (ctx != nullptr) {
    // delete ctx;
    return ctx;
  }
  ctx = new llvm::LLVMContext();
  return ctx;
}

llvm::Module *make_module(char *name, llvm::TargetMachine *TargetMachine,
                          char *triple) {
  if (mod != nullptr) {
    delete mod;
    mod = nullptr;
  }
  // std::string TargetTriple(triple);
  mod = new llvm::Module(name, *ctx);
  mod->setTargetTriple(triple);
  mod->setDataLayout(TargetMachine->createDataLayout());
  return mod;
}

llvm::IRBuilder<> *make_builder() {
  if (Builder != nullptr) {
    delete Builder;
    Builder = nullptr;
  }
  Builder = new llvm::IRBuilder<>(*ctx);
  return Builder;
}

void init_dbg() {
  if (DBuilder != nullptr) {
    delete DBuilder;
    DBuilder = nullptr;
  }
  DBuilder = new llvm::DIBuilder(*mod);
  mod->addModuleFlag(llvm::Module::Max, "Dwarf Version", 4);
  mod->addModuleFlag(llvm::Module::Warning, "Debug Info Version", 3);
  mod->addModuleFlag(llvm::Module::Min, "PIC Level", 2);
  mod->addModuleFlag(llvm::Module::Max, "PIE Level", 2);
}

llvm::DIFile *createFile(char *path, char *dir) {
  return DBuilder->createFile(path, dir);
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

llvm::DICompileUnit *createCompileUnit(int lang, llvm::DIFile *file) {
  return DBuilder->createCompileUnit(
      lang, file, "lang dbg", false, "", 0, "",
      llvm::DICompileUnit::DebugEmissionKind::FullDebug, 0, true, false,
      llvm::DICompileUnit::DebugNameTableKind::None);
}

void replaceGlobalVariables(llvm::DICompileUnit *cu,
                            std::vector<llvm::Metadata *> *vec) {
  llvm::MDTuple *tuple = llvm::MDTuple::get(*ctx, *vec);
  llvm::MDTupleTypedArrayWrapper<llvm::DIGlobalVariableExpression> w(tuple);
  cu->replaceGlobalVariables(w);
}

llvm::DILexicalBlock *createLexicalBlock(llvm::DIScope *scope,
                                         llvm::DIFile *file, int line,
                                         int col) {
  return DBuilder->createLexicalBlock(scope, file, line, col);
}

void SetCurrentDebugLocation(llvm::DIScope *scope, int line, int pos) {
  Builder->SetCurrentDebugLocation(
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
createSubroutineType(std::vector<llvm::Metadata *> *types) {
  return DBuilder->createSubroutineType(DBuilder->getOrCreateTypeArray(*types));
}

llvm::Function *getFunction(char *name) { return mod->getFunction(name); }

void setSection(llvm::Function *f, char *sec) { f->setSection(sec); }

llvm::DISubprogram *createFunction(llvm::DIScope *scope, char *name,
                                   char *linkage_name, llvm::DIFile *file,
                                   int line, llvm::DISubroutineType *ft,
                                   int spflags) {
  // std::cout << "createFunction " << name << ", " << linkage_name << "\n";
  return DBuilder->createFunction(scope, name, linkage_name, file, line, ft,
                                  line, llvm::DINode::FlagPrototyped,
                                  (llvm::DISubprogram::DISPFlags)spflags);
}

void setSubprogram(llvm::Function *f, llvm::DISubprogram *sp) {
  f->setSubprogram(sp);
}

llvm::DILocalVariable *createParameterVariable(llvm::DIScope *scope, char *name,
                                               int idx, llvm::DIFile *file,
                                               int line, llvm::DIType *type,
                                               bool preserve) {
  return DBuilder->createParameterVariable(scope, name, idx, file, line, type,
                                           preserve);
}

llvm::DILocalVariable *createAutoVariable(llvm::DIScope *scope, char *name,
                                          llvm::DIFile *file, int line,
                                          llvm::DIType *ty) {
  return DBuilder->createAutoVariable(scope, name, file, line, ty);
}

llvm::DIExpression *createExpression() { return DBuilder->createExpression(); }

llvm::DILocation *DILocation_get(llvm::DIScope *scope, int line, int pos) {
  return llvm::DILocation::get(scope->getContext(), line, pos, scope);
}

void insertDeclare(llvm::Value *value, llvm::DILocalVariable *var_info,
                   llvm::DIExpression *expr, llvm::DILocation *loc,
                   llvm::BasicBlock *bb) {
  DBuilder->insertDeclare(value, var_info, expr, loc, bb);
}

llvm::DICompositeType *createStructType(llvm::DIScope *scope, char *name,
                                        llvm::DIFile *file, int line, int size,
                                        std::vector<llvm::Metadata *> *elems) {
  auto arr = llvm::DINodeArray(llvm::MDTuple::get(*ctx, *elems));
  return DBuilder->createStructType(scope, name, file, line, size, 0,
                                    llvm::DINode::FlagZero, nullptr, arr);
}

const llvm::StructLayout *getStructLayout(llvm::StructType *st) {
  return mod->getDataLayout().getStructLayout(st);
}

uint64_t DataLayout_getTypeSizeInBits(llvm::Type *ty) {
  return mod->getDataLayout().getTypeSizeInBits(ty);
}

int64_t getElementOffsetInBits(llvm::StructLayout *sl, int idx) {
  return sl->getElementOffsetInBits(idx);
}

llvm::DIType *get_di_null() { return nullptr; }

int64_t DIType_getSizeInBits(llvm::DIType *ty) { return ty->getSizeInBits(); }

void replaceElements(llvm::DICompositeType *st,
                     std::vector<llvm::Metadata *> *elems) {
  auto arr = llvm::DINodeArray(llvm::MDTuple::get(*ctx, *elems));
  st->replaceElements(arr);
}

llvm::DICompositeType *createVariantPart(llvm::DIScope *scope, char *name,
                                         llvm::DIFile *file, int line,
                                         int64_t size,
                                         llvm::DIDerivedType *disc,
                                         std::vector<llvm::Metadata *> *elems) {
  auto arr = llvm::DINodeArray(llvm::MDTuple::get(*ctx, *elems));
  return DBuilder->createVariantPart(scope, name, file, line, size, 0,
                                     llvm::DINode::FlagZero, disc, arr);
}

llvm::DIDerivedType *createVariantMemberType(llvm::DIScope *scope, char *name,
                                             llvm::DIFile *file, int line,
                                             int64_t size, int64_t off, int idx,
                                             llvm::DIType *ty) {
  auto intType = llvm::IntegerType::get(*ctx, 32);
  auto disc = llvm::ConstantInt::getSigned(intType, idx);
  return DBuilder->createVariantMemberType(
      scope, name, file, line, size, 0, off, disc, llvm::DINode::FlagZero, ty);
}

llvm::DIType *createBasicType(char *name, uint64_t size, int encoding) {
  return DBuilder->createBasicType(name, size, encoding);
}

int DW_ATE_boolean() { return llvm::dwarf::DW_ATE_boolean; }

int DW_ATE_signed() { return llvm::dwarf::DW_ATE_signed; }

int DW_ATE_unsigned() { return llvm::dwarf::DW_ATE_unsigned; }

int DW_ATE_float() { return llvm::dwarf::DW_ATE_float; }

llvm::DIType *createPointerType(llvm::DIType *elem, int64_t size) {
  return DBuilder->createPointerType(elem, size);
}

llvm::Metadata *getOrCreateSubrange(int64_t lo, int64_t count) {
  return DBuilder->getOrCreateSubrange(lo, count);
}

llvm::DIType *createArrayType(int64_t size, llvm::DIType *ty,
                              std::vector<llvm::Metadata *> *elems) {
  llvm::DINodeArray subs(llvm::MDTuple::get(*ctx, *elems));
  return DBuilder->createArrayType(size, 0, ty, subs);
}

uint32_t make_di_flags(bool artificial) {
  if (artificial) {
    return llvm::DINode::FlagArtificial;
  }
  return llvm::DINode::FlagZero;
}

llvm::DIDerivedType *createMemberType(llvm::DIScope *scope, char *name,
                                      llvm::DIFile *file, int line,
                                      int64_t size, int64_t off, uint32_t flags,
                                      llvm::DIType *ty) {
  return DBuilder->createMemberType(scope, name, file, line, size, 0, off,
                                    (llvm::DINode::DIFlags)flags, ty);
}

llvm::DIScope *get_null_scope() { return nullptr; }

llvm::DIType *createObjectPointerType(llvm::DIType *ty) {
  return DBuilder->createObjectPointerType(ty);
}

llvm::DIGlobalVariableExpression *
createGlobalVariableExpression(llvm::DIScope *scope, char *name, char *lname,
                               llvm::DIFile *file, int line,
                               llvm::DIType *type) {
  return DBuilder->createGlobalVariableExpression(scope, name, lname, file,
                                                  line, type, false, true);
}

void addDebugInfo(llvm::GlobalVariable *gv,
                  llvm::DIGlobalVariableExpression *gve) {
  gv->addDebugInfo(gve);
}

void finalizeSubprogram(llvm::DISubprogram *sp) {
  DBuilder->finalizeSubprogram(sp);
}

void emit_llvm(char *llvm_file) {
  std::error_code ec;
  llvm::raw_fd_ostream fd(llvm_file, ec);
  mod->print(fd, nullptr);
}

llvm::Type *getVoidTy() { return Builder->getVoidTy(); }

llvm::FunctionType *make_ft(llvm::Type *retType,
                            std::vector<llvm::Type *> *argTypes, bool vararg) {
  return llvm::FunctionType::get(retType, *argTypes, vararg);
}

llvm::Function *make_func(llvm::FunctionType *ft, int linkage, char *name) {
  return llvm::Function::Create(ft, (llvm::GlobalValue::LinkageTypes)linkage,
                                name, *mod);
}

void setCallingConv(llvm::Function *f) {
  f->setCallingConv(llvm::CallingConv::C);
}

int ext() { return llvm::Function::ExternalLinkage; }
int odr() { return llvm::Function::LinkOnceODRLinkage; }
/*llvm::GlobalValue::LinkageTypes ext() {
    return llvm::Function::ExternalLinkage;
}
llvm::GlobalValue::LinkageTypes odr() {
    return llvm::Function::LinkOnceODRLinkage;
}*/

llvm::Argument *get_arg(llvm::Function *f, int i) { return f->getArg(i); }

void Argument_setname(llvm::Argument *arg, char *name) { arg->setName(name); }
void Argument_setsret(llvm::Argument *arg, llvm::Type *ty) {
  auto attr = llvm::Attribute::get(*ctx, llvm::Attribute::StructRet, ty);
  arg->addAttr(attr);
}

llvm::Attribute::AttrKind get_sret() { return llvm::Attribute::StructRet; }

void Function_print(llvm::Function *f) { f->print(llvm::errs()); }

llvm::StructType *make_struct_ty(char *name) {
  return llvm::StructType::create(*ctx, name);
}
llvm::StructType *make_struct_ty2(char *name,
                                  std::vector<llvm::Type *> *elems) {
  return llvm::StructType::create(*ctx, *elems, name);
}
llvm::StructType *make_struct_ty_noname(std::vector<llvm::Type *> *elems) {
  return llvm::StructType::create(*ctx, *elems);
}

int getSizeInBits(llvm::StructType *st) {
  int res = mod->getDataLayout().getStructLayout(st)->getSizeInBits();
  /*if (res == 0) {
    st->dump();
    auto name = st->getName().str();
    std::cout << "getSizeInBits " << name << " size: " << res
              << " elems:" << st->getNumElements() << std::endl;
  }*/
  return res;
}

int StructType_getNumElements(llvm::StructType *st) {
  return st->getNumElements();
}

llvm::ArrayType *get_arrty(llvm::Type *elem, int size) {
  return llvm::ArrayType::get(elem, size);
}

llvm::Type *getPtr() { return llvm::PointerType::getUnqual(*ctx); }

llvm::GlobalVariable *make_stdout() {
  auto res = new llvm::GlobalVariable(*mod, getPtr(), false,
                                      llvm::GlobalValue::ExternalLinkage,
                                      nullptr, "stdout");
  res->addAttribute("global");
  return res;
}

llvm::GlobalVariable *make_global(const char *name, llvm::Type *ty,
                                  llvm::Constant *init) {
  auto res = new llvm::GlobalVariable(
      *mod, ty, false, llvm::GlobalValue::ExternalLinkage, init, name);
  // res->addAttribute("global");
  return res;
}

int GlobalValue_ext() { return llvm::GlobalValue::ExternalLinkage; }
int GlobalValue_appending() { return llvm::GlobalValue::AppendingLinkage; }

llvm::GlobalVariable *make_global_linkage(const char *name, llvm::Type *ty,
                                          llvm::Constant *init, int linkage) {
  auto res = new llvm::GlobalVariable(
      *mod, ty, false, (llvm::GlobalValue::LinkageTypes)linkage, init, name);
  return res;
}

llvm::Constant *ConstantStruct_get(llvm::StructType *ty) {
  return llvm::ConstantStruct::get(ty);
}

llvm::Constant *ConstantStruct_get_elems(llvm::StructType *ty,
                                         std::vector<llvm::Constant *> *elems) {
  return llvm::ConstantStruct::get(ty, *elems);
}

llvm::Constant *ConstantArray_get(llvm::ArrayType *ty,
                                  std::vector<llvm::Constant *> *vec) {
  return llvm::ConstantArray::get(ty, *vec);
}

llvm::Value *CreateAlloca(llvm::Type *ty) { return Builder->CreateAlloca(ty); }

void Value_setName(llvm::Value *val, char *name) { val->setName(name); }

llvm::Value *CreateFPCast(llvm::Value *val, llvm::Type *trg_type) {
  return Builder->CreateFPCast(val, trg_type);
}
llvm::Value *CreateSIToFP(llvm::Value *val, llvm::Type *trg_type) {
  return Builder->CreateSIToFP(val, trg_type);
}
llvm::Value *CreateUIToFP(llvm::Value *val, llvm::Type *trg_type) {
  return Builder->CreateUIToFP(val, trg_type);
}
llvm::Value *CreateFPToSI(llvm::Value *val, llvm::Type *trg_type) {
  return Builder->CreateFPToSI(val, trg_type);
}
llvm::Value *CreateFPToUI(llvm::Value *val, llvm::Type *trg_type) {
  return Builder->CreateFPToUI(val, trg_type);
}

void CreateStore(llvm::Value *val, llvm::Value *ptr) {
  Builder->CreateStore(val, ptr);
}

llvm::BasicBlock *create_bb2(llvm::Function *func) {
  return llvm::BasicBlock::Create(*ctx, "", func);
}

llvm::BasicBlock *create_bb2_named(llvm::Function *func, const char *name) {
  return llvm::BasicBlock::Create(*ctx, name, func);
}

llvm::BasicBlock *create_bb() { return llvm::BasicBlock::Create(*ctx, ""); }

llvm::BasicBlock *create_bb_named(const char *name) {
  return llvm::BasicBlock::Create(*ctx, name);
}

void SetInsertPoint(llvm::BasicBlock *bb) { Builder->SetInsertPoint(bb); }

llvm::BasicBlock *GetInsertBlock() { return Builder->GetInsertBlock(); }

void func_insert(llvm::Function *f, llvm::BasicBlock *bb) {
  f->insert(f->end(), bb);
}

llvm::SwitchInst *CreateSwitch(llvm::Value *cond, llvm::BasicBlock *default_bb,
                               int num_cases) {
  return Builder->CreateSwitch(cond, default_bb, num_cases);
}

void SwitchInst_addCase(llvm::SwitchInst* node, llvm::ConstantInt *OnVal, llvm::BasicBlock *Dest) {
  node->addCase(OnVal, Dest);
}

llvm::Value *CreateCall(llvm::Function *f, std::vector<llvm::Value *> *args) {
  return Builder->CreateCall(f, *args);
}

llvm::Value *CreateCall_ft(llvm::FunctionType *ft, llvm::Value* val, std::vector<llvm::Value *> *args) {
  return Builder->CreateCall(ft, val, *args);
}

void CreateRet(llvm::Value *val) { Builder->CreateRet(val); }

void CreateRetVoid() { Builder->CreateRetVoid(); }

bool verifyFunction(llvm::Function *func) {
  return llvm::verifyFunction(*func, &llvm::outs());
}

void CreateCondBr(llvm::Value *cond, llvm::BasicBlock *then,
                  llvm::BasicBlock *next) {
  Builder->CreateCondBr(cond, then, next);
}

int getPrimitiveSizeInBits(llvm::Type *type) {
  return type->getPrimitiveSizeInBits();
}

llvm::Type *Value_getType(llvm::Value *val) { return val->getType(); }

void CreateBr(llvm::BasicBlock *bb) { Builder->CreateBr(bb); }

llvm::PHINode *CreatePHI(llvm::Type *type, int cnt) {
  return Builder->CreatePHI(type, cnt);
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

llvm::Value *CreateCmp(int op, llvm::Value *l, llvm::Value *r) {
  return Builder->CreateCmp((llvm::CmpInst::Predicate)op, l, r);
}

llvm::Value *CreateNSWAdd(llvm::Value *l, llvm::Value *r) {
  return Builder->CreateNSWAdd(l, r);
}
llvm::Value *CreateAdd(llvm::Value *l, llvm::Value *r) {
  return Builder->CreateAdd(l, r);
}
llvm::Value *CreateFAdd(llvm::Value *l, llvm::Value *r) {
  return Builder->CreateFAdd(l, r);
}
llvm::Value *CreateNSWSub(llvm::Value *l, llvm::Value *r) {
  return Builder->CreateNSWSub(l, r);
}
llvm::Value *CreateSub(llvm::Value *l, llvm::Value *r) {
  return Builder->CreateSub(l, r);
}
llvm::Value *CreateFSub(llvm::Value *l, llvm::Value *r) {
  return Builder->CreateFSub(l, r);
}
llvm::Value *CreateNSWMul(llvm::Value *l, llvm::Value *r) {
  return Builder->CreateNSWMul(l, r);
}
llvm::Value *CreateFMul(llvm::Value *l, llvm::Value *r) {
  return Builder->CreateFMul(l, r);
}
llvm::Value *CreateSDiv(llvm::Value *l, llvm::Value *r) {
  return Builder->CreateSDiv(l, r);
}
llvm::Value *CreateFDiv(llvm::Value *l, llvm::Value *r) {
  return Builder->CreateFDiv(l, r);
}
llvm::Value *CreateSRem(llvm::Value *l, llvm::Value *r) {
  return Builder->CreateSRem(l, r);
}
llvm::Value *CreateFRem(llvm::Value *l, llvm::Value *r) {
  return Builder->CreateFRem(l, r);
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
llvm::Value *CreateNeg(llvm::Value *val) { return Builder->CreateNeg(val); }
llvm::Value *CreateFNeg(llvm::Value *val) { return Builder->CreateFNeg(val); }

llvm::Constant *CreateGlobalStringPtr(char *str) {
  return Builder->CreateGlobalStringPtr(str);
}

bool isPointerTy(llvm::Type *type) { return type->isPointerTy(); }
bool Value_isPointerTy(llvm::Value *val) {
  return val->getType()->isPointerTy();
}

llvm::UnreachableInst *CreateUnreachable() {
  return Builder->CreateUnreachable();
}

llvm::Constant *getConst(llvm::Type *type, int val) {
  return llvm::ConstantInt::get(type, val);
}

llvm::Constant *getConstF(llvm::Type *type, double val) {
  return llvm::ConstantFP::get(type, val);
}

void CreateMemCpy(llvm::Value *trg, llvm::Value *src, uint64_t size) {
  Builder->CreateMemCpy(trg, llvm::MaybeAlign(0), src, llvm::MaybeAlign(0),
                        size);
}

llvm::Value *CreatePtrToInt(llvm::Value *val, llvm::Type *type) {
  return Builder->CreatePtrToInt(val, type);
}

llvm::ConstantInt *makeInt(int64_t val, int bits) {
  auto intType = llvm::IntegerType::get(*ctx, bits);
  return llvm::ConstantInt::getSigned(intType, val);
}

llvm::Type *getInt(int bit) { return llvm::IntegerType::get(*ctx, bit); }

llvm::Type *getFloatTy() { return llvm::Type::getFloatTy(*ctx); }
llvm::Type *getDoubleTy() { return llvm::Type::getDoubleTy(*ctx); }
llvm::Constant *makeFloat(float val) {
  return llvm::ConstantFP::get(getFloatTy(), val);
}

llvm::Constant *makeDouble(double val) {
  return llvm::ConstantFP::get(getDoubleTy(), val);
}

llvm::ArrayType *getArrTy(llvm::Type *elem, int size) {
  return llvm::ArrayType::get(elem, size);
}

llvm::PointerType *getPointerTo(llvm::Type *type) {
  return type->getPointerTo();
}

llvm::Value *ConstantPointerNull_get(llvm::PointerType *ty) {
  return llvm::ConstantPointerNull::get(ty);
}

bool isVoidTy(llvm::Type *type) { return type->isVoidTy(); }

void setBody(llvm::StructType *st, std::vector<llvm::Type *> *elems) {
  st->setBody(*elems);
}

void Value_dump(llvm::Value *v) { v->dump(); }

void Type_dump(llvm::Type *v) { v->dump(); }

llvm::Value *CreateSExt(llvm::Value *val, llvm::Type *type) {
  return Builder->CreateSExt(val, type);
}
llvm::Value *CreateZExt(llvm::Value *val, llvm::Type *type) {
  return Builder->CreateZExt(val, type);
}
llvm::Value *CreateFPExt(llvm::Value *val, llvm::Type *type) {
  return Builder->CreateFPExt(val, type);
}
llvm::Value *CreateFPTrunc(llvm::Value *val, llvm::Type *type) {
  return Builder->CreateFPTrunc(val, type);
}

llvm::Value *CreateStructGEP(llvm::Value *ptr, int idx, llvm::Type *type) {
  return Builder->CreateStructGEP(type, ptr, idx);
  // return Builder->CreateConstInBoundsGEP1_64(type, ptr, idx);
}
llvm::Value *CreateInBoundsGEP(llvm::Type *type, llvm::Value *ptr,
                               std::vector<llvm::Value *> *idx) {
  return Builder->CreateInBoundsGEP(type, ptr, *idx);
}

llvm::Value *CreateGEP(llvm::Type *type, llvm::Value *ptr,
                       std::vector<llvm::Value *> *idx) {
  return Builder->CreateGEP(type, ptr, *idx);
}

llvm::Value *CreateLoad(llvm::Type *type, llvm::Value *val) {
  auto val_type = val->getType();
  if (val_type->isVoidTy()) {
    llvm::errs() << "Error: Cannot load from void type\n";
    exit(1);
  }
  return Builder->CreateLoad(type, val);
}

llvm::Value *getTrue() { return Builder->getTrue(); }
llvm::Value *getFalse() { return Builder->getFalse(); }

int64_t get_last_write_time(const char *path) {
  auto time = std::filesystem::last_write_time(path).time_since_epoch() /
              std::chrono::milliseconds(1);
  return time;
}

void set_as_executable(const char *path) {
  std::filesystem::permissions(path,
                               std::filesystem::perms::owner_all |
                                   std::filesystem::perms::group_read |
                                   std::filesystem::perms::others_read,
                               std::filesystem::perm_options::add);
}
}