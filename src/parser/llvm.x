import parser/bridge
import ast/ast

type LLVMBool = i32;
func LLVMBoolTrue(): i32{ return 1; }
func LLVMBoolFalse(): i32{ return 0; }
func toLLVMBool(b: bool): i32{
  if(b) return 1;
  return 0;
}


struct LLVMOpaqueContext;
struct LLVMOpaqueModule;
struct LLVMTarget;
struct LLVMOpaqueTargetMachine;
struct LLVMOpaqueTargetMachineOptions;
struct LLVMOpaqueTargetData;
struct LLVMOpaqueBuilder;
struct LLVMOpaqueValue;
struct LLVMOpaqueType;
struct LLVMOpaqueBasicBlock;
struct LLVMOpaqueAttributeRef;

type LLVMTargetRef = LLVMTarget*;
type LLVMTargetMachineRef = LLVMOpaqueTargetMachine*;
type LLVMValueRef = LLVMOpaqueValue*;
type LLVMTypeRef = LLVMOpaqueType*;

enum LLVMCodeGenOptLevel{
    LLVMCodeGenLevelNone,
    LLVMCodeGenLevelLess,
    LLVMCodeGenLevelDefault,
    LLVMCodeGenLevelAggressive
}
enum LLVMRelocMode{
    LLVMRelocDefault,
    LLVMRelocStatic,
    LLVMRelocPIC,
    LLVMRelocDynamicNoPic,
    LLVMRelocROPI,
    LLVMRelocRWPI,
    LLVMRelocROPI_RWPI
}
enum LLVMCodeModel{
    LLVMCodeModelDefault,
    LLVMCodeModelJITDefault,
    LLVMCodeModelTiny,
    LLVMCodeModelSmall,
    LLVMCodeModelKernel,
    LLVMCodeModelMedium,
    LLVMCodeModelLarge
}
enum LLVMVerifierFailureAction{
    LLVMAbortProcessAction,/* verifier will print to stderr and abort() */
    LLVMPrintMessageAction,/* verifier will print to stderr and return 1 */
    LLVMReturnStatusAction /* verifier will just return 1 */
}
enum LLVMCodeGenFileType{
    LLVMAssemblyFile, 	
    LLVMObjectFile
}
enum AddressSpace{
    ADDRESS_SPACE_GENERIC,
    ADDRESS_SPACE_GLOBAL,
    ADDRESS_SPACE_SHARED,
    ADDRESS_SPACE_CONST,
    ADDRESS_SPACE_LOCAL,
    ADDRESS_SPACE_PARAM
}
enum LLVMIntPredicate{
    LLVMIntEQ /* = 32*/, 	/*equal*/
    LLVMIntNE, 	/*not equal*/
    LLVMIntUGT, /*unsigned greater than*/
    LLVMIntUGE, /*unsigned greater or equal*/
    LLVMIntULT, /*unsigned less than*/
    LLVMIntULE, /*unsigned less or equal*/
    LLVMIntSGT, /*signed greater than*/
    LLVMIntSGE, /*signed greater or equal*/
    LLVMIntSLT, /*signed less than*/
    LLVMIntSLE, /*signed less or equal */
}
impl LLVMIntPredicate{
    func from(s: str): i32{
        if(s.eq("==")) return 32; //LLVMIntPredicate::LLVMIntEQ;
        if(s.eq("!=")) return 33; //LLVMIntPredicate::LLVMIntNE;
        if(s.eq(">")) return 38; //LLVMIntPredicate::LLVMIntSGT;
        if(s.eq(">=")) return 39; //LLVMIntPredicate::LLVMIntSGE;
        if(s.eq("<")) return 40; //LLVMIntPredicate::LLVMIntSLT;
        if(s.eq("<=")) return 41; //LLVMIntPredicate::LLVMIntSLE;
        if(s.eq(">")) return 34; //LLVMIntPredicate::LLVMIntUGT;
        if(s.eq(">=")) return 35; //LLVMIntPredicate::LLVMIntUGE;
        if(s.eq("<")) return 36; //LLVMIntPredicate::LLVMIntULT;
        if(s.eq("<=")) return 37; //LLVMIntPredicate::LLVMIntULE;
        panic("op='{}'", s);
    }
}
enum LLVMRealPredicate{
    LLVMRealPredicateFalse, /**< Always false (always folded) */
    LLVMRealOEQ,            /**< True if ordered and equal */
    LLVMRealOGT,            /**< True if ordered and greater than */
    LLVMRealOGE,            /**< True if ordered and greater than or equal */
    LLVMRealOLT,            /**< True if ordered and less than */
    LLVMRealOLE,            /**< True if ordered and less than or equal */
    LLVMRealONE,            /**< True if ordered and operands are unequal */
    LLVMRealORD,            /**< True if ordered (no nans) */
    LLVMRealUNO,            /**< True if unordered: isnan(X) | isnan(Y) */
    LLVMRealUEQ,            /**< True if unordered or equal */
    LLVMRealUGT,            /**< True if unordered or greater than */
    LLVMRealUGE,            /**< True if unordered, greater than, or equal */
    LLVMRealULT,            /**< True if unordered or less than */
    LLVMRealULE,            /**< True if unordered, less than, or equal */
    LLVMRealUNE,            /**< True if unordered or not equal */
    LLVMRealPredicateTrue   /**< Always true (always folded) */
}

enum LLVMCallConv{
  LLVMCCallConv             /*= 0*/,
  LLVMFastCallConv          /*= 8*/,
  LLVMColdCallConv          /*= 9*/,
  LLVMGHCCallConv           /*= 10*/,
  LLVMHiPECallConv          /*= 11*/,
  LLVMAnyRegCallConv        /*= 13*/,
  LLVMPreserveMostCallConv  /*= 14*/,
  LLVMPreserveAllCallConv   /*= 15*/,
  LLVMSwiftCallConv         /*= 16*/,
  LLVMCXXFASTTLSCallConv    /*= 17*/,
  LLVMX86StdcallCallConv    /*= 64*/,
  LLVMX86FastcallCallConv   /*= 65*/,
  LLVMARMAPCSCallConv       /*= 66*/,
  LLVMARMAAPCSCallConv      /*= 67*/,
  LLVMARMAAPCSVFPCallConv   /*= 68*/,
  LLVMMSP430INTRCallConv    /*= 69*/,
  LLVMX86ThisCallCallConv   /*= 70*/,
  LLVMPTXKernelCallConv     /*= 71*/,
  LLVMPTXDeviceCallConv     /*= 72*/,
  LLVMSPIRFUNCCallConv      /*= 75*/,
  LLVMSPIRKERNELCallConv    /*= 76*/,
  LLVMIntelOCLBICallConv    /*= 77*/,
  LLVMX8664SysVCallConv     /*= 78*/,
  LLVMWin64CallConv         /*= 79*/,
  LLVMX86VectorCallCallConv /*= 80*/,
  LLVMHHVMCallConv          /*= 81*/,
  LLVMHHVMCCallConv         /*= 82*/,
  LLVMX86INTRCallConv       /*= 83*/,
  LLVMAVRINTRCallConv       /*= 84*/,
  LLVMAVRSIGNALCallConv     /*= 85*/,
  LLVMAVRBUILTINCallConv    /*= 86*/,
  LLVMAMDGPUVSCallConv      /*= 87*/,
  LLVMAMDGPUGSCallConv      /*= 88*/,
  LLVMAMDGPUPSCallConv      /*= 89*/,
  LLVMAMDGPUCSCallConv      /*= 90*/,
  LLVMAMDGPUKERNELCallConv  /*= 91*/,
  LLVMX86RegCallCallConv    /*= 92*/,
  LLVMAMDGPUHSCallConv      /*= 93*/,
  LLVMMSP430BUILTINCallConv /*= 94*/,
  LLVMAMDGPULSCallConv      /*= 95*/,
  LLVMAMDGPUESCallConv      /*= 96*/,
}
enum LLVMLinkage{
  LLVMExternalLinkage,    /**< Externally visible function */
  LLVMAvailableExternallyLinkage,
  LLVMLinkOnceAnyLinkage, /**< Keep one copy of function when linking (inline)*/
  LLVMLinkOnceODRLinkage, /**< Same, but only replaced by something
                            equivalent. */
  LLVMLinkOnceODRAutoHideLinkage, /**< Obsolete */
  LLVMWeakAnyLinkage,     /**< Keep one copy of function when linking (weak) */
  LLVMWeakODRLinkage,     /**< Same, but only replaced by something
                            equivalent. */
  LLVMAppendingLinkage,   /**< Special purpose, only applies to global arrays */
  LLVMInternalLinkage,    /**< Rename collisions when linking (static
                               functions) */
  LLVMPrivateLinkage,     /**< Like Internal, but omit from symbol table */
  LLVMDLLImportLinkage,   /**< Obsolete */
  LLVMDLLExportLinkage,   /**< Obsolete */
  LLVMExternalWeakLinkage,/**< ExternalWeak linkage description */
  LLVMGhostLinkage,       /**< Obsolete */
  LLVMCommonLinkage,      /**< Tentative definitions */
  LLVMLinkerPrivateLinkage, /**< Like Private, but linker removes. */
  LLVMLinkerPrivateWeakLinkage /**< Like LinkerPrivate, but is weak. */
}
impl LLVMLinkage{
  func int(self): i32{
    return *(self as i32*);
  }
}

enum LLVMTypeKind{
  LLVMVoidTypeKind ,/*= 0,*/     /**< type with no size */
  LLVMHalfTypeKind ,/*= 1,*/     /**< 16 bit floating point type */
  LLVMFloatTypeKind ,/*= 2,*/    /**< 32 bit floating point type */
  LLVMDoubleTypeKind ,/*= 3,*/   /**< 64 bit floating point type */
  LLVMX86_FP80TypeKind ,/*= 4,*/ /**< 80 bit floating point type (X87) */
  LLVMFP128TypeKind ,/*= 5,*/ /**< 128 bit floating point type (112-bit mantissa)*/
  LLVMPPC_FP128TypeKind ,/*= 6,*/ /**< 128 bit floating point type (two 64-bits) */
  LLVMLabelTypeKind ,/*= 7,*/     /**< Labels */
  LLVMIntegerTypeKind ,/*= 8,*/   /**< Arbitrary bit width integers */
  LLVMFunctionTypeKind ,/*= 9,*/  /**< Functions */
  LLVMStructTypeKind ,/*= 10,*/   /**< Structures */
  LLVMArrayTypeKind ,/*= 11,*/    /**< Arrays */
  LLVMPointerTypeKind ,/*= 12,*/  /**< Pointers */
  LLVMVectorTypeKind ,/*= 13,*/   /**< Fixed width SIMD vector type */
  LLVMMetadataTypeKind ,/*= 14,*/ /**< Metadata */
                             /* 15 previously used by LLVMX86_MMXTypeKind */
  LLVMTokenTypeKind ,/*= 16,*/    /**< Tokens */
  LLVMScalableVectorTypeKind ,/*= 17,*/ /**< Scalable SIMD vector type */
  LLVMBFloatTypeKind ,/*= 18,*/         /**< 16 bit brain floating point type */
  LLVMX86_AMXTypeKind ,/*= 19,*/        /**< X86 AMX */
  LLVMTargetExtTypeKind ,/*= 20,*/      /**< Target extension type */
}
impl LLVMTypeKind{
  func int(self): i32{
    return *(self as i32*);
  }
}

func LLVMInitializeAllTargets(){
    LLVMInitializeX86Target();
    LLVMInitializeAArch64Target();
}
func LLVMInitializeAllTargetInfos(){
    LLVMInitializeX86TargetInfo();
    LLVMInitializeAArch64TargetInfo();
}
func LLVMInitializeAllTargetMCs(){
    LLVMInitializeX86TargetMC();
    LLVMInitializeAArch64TargetMC();
}
func LLVMInitializeAllAsmParsers(){
    LLVMInitializeX86AsmParser();
    LLVMInitializeAArch64AsmParser();
}
func LLVMInitializeAllAsmPrinters(){
    LLVMInitializeX86AsmPrinter();
    LLVMInitializeAArch64AsmPrinter();
}
extern{
    //func LLVMInitializeAllTargets();
    //func LLVMInitializeAllTargetInfos();
    //func LLVMInitializeAllTargetMCs();
    //func LLVMInitializeAllAsmParsers();
    //func LLVMInitializeAllAsmPrinters();
    //func LLVMInitializeAllDisassemblers();

    func LLVMInitializeX86Target();
    func LLVMInitializeX86TargetInfo();
    func LLVMInitializeX86TargetMC();
    func LLVMInitializeX86AsmParser();
    func LLVMInitializeX86AsmPrinter();

    func LLVMInitializeAArch64Target();
    func LLVMInitializeAArch64TargetInfo();
    func LLVMInitializeAArch64TargetMC();
    func LLVMInitializeAArch64AsmParser();
    func LLVMInitializeAArch64AsmPrinter();

    func LLVMGetDefaultTargetTriple(): i8*;
    func LLVMGetTargetFromName(name: i8*): LLVMTarget*;
    func LLVMGetTargetFromTriple(triple: i8*, target: LLVMTarget**, err: i8**): i32;
    func LLVMCreateTargetMachineOptions(): LLVMOpaqueTargetMachineOptions*;
    func LLVMCreateTargetMachineWithOptions (T: LLVMTarget*, Triple: i8*, Options: LLVMOpaqueTargetMachineOptions*): LLVMOpaqueTargetMachine*;
    func LLVMCreateTargetMachine(T: LLVMTarget*, Triple: i8*, CPU: i8*, Features: i8*, Level: LLVMCodeGenOptLevel, Reloc: LLVMRelocMode, CodeModel: LLVMCodeModel): LLVMOpaqueTargetMachine*;
    func LLVMTargetMachineOptionsSetCPU(Options: LLVMOpaqueTargetMachineOptions*, CPU: i8*);
    func LLVMTargetMachineOptionsSetFeatures(Options: LLVMOpaqueTargetMachineOptions*, Features: i8*);
    func LLVMTargetMachineOptionsSetABI(Options: LLVMOpaqueTargetMachineOptions*, ABI: i8*);
    func LLVMTargetMachineOptionsSetCodeGenOptLevel(Options: LLVMOpaqueTargetMachineOptions*, Level: LLVMCodeGenOptLevel);
    func LLVMTargetMachineOptionsSetRelocMode(Options: LLVMOpaqueTargetMachineOptions*, Reloc: LLVMRelocMode);
    func LLVMTargetMachineOptionsSetCodeModel(Options: LLVMOpaqueTargetMachineOptions*, CodeModel: LLVMCodeModel);
    func LLVMGetTargetMachineCPU(T: LLVMOpaqueTargetMachine*): i8*;
    func LLVMGetTargetMachineTarget(tm: LLVMOpaqueTargetMachine*): LLVMTarget*;

    //ctx, module, func
    func LLVMContextCreate(): LLVMOpaqueContext*;
    func LLVMContextDispose(c: LLVMOpaqueContext*);
    func LLVMModuleCreateWithNameInContext(name: i8*, c: LLVMOpaqueContext*): LLVMOpaqueModule*;
    func LLVMDisposeModule(m: LLVMOpaqueModule*);
    func LLVMSetTarget(m: LLVMOpaqueModule*, triple: i8*);
    func LLVMSetDataLayout(m: LLVMOpaqueModule*, DataLayoutStr: i8*);
    func LLVMSetModuleDataLayout (m: LLVMOpaqueModule*, DL: LLVMOpaqueTargetData*);
    func LLVMCreateTargetDataLayout(T: LLVMOpaqueTargetMachine*): LLVMOpaqueTargetData*;
    func LLVMDumpModule(m: LLVMOpaqueModule*);
    func LLVMPrintModuleToFile(m: LLVMOpaqueModule*, Filename: i8*, ErrorMessage: i8**): i32;
    func LLVMVerifyModule(m: LLVMOpaqueModule*, action: LLVMVerifierFailureAction, msg: i8**): i32;
    func LLVMTargetMachineEmitToFile (T: LLVMOpaqueTargetMachine*, M: LLVMOpaqueModule*, Filename: i8*, codegen: LLVMCodeGenFileType, ErrorMessage: i8**): i32;
    func LLVMAddFunction(m: LLVMOpaqueModule*, name: i8*, ft: LLVMOpaqueType*): LLVMOpaqueValue*;
    func LLVMSetFunctionCallConv(fn: LLVMOpaqueValue*, cc: i32);
    func LLVMSetLinkage(val: LLVMOpaqueValue*, linkage: i32 /*LLVMLinkage*/);
    func LLVMGetParam(fn: LLVMOpaqueValue*, idx: i32): LLVMOpaqueValue*;
    
    //types
    func LLVMPointerType(elem: LLVMOpaqueType*, addrspace: i32): LLVMOpaqueType*;
    func LLVMArrayType(elem: LLVMOpaqueType*, count: i32): LLVMOpaqueType*;
    func LLVMStructCreateNamed(C: LLVMOpaqueContext*, Name: i8*): LLVMOpaqueType*;
    func LLVMStructSetBody(StructTy: LLVMOpaqueType*, ElementTypes: LLVMOpaqueType**, ElementCount: i32, Packed: i32);
    func LLVMVoidTypeInContext(c: LLVMOpaqueContext*): LLVMOpaqueType*;
    func LLVMFloatTypeInContext(c: LLVMOpaqueContext*): LLVMOpaqueType*;
    func LLVMDoubleTypeInContext(c: LLVMOpaqueContext*): LLVMOpaqueType*;
    func LLVMIntTypeInContext(c: LLVMOpaqueContext*, bits: i32): LLVMOpaqueType*;
    func LLVMInt8TypeInContext(c: LLVMOpaqueContext*): LLVMOpaqueType*;
    func LLVMInt32TypeInContext(c: LLVMOpaqueContext*): LLVMOpaqueType*;
    func LLVMDumpValue(val: LLVMOpaqueValue*);
    func LLVMPrintValueToString(val: LLVMOpaqueValue*): i8*;
    func LLVMPrintTypeToString(val: LLVMOpaqueType*): i8*;
    func LLVMSizeOfTypeInBits(trg: LLVMTarget*, ty: LLVMOpaqueType*): i64;
    func LLVMTypeOf(val: LLVMOpaqueValue*): LLVMOpaqueType*;
    func LLVMFunctionType(ret: LLVMOpaqueType*, params: LLVMOpaqueType**, cnt: i32, vararg: LLVMBool): LLVMOpaqueType*;
    func LLVMGetTypeKind(ty: LLVMOpaqueType*): i32;

    //global
    func LLVMAddGlobal(md: LLVMOpaqueModule*, ty: LLVMOpaqueType*, name: i8*): LLVMOpaqueValue*;
    func LLVMConstStringInContext(C: LLVMOpaqueContext*, str: i8*, len: i32, nll: LLVMBool): LLVMOpaqueValue*;
    func LLVMSetInitializer(var: LLVMOpaqueValue*, val: LLVMOpaqueValue*);
    func LLVMSetGlobalConstant(var: LLVMOpaqueValue*, iscons: LLVMBool);
    
    //basic block
    func LLVMCreateBasicBlockInContext(B: LLVMOpaqueBuilder*, name: i8*): LLVMOpaqueBasicBlock*;
    func LLVMAppendBasicBlockInContext(C: LLVMOpaqueContext*, fn: LLVMOpaqueValue*, name: i8*): LLVMOpaqueBasicBlock*;
    func LLVMPositionBuilderAtEnd(B: LLVMOpaqueBuilder*, bb: LLVMOpaqueBasicBlock*);
    
    //builder
    func LLVMCreateBuilderInContext(C: LLVMOpaqueContext*): LLVMOpaqueBuilder*;
    func LLVMSetValueName2(val: LLVMOpaqueValue*, name: i8*, len: i64 /*size_t*/);
    func LLVMCreateTypeAttribute(c: LLVMOpaqueContext*, kind: i32, ty: LLVMOpaqueType*): LLVMOpaqueAttributeRef*;
    func LLVMGetEnumAttributeKindForName(name: i8*, len: i64): i32;
      
    func LLVMBuildICmp(B: LLVMOpaqueBuilder*, Op: i32, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
    func LLVMBuildFCmp(B: LLVMOpaqueBuilder*, Op: LLVMRealPredicate, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
    func LLVMBuildBr(B: LLVMOpaqueBuilder*, bb: LLVMOpaqueBasicBlock*): LLVMOpaqueValue*;
    func LLVMBuildCondBr(B: LLVMOpaqueBuilder*, cond: LLVMOpaqueValue*, then: LLVMOpaqueBasicBlock*, els: LLVMOpaqueBasicBlock*): LLVMOpaqueValue*;
    func LLVMBuildRetVoid(B: LLVMOpaqueBuilder*): LLVMOpaqueValue*;
    func LLVMBuildRet(B: LLVMOpaqueBuilder*, val: LLVMOpaqueValue*): LLVMOpaqueValue*;
    func LLVMConstInt(IntTy: LLVMOpaqueType*, N: i64, SignExtend: i32): LLVMOpaqueValue*;
    func LLVMBuildAlloca(B: LLVMOpaqueBuilder*, ty: LLVMOpaqueType*, name: i8*): LLVMOpaqueValue*;
    func LLVMBuildStore(B: LLVMOpaqueBuilder*, val: LLVMOpaqueValue*, ptr: LLVMOpaqueValue*): LLVMOpaqueValue*;
    func LLVMBuildMemCpy(B: LLVMOpaqueBuilder*, dst: LLVMOpaqueValue*, da: i32, src: LLVMOpaqueValue*, sa: i32, size: LLVMOpaqueValue*): LLVMOpaqueValue*;
    func LLVMConstGEP2(ty: LLVMOpaqueType*, val: LLVMOpaqueValue*, idx: LLVMOpaqueValue**, cnt: i32): LLVMOpaqueValue*;
    
}


func llvm_ctest(){
  LLVMInitializeAllTargetInfos();
  LLVMInitializeAllTargets();
  LLVMInitializeAllTargetMCs();
  LLVMInitializeAllAsmPrinters();
  LLVMInitializeAllAsmParsers();

  let triple = LLVMGetDefaultTargetTriple();
  printf("triple=%s\n", triple);
  let target = ptr::null<LLVMTarget>();
  let err = ptr::null<i8>();
  let code = LLVMGetTargetFromTriple(triple, &target, &err);
  print("code={}\n", code);
  printf("err=%s\n", err);
  print("ref is null={:?}\n", target as u64 == 0);

  let opt = LLVMCreateTargetMachineOptions();
  LLVMTargetMachineOptionsSetCPU(opt, "generic".ptr());
  let machine = LLVMCreateTargetMachineWithOptions(target, triple, opt);
  printf("machine=%p cpu='%s'\n", machine, LLVMGetTargetMachineCPU(machine));
}

struct Emitter{
    tm: LLVMOpaqueTargetMachine*;
    ctx: LLVMOpaqueContext*;
    module: LLVMOpaqueModule*;
    builder: LLVMOpaqueBuilder*;
}

impl Emitter{
    func new(module_name: str): Emitter{
        LLVMInitializeAllTargetInfos();
        LLVMInitializeAllTargets();
        LLVMInitializeAllTargetMCs();
        LLVMInitializeAllAsmPrinters();
        LLVMInitializeAllAsmParsers();

        let target_triple = CStr::new(LLVMGetDefaultTargetTriple());
        let env_triple = std::getenv("target_triple");
        if(env_triple.is_some()){
            target_triple.drop();
            target_triple = env_triple.unwrap().owned().cstr();
        }
        let target = ptr::null<LLVMTarget>();
        let err = ptr::null<i8>();
        let code = LLVMGetTargetFromTriple(target_triple.ptr(), &target, &err);
        if(code != 0) panic("cant init llvm triple");

        let opt = LLVMCreateTargetMachineOptions();
        LLVMTargetMachineOptionsSetCPU(opt, "generic".ptr());
        let tm = LLVMCreateTargetMachineWithOptions(target, target_triple.ptr(), opt);        

        let ctx = LLVMContextCreate();
        let name = module_name.cstr();
        let md = LLVMModuleCreateWithNameInContext(name.ptr(), ctx);
        LLVMSetTarget(md, target_triple.ptr());
        let dl = LLVMCreateTargetDataLayout(tm);
        LLVMSetModuleDataLayout(md, dl);

        let builder = LLVMCreateBuilderInContext(ctx);
        setModule(md as LLVMModule*);//todo remove these
        setCtx(ctx as LLVMContext*);
        setBuilder(builder as IRBuilder*);

        name.drop();
        target_triple.drop();
        return Emitter{tm: tm, ctx: ctx, module: md, builder: builder};
    }

    func dump(self){
        LLVMDumpModule(self.module);
    }

    func emit_module(self, file: str){
        let file_c = file.cstr();
        let error = ptr::null<i8>();
        if(LLVMPrintModuleToFile(self.module, file_c.ptr(), &error) != 0){
          panic("cant emit file {:?}, err: {:?}", file, CStr::new(error));
        }
        file_c.drop();
    }

    func emit_obj(self, file: str){
        let msg = ptr::null<i8>();
        let code = LLVMVerifyModule(self.module, LLVMVerifierFailureAction::LLVMAbortProcessAction, &msg);

        let file_c = file.cstr();
        let err = ptr::null<i8>();
        let code2 = LLVMTargetMachineEmitToFile(self.tm, self.module, file_c.ptr(), LLVMCodeGenFileType::LLVMObjectFile, &err);
    }

    func make_struct_ty(self, name: str): LLVMOpaqueType*{
        let name_c = name.cstr();
        let ty = LLVMStructCreateNamed(self.ctx, name_c.ptr());
        name_c.drop();
        return ty;
    }

    func getTrue(self): LLVMOpaqueValue*{
        let boolType = LLVMIntTypeInContext(self.ctx, 1);
        return LLVMConstInt(boolType, 1, 0);
    }
    func getFalse(self): LLVMOpaqueValue*{
        let boolType = LLVMIntTypeInContext(self.ctx, 1);
        return LLVMConstInt(boolType, 0, 0);
    }
    func makeInt(self, val: i64, bits: i32): LLVMOpaqueValue*{
        let ty = LLVMIntTypeInContext(self.ctx, bits);
        return LLVMConstInt(ty, val, 0);
    }
    func intTy(self, bits: i32): LLVMOpaqueType*{
      return LLVMIntTypeInContext(self.ctx, bits);
    }
    func intPtr(self, bits: i32): LLVMOpaqueType*{
      return LLVMPointerType(LLVMIntTypeInContext(self.ctx, bits), 0);
    }
    
    func sizeOf(self, ty: LLVMOpaqueType*): i64{
      let target = LLVMGetTargetMachineTarget(self.tm);
      return LLVMSizeOfTypeInBits(target, ty);
    }
    
    func glob_str(self, str: str): LLVMOpaqueValue*{
      let len = str.len() as i32;
      let i8t = LLVMIntTypeInContext(self.ctx, 8);
      let ty = LLVMArrayType(i8t, len + 1);
      let cs = str.cstr();
      let cons = LLVMConstStringInContext(self.ctx, cs.ptr(), len + 1, 1 /* addNull */);
      let res = LLVMAddGlobal(self.module, ty, "".ptr());
      LLVMSetInitializer(res, cons);
      LLVMSetGlobalConstant(res, LLVMBoolTrue());
      LLVMSetLinkage(res, LLVMLinkage::LLVMPrivateLinkage{}.int());
      
      let indices = [ptr::null<LLVMOpaqueValue>(); 2];
      indices[0] = LLVMConstInt(LLVMInt32TypeInContext(self.ctx), 0, 0);
      indices[1] = LLVMConstInt(LLVMInt32TypeInContext(self.ctx), 0, 0);
      res = LLVMConstGEP2(
        LLVMPointerType(LLVMInt8TypeInContext(self.ctx), 0), // Pointer to i8
        res,
        indices.ptr(),
        2
      );
      return res;
    }
}