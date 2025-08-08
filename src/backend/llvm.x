import ast/ast
import std/io

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
struct LLVMOpaqueMetadata;
struct LLVMOpaqueDIBuilder;
struct LLVMOpaqueDbgRecord;
struct LLVMOpaquePassManager;
struct LLVMOpaquePassManagerBuilder;
struct LLVMOpaqueModuleProvider;
struct LLVMOpaqueError;
struct LLVMOpaquePassBuilderOptions;

type LLVMTargetRef = LLVMTarget*;
type LLVMTargetMachineRef = LLVMOpaqueTargetMachine*;
type LLVMValueRef = LLVMOpaqueValue*;
type LLVMTypeRef = LLVMOpaqueType*;
type LLVMDWARFTypeEncoding = i32;

enum LLVMCodeGenOptLevel{
    LLVMCodeGenLevelNone,
    LLVMCodeGenLevelLess,
    LLVMCodeGenLevelDefault,
    LLVMCodeGenLevelAggressive
}
impl LLVMCodeGenOptLevel{
  func int(self): i32{
    return *(self as i32*);
  }
}
//#repr(i32)
enum LLVMRelocMode{
    LLVMRelocDefault,
    LLVMRelocStatic,
    LLVMRelocPIC,
    LLVMRelocDynamicNoPic,
    LLVMRelocROPI,
    LLVMRelocRWPI,
    LLVMRelocROPI_RWPI
}
impl LLVMRelocMode{
  func int(self): i32{
    return *(self as i32*);
  }
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
impl LLVMVerifierFailureAction{
  func int(self): i32{
    return *(self as i32*);
  }
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
impl LLVMRealPredicate{
  func int(self): i32{
    return *(self as i32*);
  }
  func from(s: str): i32{
    if(s.eq("==")) return LLVMRealPredicate::LLVMRealOEQ{}.int();
    if(s.eq(">")) return LLVMRealPredicate::LLVMRealOGT{}.int();
    if(s.eq(">=")) return LLVMRealPredicate::LLVMRealOGE{}.int();
    if(s.eq("<")) return LLVMRealPredicate::LLVMRealOLT{}.int();
    if(s.eq("<=")) return LLVMRealPredicate::LLVMRealOLE{}.int();
    if(s.eq("!=")) return LLVMRealPredicate::LLVMRealONE{}.int();

    if(s.eq("==")) return LLVMRealPredicate::LLVMRealUEQ{}.int();
    if(s.eq(">")) return LLVMRealPredicate::LLVMRealUGT{}.int();
    if(s.eq(">=")) return LLVMRealPredicate::LLVMRealUGE{}.int();
    if(s.eq("<")) return LLVMRealPredicate::LLVMRealULT{}.int();
    if(s.eq("<=")) return LLVMRealPredicate::LLVMRealULE{}.int();
    if(s.eq("!=")) return LLVMRealPredicate::LLVMRealUNE{}.int();
    panic("op='{}'", s);
  }
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
#derive(Debug)
enum LLVMDIFlags{
  LLVMDIFlagZero /*= 0*/,
  LLVMDIFlagPrivate /* = 1*/,
  LLVMDIFlagProtected /* = 2*/,
  LLVMDIFlagPublic /* = 3*/,
  LLVMDIFlagFwdDecl /*= 1 << 2*/,
  LLVMDIFlagAppleBlock /*= 1 << 3*/,
  LLVMDIFlagReservedBit4 /*= 1 << 4*/,
  LLVMDIFlagVirtual /*= 1 << 5*/,
  LLVMDIFlagArtificial /*= 1 << 6*/,
  LLVMDIFlagExplicit /*= 1 << 7*/,
  LLVMDIFlagPrototyped /*= 1 << 8*/,
  LLVMDIFlagObjcClassComplete /*= 1 << 9*/,
  LLVMDIFlagObjectPointer /*= 1 << 10*/,
  LLVMDIFlagVector /*= 1 << 11*/,
  LLVMDIFlagStaticMember /*= 1 << 12*/,
  LLVMDIFlagLValueReference /*= 1 << 13*/,
  LLVMDIFlagRValueReference /*= 1 << 14*/,
  LLVMDIFlagReserved /*= 1 << 15*/,
  LLVMDIFlagSingleInheritance /*= 1 << 16*/,
  LLVMDIFlagMultipleInheritance /*= 2 << 16*/,
  LLVMDIFlagVirtualInheritance /*= 3 << 16*/,
  LLVMDIFlagIntroducedVirtual /*= 1 << 18*/,
  LLVMDIFlagBitField /*= 1 << 19*/,
  LLVMDIFlagNoReturn /*= 1 << 20*/,
  LLVMDIFlagTypePassByValue /*= 1 << 22*/,
  LLVMDIFlagTypePassByReference /*= 1 << 23*/,
  LLVMDIFlagEnumClass /*= 1 << 24*/,
  LLVMDIFlagFixedEnum /*= 1 << 24*//*LLVMDIFlagEnumClass*/, // Deprecated.
  LLVMDIFlagThunk /*= 1 << 25*/,
  LLVMDIFlagNonTrivial /*= 1 << 26*/,
  LLVMDIFlagBigEndian /*= 1 << 27*/,
  LLVMDIFlagLittleEndian /*= 1 << 28*/,
  LLVMDIFlagIndirectVirtualBase /* = (1 << 2) | (1 << 5)*/,
  LLVMDIFlagAccessibility /* = LLVMDIFlagPrivate | LLVMDIFlagProtected |
                            LLVMDIFlagPublic*/,
  LLVMDIFlagPtrToMemberRep /* = LLVMDIFlagSingleInheritance |
                             LLVMDIFlagMultipleInheritance |
                             LLVMDIFlagVirtualInheritance*/
}
impl LLVMDIFlags{
  func int(self): i32{
    match self{
      LLVMDIFlagZero => return 0,
      LLVMDIFlagArtificial => return 1 << 6,
      LLVMDIFlagObjectPointer => return 1 << 10,
      _ => panic("{:?}")
    }
  }
}

enum LLVMDWARFSourceLanguage{
  LLVMDWARFSourceLanguageC89,
  LLVMDWARFSourceLanguageC,
  LLVMDWARFSourceLanguageAda83,
  LLVMDWARFSourceLanguageC_plus_plus,
  LLVMDWARFSourceLanguageCobol74,
  LLVMDWARFSourceLanguageCobol85,
  LLVMDWARFSourceLanguageFortran77,
  LLVMDWARFSourceLanguageFortran90,
  LLVMDWARFSourceLanguagePascal83,
  LLVMDWARFSourceLanguageModula2,
  // New in DWARF v3:
  LLVMDWARFSourceLanguageJava,
  LLVMDWARFSourceLanguageC99,
  LLVMDWARFSourceLanguageAda95,
  LLVMDWARFSourceLanguageFortran95,
  LLVMDWARFSourceLanguagePLI,
  LLVMDWARFSourceLanguageObjC,
  LLVMDWARFSourceLanguageObjC_plus_plus,
  LLVMDWARFSourceLanguageUPC,
  LLVMDWARFSourceLanguageD,
  // New in DWARF v4:
  LLVMDWARFSourceLanguagePython,
  // New in DWARF v5:
  LLVMDWARFSourceLanguageOpenCL,
  LLVMDWARFSourceLanguageGo,
  LLVMDWARFSourceLanguageModula3,
  LLVMDWARFSourceLanguageHaskell,
  LLVMDWARFSourceLanguageC_plus_plus_03,
  LLVMDWARFSourceLanguageC_plus_plus_11,
  LLVMDWARFSourceLanguageOCaml,
  LLVMDWARFSourceLanguageRust,
  LLVMDWARFSourceLanguageC11,
  LLVMDWARFSourceLanguageSwift,
  LLVMDWARFSourceLanguageJulia,
  LLVMDWARFSourceLanguageDylan,
  LLVMDWARFSourceLanguageC_plus_plus_14,
  LLVMDWARFSourceLanguageFortran03,
  LLVMDWARFSourceLanguageFortran08,
  LLVMDWARFSourceLanguageRenderScript,
  LLVMDWARFSourceLanguageBLISS,
  LLVMDWARFSourceLanguageKotlin,
  LLVMDWARFSourceLanguageZig,
  LLVMDWARFSourceLanguageCrystal,
  LLVMDWARFSourceLanguageC_plus_plus_17,
  LLVMDWARFSourceLanguageC_plus_plus_20,
  LLVMDWARFSourceLanguageC17,
  LLVMDWARFSourceLanguageFortran18,
  LLVMDWARFSourceLanguageAda2005,
  LLVMDWARFSourceLanguageAda2012,
  LLVMDWARFSourceLanguageHIP,
  LLVMDWARFSourceLanguageAssembly,
  LLVMDWARFSourceLanguageC_sharp,
  LLVMDWARFSourceLanguageMojo,
  LLVMDWARFSourceLanguageGLSL,
  LLVMDWARFSourceLanguageGLSL_ES,
  LLVMDWARFSourceLanguageHLSL,
  LLVMDWARFSourceLanguageOpenCL_CPP,
  LLVMDWARFSourceLanguageCPP_for_OpenCL,
  LLVMDWARFSourceLanguageSYCL,
  LLVMDWARFSourceLanguageRuby,
  LLVMDWARFSourceLanguageMove,
  LLVMDWARFSourceLanguageHylo,
  LLVMDWARFSourceLanguageMetal,
 
  // Vendor extensions:
  LLVMDWARFSourceLanguageMips_Assembler,
  LLVMDWARFSourceLanguageGOOGLE_RenderScript,
  LLVMDWARFSourceLanguageBORLAND_Delphi
}
impl LLVMDWARFSourceLanguage{
  func int(self): i32{
    return *(self as i32*);
  }
}

enum LLVMDWARFEmissionKind{
    LLVMDWARFEmissionNone /* = 0*/,
    LLVMDWARFEmissionFull,
    LLVMDWARFEmissionLineTablesOnly
}
impl LLVMDWARFEmissionKind{
  func int(self): i32{
    return *(self as i32*);
  }
}
enum DISPFlags{
  SPFlagZero /* = 0*/,
  SPFlagVirtual /* = 1*/,
  SPFlagPureVirtual /* = 2*/,
  SPFlagLocalToUnit /*= (1 << 2)*/,
  SPFlagDefinition /*= (1 << 3)*/,
  SPFlagOptimized /*= (1 << 4)*/,
  SPFlagPure /*= (1 << 5)*/,
  SPFlagElemental /*= (1 << 6)*/,
  SPFlagRecursive /*= (1 << 7)*/,
  SPFlagMainSubprogram /*= (1 << 8)*/,
  SPFlagDeleted /*= (1 << 9)*/,
  SPFlagObjCDirect /*= (1 << 11)*/,
  SPFlagLargest /*= (1 << 11)*/,
  SPFlagNonvirtual /* = DISPFlags::SPFlagZero*/,
  SPFlagVirtuality /* = DISPFlags::SPFlagVirtual | DISPFlags::SPFlagPureVirtual*/,
}
impl DISPFlags{
  func int(self): i32{
    match self{
      DISPFlags::SPFlagZero => return 0,
      DISPFlags::SPFlagDefinition => return 1 << 3,
      DISPFlags::SPFlagMainSubprogram => return 1 << 8,
      _ => panic("todo"),
    }
  }
}


const LLVMDWARFTypeEncoding_Address       = 0x01;
const LLVMDWARFTypeEncoding_Boolean       = 0x02;
const LLVMDWARFTypeEncoding_ComplexFloat  = 0x03;
const LLVMDWARFTypeEncoding_Float         = 0x04;
const LLVMDWARFTypeEncoding_Signed        = 0x05;
const LLVMDWARFTypeEncoding_SignedChar    = 0x06;
const LLVMDWARFTypeEncoding_Unsigned      = 0x07;
const LLVMDWARFTypeEncoding_UnsignedChar  = 0x08;


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
  func LLVMCreateTargetMachine(T: LLVMTarget*, Triple: i8*, CPU: i8*, Features: i8*, Level: i32/*LLVMCodeGenOptLevel*/, Reloc: i32/*LLVMRelocMode*/, CodeModel: LLVMCodeModel): LLVMOpaqueTargetMachine*;
  func LLVMTargetMachineOptionsSetCPU(Options: LLVMOpaqueTargetMachineOptions*, CPU: i8*);
  func LLVMTargetMachineOptionsSetFeatures(Options: LLVMOpaqueTargetMachineOptions*, Features: i8*);
  func LLVMTargetMachineOptionsSetABI(Options: LLVMOpaqueTargetMachineOptions*, ABI: i8*);
  func LLVMTargetMachineOptionsSetCodeGenOptLevel(Options: LLVMOpaqueTargetMachineOptions*, Level: i32/*LLVMCodeGenOptLevel*/);
  func LLVMTargetMachineOptionsSetRelocMode(Options: LLVMOpaqueTargetMachineOptions*, Reloc: i32 /*LLVMRelocMode*/);
  func LLVMTargetMachineOptionsSetCodeModel(Options: LLVMOpaqueTargetMachineOptions*, CodeModel: LLVMCodeModel);
  func LLVMGetTargetMachineCPU(T: LLVMOpaqueTargetMachine*): i8*;
  func LLVMGetTargetMachineTarget(tm: LLVMOpaqueTargetMachine*): LLVMTarget*;
  func LLVMSetModuleDataLayout(m: LLVMOpaqueModule*, DL: LLVMOpaqueTargetData*);
  func LLVMGetModuleDataLayout(m: LLVMOpaqueModule*): LLVMOpaqueTargetData*;
  func LLVMOffsetOfElement(trg: LLVMOpaqueTargetData*, ty: LLVMOpaqueType*, elem: i32): i64;

  //ctx, module, func
  func LLVMContextCreate(): LLVMOpaqueContext*;
  func LLVMContextDispose(c: LLVMOpaqueContext*);
  func LLVMModuleCreateWithNameInContext(name: i8*, c: LLVMOpaqueContext*): LLVMOpaqueModule*;
  func LLVMDisposeModule(m: LLVMOpaqueModule*);
  func LLVMSetTarget(m: LLVMOpaqueModule*, triple: i8*);
  func LLVMSetDataLayout(m: LLVMOpaqueModule*, DataLayoutStr: i8*);
  
  func LLVMCreateTargetDataLayout(T: LLVMOpaqueTargetMachine*): LLVMOpaqueTargetData*;
  func LLVMDumpModule(m: LLVMOpaqueModule*);
  func LLVMPrintModuleToFile(m: LLVMOpaqueModule*, Filename: i8*, ErrorMessage: i8**): i32;
  func LLVMVerifyModule(m: LLVMOpaqueModule*, action: LLVMVerifierFailureAction, msg: i8**): i32;
  func LLVMVerifyFunction(fn: LLVMOpaqueValue*, act: i32/*LLVMVerifierFailureAction*/): i32 /*LLVMBool*/;
  func LLVMTargetMachineEmitToFile (T: LLVMOpaqueTargetMachine*, M: LLVMOpaqueModule*, Filename: i8*, codegen: LLVMCodeGenFileType, ErrorMessage: i8**): i32;
  func LLVMAddFunction(m: LLVMOpaqueModule*, name: i8*, ft: LLVMOpaqueType*): LLVMOpaqueValue*;
  func LLVMSetFunctionCallConv(fn: LLVMOpaqueValue*, cc: i32);
  func LLVMGetParam(fn: LLVMOpaqueValue*, idx: i32): LLVMOpaqueValue*;

  //core
  func LLVMCreatePassManager(): LLVMOpaquePassManager*;
  func LLVMCreateFunctionPassManagerForModule(m: LLVMOpaqueModule*): LLVMOpaquePassManager*;
  func LLVMCreateFunctionPassManager(mp: LLVMOpaqueModuleProvider*): LLVMOpaquePassManager*;
  func LLVMRunPassManager(pm: LLVMOpaquePassManager*, m: LLVMOpaqueModule*): i32/*LLVMBool*/;
  func LLVMInitializeFunctionPassManager (pm: LLVMOpaquePassManager*): i32/*LLVMBool*/;
  func LLVMDisposePassManager(pm: LLVMOpaquePassManager*);
  // func LLVMPassManagerBuilderCreate(): LLVMOpaquePassManagerBuilder*;
  // //OptLevel, 0 = -O0, 1 = -O1, 2 = -O2, 3 = -O3
  // func LLVMPassManagerBuilderSetOptLevel(pmb: LLVMOpaquePassManagerBuilder*, OptLevel: u32);
  // func LLVMPassManagerBuilderUseInlinerWithThreshold(pmb: LLVMOpaquePassManagerBuilder*, Threshold: u32);
  // func LLVMPassManagerBuilderPopulateModulePassManager(pmb: LLVMOpaquePassManagerBuilder*, pm: LLVMOpaquePassManager*);
  // func LLVMPassManagerBuilderDispose(pmb: LLVMOpaquePassManagerBuilder*);

  //new pass manager
  func LLVMRunPasses(m: LLVMOpaqueModule*, Passes: i8*, TM: LLVMOpaqueTargetMachine*, Options: LLVMOpaquePassBuilderOptions*): LLVMOpaqueError*;
  func LLVMRunPassesOnFunction (f: LLVMOpaqueValue*, Passes: i8*, TM: LLVMOpaqueTargetMachine*, Options: LLVMOpaquePassBuilderOptions*): LLVMOpaqueError*;
  func LLVMCreatePassBuilderOptions(): LLVMOpaquePassBuilderOptions*;
  func LLVMPassBuilderOptionsSetVerifyEach(opt: LLVMOpaquePassBuilderOptions*, verify: LLVMBool);
  func LLVMPassBuilderOptionsSetAAPipeline(opt: LLVMOpaquePassBuilderOptions*, AAPipeline: i8*);
  func LLVMPassBuilderOptionsSetLoopInterleaving(Options: LLVMOpaquePassBuilderOptions*, LoopInterleaving: LLVMBool);
  func LLVMPassBuilderOptionsSetLoopVectorization(Options: LLVMOpaquePassBuilderOptions*, LoopVectorization: LLVMBool);
  func LLVMPassBuilderOptionsSetSLPVectorization(Options: LLVMOpaquePassBuilderOptions*, SLPVectorization: LLVMBool);
  func LLVMPassBuilderOptionsSetLoopUnrolling(Options: LLVMOpaquePassBuilderOptions*, LoopUnrolling: LLVMBool);
  func LLVMPassBuilderOptionsSetForgetAllSCEVInLoopUnroll (Options: LLVMOpaquePassBuilderOptions*, ForgetAllSCEVInLoopUnroll: LLVMBool);
  func LLVMPassBuilderOptionsSetLicmMssaOptCap(Options: LLVMOpaquePassBuilderOptions*, LicmMssaOptCap: u32);
  func LLVMPassBuilderOptionsSetLicmMssaNoAccForPromotionCap (Options: LLVMOpaquePassBuilderOptions*, LicmMssaNoAccForPromotionCap: u32);
  func LLVMPassBuilderOptionsSetCallGraphProfile(Options: LLVMOpaquePassBuilderOptions*, CallGraphProfile: LLVMBool);
  func LLVMPassBuilderOptionsSetMergeFunctions(Options: LLVMOpaquePassBuilderOptions*, MergeFunctions: LLVMBool);
  func LLVMPassBuilderOptionsSetInlinerThreshold(Options: LLVMOpaquePassBuilderOptions*, Threshold: i32);
  func LLVMDisposePassBuilderOptions(pbo: LLVMOpaquePassBuilderOptions*);
  func LLVMGetErrorMessage(err: LLVMOpaqueError*): i8*;
  func LLVMDisposeErrorMessage(msg: i8*);
  
  //types
  func LLVMPointerType(elem: LLVMOpaqueType*, addrspace: i32): LLVMOpaqueType*;
  func LLVMPointerTypeInContext(ctx: LLVMOpaqueContext*, addrspace: i32): LLVMOpaqueType*;
  func LLVMArrayType(elem: LLVMOpaqueType*, count: i32): LLVMOpaqueType*;
  func LLVMStructCreateNamed(C: LLVMOpaqueContext*, Name: i8*): LLVMOpaqueType*;
  func LLVMStructTypeInContext(C: LLVMOpaqueContext*, ElementTypes: LLVMOpaqueType**, ElementCount: i32, Packed: LLVMBool): LLVMOpaqueType*;
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
  func LLVMSizeOfTypeInBits(trg: LLVMOpaqueTargetData*, ty: LLVMOpaqueType*): i64;
  func LLVMGetIntTypeWidth(ty: LLVMOpaqueType*): i32;
  func LLVMTypeOf(val: LLVMOpaqueValue*): LLVMOpaqueType*;
  func LLVMFunctionType(ret: LLVMOpaqueType*, params: LLVMOpaqueType**, cnt: i32, vararg: LLVMBool): LLVMOpaqueType*;
  func LLVMGetTypeKind(ty: LLVMOpaqueType*): /*LLVMTypeKind*/i32;
  func LLVMGetElementType(ty: LLVMOpaqueType*): LLVMOpaqueType*;

  //global
  func LLVMAddGlobal(md: LLVMOpaqueModule*, ty: LLVMOpaqueType*, name: i8*): LLVMOpaqueValue*;
  func LLVMConstStringInContext(C: LLVMOpaqueContext*, str: i8*, len: i32, nll: LLVMBool): LLVMOpaqueValue*;
  func LLVMConstStructInContext(C: LLVMOpaqueContext*, ConstantVals: LLVMOpaqueValue**, Count: i32, Packed: LLVMBool): LLVMOpaqueValue*;
  func LLVMConstNull(ty: LLVMOpaqueType*): LLVMOpaqueValue*;
  func LLVMConstArray(ElementTy: LLVMOpaqueType*, ConstantVals: LLVMOpaqueValue**, Length: i32): LLVMOpaqueValue*;
  func LLVMSetInitializer(var: LLVMOpaqueValue*, val: LLVMOpaqueValue*);
  func LLVMSetGlobalConstant(var: LLVMOpaqueValue*, iscons: LLVMBool);
  func LLVMSetLinkage(val: LLVMOpaqueValue*, linkage: i32 /*LLVMLinkage*/);
  func LLVMSetSection(Global: LLVMOpaqueValue*, Section: i8*);
  
  //basic block
  func LLVMCreateBasicBlockInContext(B: LLVMOpaqueBuilder*, name: i8*): LLVMOpaqueBasicBlock*;
  func LLVMAppendBasicBlockInContext(C: LLVMOpaqueContext*, fn: LLVMOpaqueValue*, name: i8*): LLVMOpaqueBasicBlock*;
  func LLVMPositionBuilderAtEnd(B: LLVMOpaqueBuilder*, bb: LLVMOpaqueBasicBlock*);
  func LLVMGetInsertBlock(B: LLVMOpaqueBuilder*): LLVMOpaqueBasicBlock*;
  func LLVMDeleteBasicBlock(bb: LLVMOpaqueBasicBlock*);
  
  //builder
  func LLVMCreateBuilderInContext(C: LLVMOpaqueContext*): LLVMOpaqueBuilder*;
  func LLVMSetValueName2(val: LLVMOpaqueValue*, name: i8*, len: i64 /*size_t*/);
  func LLVMCreateTypeAttribute(c: LLVMOpaqueContext*, kind: i32, ty: LLVMOpaqueType*): LLVMOpaqueAttributeRef*;
  func LLVMGetEnumAttributeKindForName(name: i8*, len: i64): i32;
  func LLVMAddAttributeAtIndex(f: LLVMOpaqueValue*, idx: i32, attr: LLVMOpaqueAttributeRef*);
    
  func LLVMConstGEP2(ty: LLVMOpaqueType*, val: LLVMOpaqueValue*, idx: LLVMOpaqueValue**, cnt: i32): LLVMOpaqueValue*;
  func LLVMBuildGEP2(B: LLVMOpaqueBuilder*, ty: LLVMOpaqueType*, ptr: LLVMOpaqueValue*, idx: LLVMOpaqueValue**, cnt: i32, name: i8*): LLVMOpaqueValue*;
  func LLVMBuildInBoundsGEP2(B: LLVMOpaqueBuilder*, ty: LLVMOpaqueType*, ptr: LLVMOpaqueValue*, idx: LLVMOpaqueValue**, cnt: i32, name: i8*): LLVMOpaqueValue*;
  func LLVMBuildStructGEP2(B: LLVMOpaqueBuilder*, ty: LLVMOpaqueType*, ptr: LLVMOpaqueValue*, idx: i32, name: i8*): LLVMOpaqueValue*;
  func LLVMBuildICmp(B: LLVMOpaqueBuilder*, Op: i32, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
  func LLVMBuildFCmp(B: LLVMOpaqueBuilder*, Op: i32 /*LLVMRealPredicate*/, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
  func LLVMBuildBr(B: LLVMOpaqueBuilder*, bb: LLVMOpaqueBasicBlock*): LLVMOpaqueValue*;
  func LLVMBuildCondBr(B: LLVMOpaqueBuilder*, cond: LLVMOpaqueValue*, then: LLVMOpaqueBasicBlock*, els: LLVMOpaqueBasicBlock*): LLVMOpaqueValue*;
  func LLVMBuildRetVoid(B: LLVMOpaqueBuilder*): LLVMOpaqueValue*;
  func LLVMBuildRet(B: LLVMOpaqueBuilder*, val: LLVMOpaqueValue*): LLVMOpaqueValue*;
  func LLVMConstInt(IntTy: LLVMOpaqueType*, N: i64, SignExtend: i32): LLVMOpaqueValue*;
  func LLVMConstReal(ty: LLVMOpaqueType*, N: f64): LLVMOpaqueValue*;
  func LLVMBuildAlloca(B: LLVMOpaqueBuilder*, ty: LLVMOpaqueType*, name: i8*): LLVMOpaqueValue*;
  func LLVMBuildStore(B: LLVMOpaqueBuilder*, val: LLVMOpaqueValue*, ptr: LLVMOpaqueValue*): LLVMOpaqueValue*;
  func LLVMBuildLoad2(B: LLVMOpaqueBuilder*, ty: LLVMOpaqueType*, ptr: LLVMOpaqueValue*, name: i8*): LLVMOpaqueValue*;
  func LLVMBuildMemCpy(B: LLVMOpaqueBuilder*, dst: LLVMOpaqueValue*, da: i32, src: LLVMOpaqueValue*, sa: i32, size: LLVMOpaqueValue*): LLVMOpaqueValue*;
  func LLVMBuildCall2(B: LLVMOpaqueBuilder*, ft: LLVMOpaqueType*, Fn: LLVMOpaqueValue*, args: LLVMOpaqueValue**, NumArgs: i32, name: i8*): LLVMOpaqueValue*;
  func LLVMBuildSwitch(B: LLVMOpaqueBuilder*, val: LLVMOpaqueValue*, Else: LLVMOpaqueBasicBlock*, numcases: i32): LLVMOpaqueValue*;
  func LLVMAddCase(Switch: LLVMOpaqueValue*, OnVal: LLVMOpaqueValue*, Dest: LLVMOpaqueBasicBlock*);
  func LLVMBuildUnreachable(B: LLVMOpaqueBuilder*): LLVMOpaqueValue*;
  func LLVMBuildPhi(B: LLVMOpaqueBuilder*, Ty: LLVMOpaqueType*, Name: i8*): LLVMOpaqueValue*;
  func LLVMAddIncoming(phi: LLVMOpaqueValue*, vals: LLVMOpaqueValue**, bbs: LLVMOpaqueBasicBlock**, count: i32);
  func LLVMBuildPtrToInt(B: LLVMOpaqueBuilder*, val: LLVMOpaqueValue*, dest: LLVMOpaqueType*, name: i8*): LLVMOpaqueValue*;
  func LLVMBuildSExt(B: LLVMOpaqueBuilder*, val: LLVMOpaqueValue*, dest: LLVMOpaqueType*, name: i8*): LLVMOpaqueValue*;
  func LLVMBuildZExt(B: LLVMOpaqueBuilder*, val: LLVMOpaqueValue*, dest: LLVMOpaqueType*, name: i8*): LLVMOpaqueValue*;
  func LLVMBuildFPExt(B: LLVMOpaqueBuilder*, val: LLVMOpaqueValue*, dest: LLVMOpaqueType*, name: i8*): LLVMOpaqueValue*;
  func LLVMBuildTrunc(B: LLVMOpaqueBuilder*, val: LLVMOpaqueValue*, dest: LLVMOpaqueType*, name: i8*): LLVMOpaqueValue*;
  func LLVMBuildFPTrunc(B: LLVMOpaqueBuilder*, val: LLVMOpaqueValue*, dest: LLVMOpaqueType*, name: i8*): LLVMOpaqueValue*;
  func LLVMBuildUIToFP(B: LLVMOpaqueBuilder*, val: LLVMOpaqueValue*, dest: LLVMOpaqueType*, name: i8*): LLVMOpaqueValue*;
  func LLVMBuildSIToFP(B: LLVMOpaqueBuilder*, val: LLVMOpaqueValue*, dest: LLVMOpaqueType*, name: i8*): LLVMOpaqueValue*;
  func LLVMBuildFPToUI(B: LLVMOpaqueBuilder*, val: LLVMOpaqueValue*, dest: LLVMOpaqueType*, name: i8*): LLVMOpaqueValue*;
  func LLVMBuildFPToSI(B: LLVMOpaqueBuilder*, val: LLVMOpaqueValue*, dest: LLVMOpaqueType*, name: i8*): LLVMOpaqueValue*;
  
  //infix
  func LLVMBuildAdd(B: LLVMOpaqueBuilder*, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
  func LLVMBuildFAdd(B: LLVMOpaqueBuilder*, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
  func LLVMBuildNSWAdd(B: LLVMOpaqueBuilder*, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
  func LLVMBuildSub(B: LLVMOpaqueBuilder*, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
  func LLVMBuildFSub(B: LLVMOpaqueBuilder*, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
  func LLVMBuildNSWSub(B: LLVMOpaqueBuilder*, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
  func LLVMBuildMul(B: LLVMOpaqueBuilder*, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
  func LLVMBuildFMul(B: LLVMOpaqueBuilder*, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
  func LLVMBuildNSWMul(B: LLVMOpaqueBuilder*, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
  func LLVMBuildFDiv(B: LLVMOpaqueBuilder*, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
  func LLVMBuildSDiv(B: LLVMOpaqueBuilder*, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
  func LLVMBuildUDiv(B: LLVMOpaqueBuilder*, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
  func LLVMBuildFRem(B: LLVMOpaqueBuilder*, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
  func LLVMBuildURem(B: LLVMOpaqueBuilder*, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
  func LLVMBuildSRem(B: LLVMOpaqueBuilder*, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
  func LLVMBuildAnd(B: LLVMOpaqueBuilder*, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
  func LLVMBuildOr(B: LLVMOpaqueBuilder*, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
  func LLVMBuildXor(B: LLVMOpaqueBuilder*, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
  func LLVMBuildShl(B: LLVMOpaqueBuilder*, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
  func LLVMBuildAShr(B: LLVMOpaqueBuilder*, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
  
  func LLVMBuildFNeg(B: LLVMOpaqueBuilder*, val: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
  func LLVMBuildNeg(B: LLVMOpaqueBuilder*, val: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
  func LLVMBuildNot(B: LLVMOpaqueBuilder*, val: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
}

//debug
extern{
  func LLVMCreateDIBuilder(M: LLVMOpaqueModule*): LLVMOpaqueDIBuilder*;
  func LLVMGetSubprogram(fn: LLVMOpaqueValue*): LLVMOpaqueMetadata*;
  func LLVMDITypeGetSizeInBits(ty: LLVMOpaqueMetadata*): i64;
  
  func LLVMDIBuilderCreateSubroutineType(B: LLVMOpaqueDIBuilder*, file: LLVMOpaqueMetadata*, params: LLVMOpaqueMetadata**, cnt: i32, flags: i32/*LLVMDIFlags*/): LLVMOpaqueMetadata*;
  func LLVMDIBuilderCreateFunction( B: LLVMOpaqueDIBuilder*,
                                    scope: LLVMOpaqueMetadata*,
                                    name: i8*, namelen: i64,
                                    link: i8*, linkagelen: i64,
                                    file: LLVMOpaqueMetadata*,
                                    line: i32,
                                    ty: LLVMOpaqueMetadata*,
                                    IsLocalToUnit: LLVMBool,
                                    IsDefinition: LLVMBool,
                                    ScopeLine: i32,
                                    Flags: i32 /*LLVMDIFlags*/,
                                    IsOptimized: LLVMBool): LLVMOpaqueMetadata*;

  func LLVMDIBuilderCreateParameterVariable(Builder: LLVMOpaqueDIBuilder*,
                                            Scope: LLVMOpaqueMetadata*,
                                            Name: i8*,
                                            NameLen: i64,
                                            ArgNo: i32,
                                            File: LLVMOpaqueMetadata*,
                                            LineNo: i32,
                                            Ty: LLVMOpaqueMetadata*,
                                            AlwaysPreserve: LLVMBool,
                                            Flags: i32/*LLVMDIFlags */
                                            ): LLVMOpaqueMetadata*;

  func LLVMDIBuilderCreateBasicType(B: LLVMOpaqueDIBuilder*,
                                    name: i8*, namelen: i64, bits: i64,
                                    encoding: LLVMDWARFTypeEncoding,
                                    flags: i32/*LLVMDIFlags*/): LLVMOpaqueMetadata*;

  func LLVMDIBuilderCreateCompileUnit(Builder: LLVMOpaqueDIBuilder*,
		  	                              Lang: i32/*LLVMDWARFSourceLanguage*/,
                                      FileRef: LLVMOpaqueMetadata*,
                                      Producer: i8*,
                                      ProducerLen: i64,
                                      isOptimized: LLVMBool,
                                      Flags: i8*,
                                      FlagsLen: i64,
                                      RuntimeVer: i32,
                                      SplitName: i8*,
                                      SplitNameLen: i64,
                                      Kind: i32/*LLVMDWARFEmissionKind*/,
                                      DWOId: i32,
                                      SplitDebugInlining: LLVMBool,
                                      DebugInfoForProfiling: LLVMBool,
                                      SysRoot: i8*,
                                      SysRootLen: i64,
                                      SDK: i8*,
                                      SDKLen: i64): LLVMOpaqueMetadata*;

  func LLVMDIBuilderCreateFile( Builder: LLVMOpaqueDIBuilder*,
                                Filename: i8*,
                                FilenameLen: i64,
                                Directory: i8*,
                                DirectoryLen: i64): LLVMOpaqueMetadata*;
  func LLVMDIBuilderCreateLexicalBlock(builder: LLVMOpaqueDIBuilder*, scope: LLVMOpaqueMetadata*, file: LLVMOpaqueMetadata*, line: i32, column: i32): LLVMOpaqueMetadata*;
  func LLVMDIBuilderCreateGlobalVariableExpression( Builder: LLVMOpaqueDIBuilder*,
                                                    Scope: LLVMOpaqueMetadata*,
                                                    Name: i8*,
                                                    NameLen: i64,
                                                    Linkage: i8*,
                                                    LinkLen: i64, 
                                                    File: LLVMOpaqueMetadata*,
                                                    LineNo: i32,
                                                    Ty: LLVMOpaqueMetadata*,
                                                    LocalToUnit: LLVMBool,
                                                    Expr: LLVMOpaqueMetadata*,
                                                    Decl: LLVMOpaqueMetadata*,
                                                    AlignInBits: i32): LLVMOpaqueMetadata*;
  func LLVMDIBuilderFinalizeSubprogram(B: LLVMOpaqueDIBuilder*, sp: LLVMOpaqueMetadata*);
  func LLVMDIBuilderCreateDebugLocation(ctx: LLVMOpaqueContext*, line: i32, column: i32, sp: LLVMOpaqueMetadata*, inlined: LLVMOpaqueMetadata*): LLVMOpaqueMetadata*;
  func LLVMSetCurrentDebugLocation2(B: LLVMOpaqueBuilder*, loc: LLVMOpaqueMetadata*);
  func LLVMSetSubprogram(Func: LLVMOpaqueValue*, SP: LLVMOpaqueMetadata*);
  func LLVMDIBuilderCreateObjectPointerType(Builder: LLVMOpaqueDIBuilder*, Type: LLVMOpaqueMetadata*, Implicit: LLVMBool): LLVMOpaqueMetadata*;

  func LLVMDIBuilderCreatePointerType(Builder: LLVMOpaqueDIBuilder*,
                                  PointeeTy: LLVMOpaqueMetadata*,
                                  SizeInBits: i64,
                                  AlignInBits: i64,
                                  AddressSpace: i32,
                                  Name: i8*,
                                  NameLen: i64
                                  ): LLVMOpaqueMetadata*;

  func LLVMDIBuilderCreateArrayType(Builder: LLVMOpaqueDIBuilder*, Size: i64, AlignInBits: i32, Ty: LLVMOpaqueMetadata*, Subscripts: LLVMOpaqueMetadata**, NumSubscripts: i32): LLVMOpaqueMetadata*;
  func LLVMDIBuilderGetOrCreateSubrange(Builder: LLVMOpaqueDIBuilder*, LowerBound: i64, Count: i64): LLVMOpaqueMetadata*;

  func LLVMDIBuilderCreateMemberType(Builder: LLVMOpaqueDIBuilder*,
                                Scope: LLVMOpaqueMetadata*,
                                Name: i8*,
                                NameLen: i64,
                                File: LLVMOpaqueMetadata*,
                                LineNo: i32,
                                SizeInBits: i64,
                                AlignInBits: i32,
                                OffsetInBits: i64,
                                Flags: i32/*LLVMDIFlags*/,
                                Ty: LLVMOpaqueMetadata*
                                ): LLVMOpaqueMetadata*;
  func LLVMDIBuilderCreateStructType(Builder: LLVMOpaqueDIBuilder*,
                                    Scope: LLVMOpaqueMetadata*,
                                    Name: i8*,
                                    NameLen: i64,
                                    File: LLVMOpaqueMetadata*,
                                    LineNumber: i32,
                                    SizeInBits: i64,
                                    AlignInBits: i32,
                                    Flags: i32 /* LLVMDIFlags*/,
                                    DerivedFrom: LLVMOpaqueMetadata*,
                                    Elements: LLVMOpaqueMetadata**,
                                    NumElements: i32,
                                    RunTimeLang: i32,
                                    VTableHolder: LLVMOpaqueMetadata*,
                                    UniqueId: i8*,
                                    UniqueIdLen: i64
                                    ): LLVMOpaqueMetadata*;
  func LLVMDIBuilderInsertDeclareRecordAtEnd(Builder: LLVMOpaqueDIBuilder*,
                                            Storage: LLVMOpaqueValue*,
                                            VarInfo: LLVMOpaqueMetadata*,
                                            Expr: LLVMOpaqueMetadata*,
                                            DebugLoc: LLVMOpaqueMetadata*,
                                            Block: LLVMOpaqueBasicBlock*
                                            ): LLVMOpaqueDbgRecord*;                                    
  func LLVMDIBuilderCreateExpression(Builder: LLVMOpaqueDIBuilder*, Addr: i64*, Length: i64): LLVMOpaqueMetadata*;

  func LLVMDIBuilderCreateAutoVariable(Builder: LLVMOpaqueDIBuilder*,
                                        Scope: LLVMOpaqueMetadata*,
                                        Name: i8*,
                                        NameLen: i64,
                                        File: LLVMOpaqueMetadata*,
                                        LineNo: i32,
                                        Ty: LLVMOpaqueMetadata*,
                                        AlwaysPreserve: LLVMBool,
                                        Flags: i32/*LLVMDIFlags*/,
                                        AlignInBits: i32 
                                        ): LLVMOpaqueMetadata*;
  
  func LLVMDIBuilderCreateEnumerationType(Builder: LLVMOpaqueDIBuilder*,
                                          Scope: LLVMOpaqueMetadata*,
                                          Name: i8*,
                                          NameLen: i64,
                                          File: LLVMOpaqueMetadata*,
                                          LineNumber: i32,
                                          SizeInBits: i64,
                                          AlignInBits: i32,
                                          Elements: LLVMOpaqueMetadata**,
                                          NumElements: i32,
                                          ClassTy: LLVMOpaqueMetadata* 
                                          ): LLVMOpaqueMetadata*;

  func LLVMDIBuilderCreateEnumerator(Builder: LLVMOpaqueDIBuilder*,
                                    Name: i8*,
                                    NameLen: i64,
                                    Value: i64,
                                    IsUnsigned: LLVMBool
                                    ): LLVMOpaqueMetadata*;

  func LLVMTemporaryMDNode(Ctx: LLVMOpaqueContext*, Data: LLVMOpaqueMetadata*, NumElements: i64): LLVMOpaqueMetadata*;                                    
  func LLVMMetadataReplaceAllUsesWith(TempTrgetMetadata: LLVMOpaqueMetadata*, Replacement: LLVMOpaqueMetadata*);
  func LLVMDisposeTemporaryMDNode(TempNode: LLVMOpaqueMetadata*);

  func LLVMDIBuilderCreateReplaceableCompositeType(Builder: LLVMOpaqueDIBuilder*,
                                              Tag: i32,
                                              Name: i8*,
                                              NameLen: i64,
                                              Scope: LLVMOpaqueMetadata*,
                                              File: LLVMOpaqueMetadata*,
                                              Line: i32,
                                              RuntimeLang: i32,
                                              SizeInBits: i64,
                                              AlignInBits: i32,
                                              Flags: i32/*LLVMDIFlags */,
                                              UniqueIdentifier: i8*,
                                              UniqueIdentifierLen: i64
                                              ): LLVMOpaqueMetadata*;
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
      LLVMTargetMachineOptionsSetRelocMode(opt, LLVMRelocMode::LLVMRelocPIC{}.int());
      let tm = LLVMCreateTargetMachineWithOptions(target, target_triple.ptr(), opt);        

      let ctx = LLVMContextCreate();
      let name = module_name.cstr();
      let md = LLVMModuleCreateWithNameInContext(name.ptr(), ctx);
      LLVMSetTarget(md, target_triple.ptr());
      let dl = LLVMCreateTargetDataLayout(tm);
      LLVMSetModuleDataLayout(md, dl);

      let builder = LLVMCreateBuilderInContext(ctx);

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
  func makeFloat(self, val: f64): LLVMOpaqueValue*{
    let ty = LLVMFloatTypeInContext(self.ctx);
    return LLVMConstReal(ty, val);
  }
  func makeDouble(self, val: f64): LLVMOpaqueValue*{
    let ty = LLVMDoubleTypeInContext(self.ctx);
    return LLVMConstReal(ty, val);
  }    
  func intTy(self, bits: i32): LLVMOpaqueType*{
    return LLVMIntTypeInContext(self.ctx, bits);
  }
  func intPtr(self, bits: i32): LLVMOpaqueType*{
    return LLVMPointerType(LLVMIntTypeInContext(self.ctx, bits), 0);
  }

  func sizeOf(self, val: LLVMOpaqueValue*): i64{
    let ty = LLVMTypeOf(val);
    return self.sizeOf(ty);
  }
  
  func sizeOf(self, ty: LLVMOpaqueType*): i64{
    let dl = LLVMGetModuleDataLayout(self.module);
    return LLVMSizeOfTypeInBits(dl, ty);
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
    cs.drop();
    return res;
  }

  func make_stdout(self): LLVMOpaqueValue*{
      let ty = LLVMPointerTypeInContext(self.ctx, 0);
      let res = LLVMAddGlobal(self.module, ty, "stdout".ptr());
      LLVMSetLinkage(res, LLVMLinkage::LLVMExternalLinkage{}.int());
      return res;
  }

  func gep_ptr(self, type: LLVMOpaqueType*, ptr: LLVMOpaqueValue*, i1: LLVMOpaqueValue*): LLVMOpaqueValue*{
    let idx = [i1 as LLVMOpaqueValue*];
    return LLVMBuildGEP2(self.builder, type, ptr, idx.ptr(), 1, "".ptr());
  }

  func gep_arr(self, type: LLVMOpaqueType*, ptr: LLVMOpaqueValue*, i1: i32, i2: i32): LLVMOpaqueValue*{
    return self.gep_arr(type, ptr, self.makeInt(i1, 64), self.makeInt(i2, 64));
  }

  func gep_arr(self, type: LLVMOpaqueType*, ptr: LLVMOpaqueValue*, i1: LLVMOpaqueValue*, i2: LLVMOpaqueValue*): LLVMOpaqueValue*{
    let args = [i1, i2];
    return LLVMBuildInBoundsGEP2(self.builder, type, ptr, args.ptr(), 2, "".ptr());
  }

  func isPtr(self, val: LLVMOpaqueValue*): bool{
    let ty = LLVMTypeOf(val);
    return LLVMGetTypeKind(ty) == LLVMTypeKind::LLVMPointerTypeKind{}.int();
  }
  
  func isPtr(ty: LLVMOpaqueType*): bool{
    return LLVMGetTypeKind(ty) == LLVMTypeKind::LLVMPointerTypeKind{}.int();
  }

  func loadPtr(self, val: LLVMOpaqueValue*): LLVMOpaqueValue*{
    return LLVMBuildLoad2(self.builder, LLVMPointerTypeInContext(self.ctx, 0), val, "".ptr());
  }

  func verify_func(self, proto: LLVMOpaqueValue*){
    let vrf = LLVMVerifyFunction(proto, LLVMVerifierFailureAction::LLVMPrintMessageAction{}.int());
    if(vrf == 1){
      LLVMDumpValue(proto);
      panic("");
    }
  }

  // func optimize_module0(self){
  //   let pass_manager = LLVMCreatePassManager();

  //   // Create the PassManagerBuilder
  //   let builder = LLVMPassManagerBuilderCreate();
  //   //Set optimization level: 0-3 (similar to clang -O0 to -O3)
  //   LLVMPassManagerBuilderSetOptLevel(builder, 2u32); // -O2

  //   // Optional: inlining threshold and loop unrolling
  //   LLVMPassManagerBuilderUseInlinerWithThreshold(builder, 225u32);

  //   // Populate the pass manager with standard optimizations
  //   LLVMPassManagerBuilderPopulateModulePassManager(builder, pass_manager);

  //   // Run optimizations on the module
  //   LLVMRunPassManager(pass_manager, self.module);

  //   // Cleanup
  //   LLVMPassManagerBuilderDispose(builder);
  //   LLVMDisposePassManager(pass_manager);    
  // }

  func optimize_module_newpm(self, level: String*){
    if(level.eq("-O0")) return;
    let pipeline = if(level.eq("-O1") || level.eq("-O")){
      "default<O1>"
    }
    else if(level.eq("-O2")){
      "default<O2>"
    }
    else if(level.eq("-O3")){
      "default<O3>"
    }else{
      panic("invalid optimization level '{}'", level);
    };
    let opt = LLVMCreatePassBuilderOptions();
    LLVMPassBuilderOptionsSetLoopInterleaving(opt, LLVMBoolTrue());
    LLVMPassBuilderOptionsSetLoopVectorization(opt, LLVMBoolTrue());
    LLVMPassBuilderOptionsSetSLPVectorization(opt, LLVMBoolTrue());
    LLVMPassBuilderOptionsSetLoopUnrolling(opt, LLVMBoolTrue());
    LLVMPassBuilderOptionsSetForgetAllSCEVInLoopUnroll(opt, LLVMBoolTrue());
    LLVMPassBuilderOptionsSetCallGraphProfile(opt, LLVMBoolTrue());
    LLVMPassBuilderOptionsSetMergeFunctions(opt, LLVMBoolTrue());
    let err = LLVMRunPasses(self.module, pipeline .ptr(), self.tm, opt);
    if(err as u64 != 0){
      let msg = LLVMGetErrorMessage(err);
      printf("LLVMRunPasses failed msg=%s\n", msg);
      LLVMDisposeErrorMessage(msg);
      panic("");
    }
    LLVMDisposePassBuilderOptions(opt);
  }
}