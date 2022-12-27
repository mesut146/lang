#include "Compiler.h"
#include "Resolver.h"
#include "parser/Ast.h"
#include "parser/Parser.h"
#include <filesystem>
#include <iostream>
#include <unordered_map>

#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Value.h>
#include <llvm/IR/Attributes.h>
#include <llvm/Support/Host.h>
#include <llvm/Support/TargetRegistry.h>
#include <llvm/Support/TargetSelect.h>
#include <llvm/Support/FileSystem.h>
#include <llvm/Target/TargetOptions.h>
#include <llvm/Target/TargetMachine.h>
#include <llvm/IR/LegacyPassManager.h>

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
static std::map<std::string, llvm::Value *> NamedValues;
std::map<Method*,llvm::Function*> funcMap;

static void InitializeModule() {
    // Open a new context and module.
    TheContext = std::make_unique<llvm::LLVMContext>();
    TheModule = std::make_unique<llvm::Module>("test", *TheContext);

    // Create a new builder for the module.
    Builder = std::make_unique<llvm::IRBuilder<>>(*TheContext);
}

llvm::Type* mapType(Type* t){
  auto s = t->print();
  if(s=="int") return llvm::Type::getInt32Ty(*TheContext);
  throw std::runtime_error("mapType: "+s);
}

void createProtos(Unit* unit){
    for (auto m : unit->methods) {
        std::vector<llvm::Type *> argTypes;
        for(auto& prm:m->params){
          argTypes.push_back(mapType(prm->type));
        }
        auto retType = mapType(m->type);
        llvm::FunctionType *FT =
                llvm::FunctionType::get(retType, argTypes, false);
        auto *f = llvm::Function::Create(FT, llvm::Function::ExternalLinkage, m->name, TheModule.get());
unsigned Idx = 0;
  for (auto &Arg : f->args()){
    Arg.setName(m->params[Idx++]->name);
  }
  funcMap[m]=f;
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
    for (auto m : unit->methods) {
        /*std::vector<llvm::Type *> argTypes;
        for(auto& prm:m->params){
          argTypes.push_back(mapType(prm->type));
        }
        auto retType = mapType(m->type);
        llvm::FunctionType *FT =
                llvm::FunctionType::get(retType, argTypes, false);
        auto *f = llvm::Function::Create(FT, llvm::Function::ExternalLinkage, m->name, TheModule.get());
unsigned Idx = 0;
  for (auto &Arg : f->args())
    Arg.setName(m->params[Idx++]->name);
*/
auto f = funcMap[m];
  auto *BB = llvm::BasicBlock::Create(*TheContext, "entry", f);
  Builder->SetInsertPoint(BB);
  
  NamedValues.clear();
  for (auto &Arg : f->args())
    NamedValues[std::string(Arg.getName())] = &Arg;

  m->body->accept(this, nullptr);

  // Record the function 
  //f->eraseFromParent();
    }
    //TheModule->print(,nullptr);
    TheModule->dump();
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
  std::cerr<< "Could not open file: " << EC.message();
  exit ( 1);
}

llvm::legacy::PassManager pass;
auto FileType = llvm::CGFT_ObjectFile;

if (TargetMachine->addPassesToEmitFile(pass, dest, nullptr, FileType)) {
  std::cerr << "TargetMachine can't emit a file of this type";
  exit( 1);
}

pass.run(*TheModule);
dest.flush();
}

void* Compiler::visitBlock(Block *b, void* arg){
    for(auto& s:b->list){
        s->accept(this, nullptr);
    }
    return nullptr;
}

void* Compiler::visitReturnStmt(ReturnStmt *t, void* arg){
    auto val = (llvm:: Value*) t->expr->accept (this, nullptr);
    Builder->CreateRet(val);
    return nullptr;
}
void* Compiler::visitExprStmt(ExprStmt *b, void* arg){
    return b->expr->accept (this, nullptr);
}
void* Compiler::visitInfix(Infix *i, void* arg) {
    auto l=(llvm::Value*)i->left->accept (this, nullptr);
    auto r=(llvm::Value*)i->right->accept (this, nullptr);
    if(i->op=="+"){
        return Builder->CreateAdd(l,r, "addtmp");
    }
    throw std::runtime_error("infix: "+i->print());
}
void* Compiler::visitSimpleName(SimpleName *n, void* arg){
    auto it = NamedValues.find(n->name);
    if(it==NamedValues.end()){
        throw std::runtime_error("unknown ref: "+n->name);
    }
    return it->second;
}
static llvm::Function *printf_prototype(llvm::LLVMContext &ctx, llvm::Module *mod) {
    auto *Pty = llvm::PointerType::get(llvm::IntegerType::get(mod->getContext(), 8), 0);
            auto *FuncTy9 = llvm::FunctionType::get(llvm::IntegerType::get(mod->getContext(), 32), true);

            auto func_printf = llvm::Function::Create(FuncTy9, llvm::GlobalValue::ExternalLinkage, "printf", mod);
            func_printf->setCallingConv(llvm::CallingConv::C);

            llvm:: AttributeList func_printf_PAL;
            func_printf->setAttributes(func_printf_PAL);
        return func_printf;
}

void* Compiler::visitMethodCall(MethodCall *mc, void* arg){
    llvm:: Function* f;
    if(mc->name=="print"){
        f = printf_prototype(*TheContext, TheModule.get());
        
    }else{
    auto resolv=new Resolver(unit);
    auto rt = (RType*)mc->accept (resolv, nullptr);
    f = funcMap[rt->targetMethod];
    }
    std::vector<llvm::Value *> ArgsV;
  for (unsigned i = 0, e = mc->args.size(); i != e; ++i) {
      auto a=mc->args[i];
    ArgsV.push_back((llvm::Value*)a->accept(this, nullptr));
    if (!ArgsV.back())
      throw std:: runtime_error("arg null: "+a->print());
  }

  return Builder->CreateCall(f, ArgsV, "calltmp");
}
llvm::Value* makeStr(std::string str, llvm::Module* module, llvm::LLVMContext &context) {
    //0. Def
    auto charType = llvm::IntegerType::get(context, 8);


    //1. Initialize chars vector
    std::vector<llvm::Constant *> chars(str.length());
    for(unsigned int i = 0; i < str.size(); i++) {
      chars[i] = llvm::ConstantInt::get(charType, str[i]);
    }

    //1b. add a zero terminator too
    chars.push_back(llvm::ConstantInt::get(charType, 0));


    //2. Initialize the string from the characters
    auto stringType = llvm::ArrayType::get(charType, chars.size());

    //3. Create the declaration statement
    auto globalDeclaration = (llvm::GlobalVariable*) module->getOrInsertGlobal(".str", stringType);
    globalDeclaration->setInitializer(llvm::ConstantArray::get(stringType, chars));
    globalDeclaration->setConstant(true);
    globalDeclaration->setLinkage(llvm::GlobalValue::LinkageTypes::PrivateLinkage);
    globalDeclaration->setUnnamedAddr (llvm::GlobalValue::UnnamedAddr::Global);



    //4. Return a cast to an i8*
    return llvm::ConstantExpr::getBitCast(globalDeclaration, charType->getPointerTo());
}
void* Compiler::visitLiteral(Literal *n, void* arg){
    if(n->isStr){
       //auto ptr = llvm::PointerType::get(llvm::IntegerType::get(*TheContext, 8), 0);
       auto trimmed = n->val.substr(1, n->val.size()-2);
       return makeStr(trimmed,TheModule.get(), *TheContext);
    }
    if(n->isInt){
        auto intType = llvm::IntegerType::get(*TheContext, 32);
        return llvm::ConstantInt::get(intType, atoi(n->val.c_str()));
    }
    throw std:: runtime_error("literal: "+n->print());
}