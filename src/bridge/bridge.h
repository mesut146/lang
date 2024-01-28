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

extern "C"{
    void init();
    //write to ptr, return length
    int getDefaultTargetTriple(char* ptr);
    void InitializeAllTargetInfos();
    void InitializeAllTargets();
    void InitializeAllTargetMCs();
    void InitializeAllAsmParsers();
    void InitializeAllAsmPrinters();
    const void* lookupTarget(const char* triple);
    void* createTargetMachine(const char* TargetTriple);
    
    void emit(const char* name, void* target, char* triple, void* module);
}