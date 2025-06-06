import parser/bridge
import ast/ast

struct LLVMOpaqueContext;
struct LLVMOpaqueModule;
struct LLVMTarget;
struct LLVMOpaqueTargetMachine;
struct LLVMOpaqueTargetMachineOptions;
struct LLVMOpaqueTargetData;
struct LLVMOpaqueBuilder;
struct LLVMOpaqueValue;
struct LLVMOpaqueType;

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
    func LLVMInitializeAllDisassemblers();

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

    
    //types
    func LLVMPointerType(elem: LLVMOpaqueType*, addrspace: i32): LLVMOpaqueType*;
    func LLVMArrayType(elem: LLVMOpaqueType*, count: u32): LLVMOpaqueType*;
    func LLVMStructCreateNamed(C: LLVMOpaqueContext*, Name: i8*): LLVMOpaqueType*;
    func LLVMStructSetBody(StructTy: LLVMOpaqueType*, ElementTypes: LLVMOpaqueType**, ElementCount: i32, Packed: i32);
    func LLVMVoidTypeInContext(c: LLVMOpaqueContext*): LLVMOpaqueType*;
    func LLVMFloatTypeInContext(c: LLVMOpaqueContext*): LLVMOpaqueType*;
    func LLVMDoubleTypeInContext(c: LLVMOpaqueContext*): LLVMOpaqueType*;
    func LLVMIntTypeInContext(c: LLVMOpaqueContext*, bits: i32): LLVMOpaqueType*;
    func LLVMDumpValue(val: LLVMOpaqueValue*);
    func LLVMPrintValueToString(val: LLVMOpaqueValue*): i8*;
    func LLVMPrintTypeToString(val: LLVMOpaqueType*): i8*;
    func LLVMTypeOf(val: LLVMOpaqueValue*): LLVMOpaqueType*;

    //builder
    func LLVMCreateBuilderInContext(C: LLVMOpaqueContext*): LLVMOpaqueBuilder*;
    func LLVMAddGlobal(md: LLVMOpaqueModule*, ty: LLVMOpaqueType*, name: i8*): LLVMValueRef;
    func LLVMBuildICmp(B: LLVMOpaqueBuilder*, Op: i32, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
    func LLVMBuildFCmp(B: LLVMOpaqueBuilder*, Op: LLVMRealPredicate, LHS: LLVMOpaqueValue*, RHS: LLVMOpaqueValue*, Name: i8*): LLVMOpaqueValue*;
    func LLVMConstInt(IntTy: LLVMOpaqueType*, N: i64, SignExtend: i32): LLVMOpaqueValue*;
    
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
        setModule(md as LLVMModule*);
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
        LLVMPrintModuleToFile(self.module, file_c.ptr(), &error);
        file_c.drop();
    }

    func emit_obj(self, file: str){
        let msg = ptr::null<i8>();
        let code = LLVMVerifyModule(self.module, LLVMVerifierFailureAction::LLVMAbortProcessAction, &msg);

        let file_c = file.cstr();
        let err = ptr::null<i8>();
        let code2 = LLVMTargetMachineEmitToFile(self.tm, self.module, file_c.ptr(), LLVMCodeGenFileType::LLVMObjectFile, &err);
    }

    func make_struct_ty_new(self, name: str): LLVMOpaqueType*{
        let name_c = name.cstr();
        let ty = LLVMStructCreateNamed(self.ctx, name_c.ptr());
        name_c.drop();
        return ty;
    }
    func make_struct_ty_new(self, name: str, elems: List<Type>*): LLVMOpaqueType*{
        let name_c = name.cstr();
        let ty = LLVMStructCreateNamed(self.ctx, name_c.ptr());
        //LLVMStructSetBody(ty, elemptr, elems.len() as i32, 0);
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
}