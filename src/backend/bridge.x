import std/io

struct vector_Type;
struct vector_Value;
struct vector_Constant;//std::vector<llvm::Constant*>
struct vector_Metadata;

struct Target;
struct TargetMachine;
struct LLVMModule;
struct LLVMContext;
struct IRBuilder;
struct StructLayout;
struct StructType;
struct llvm_Type;//todo make LLVMType
struct PointerType;
struct ArrayType;
struct IntegerType;
struct llvm_FunctionType;
//struct LinkageTypes;
struct Function;
struct Argument;
//struct AttrKind;
struct Value;
struct BasicBlock;
struct PHINode;
struct SwitchInst;
struct Constant;
struct ConstantInt;
struct GlobalVariable;

struct DIBuilder;
struct DICompileUnit;
struct DIFile;
struct DISubprogram;
struct DISubroutineType;
struct DIType;
struct DICompositeType;
struct DIDerivedType;
struct DIScope;
struct DILexicalBlock;
struct Metadata;
struct DILocalVariable;
struct DIExpression;
struct DILocation;
struct DIGlobalVariableExpression;

enum RelocMode{
  Static, PIC_, DynamicNoPIC, ROPI, RWPI, ROPI_RWPI
}
impl RelocMode{
  func int(self): i32{
    return *(self as i32*);
  }
}

extern{
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
}

extern{
    func vector_Type_new(): vector_Type*;
    func vector_Type_push(vec: vector_Type*, elem: llvm_Type*);
    func vector_Type_delete(vec: vector_Type*);
    
    func Function_delete(f: Function*);
    
    func vector_Value_new(): vector_Value*;
    func vector_Value_push(vec: vector_Value*, elem: Value*);
    func vector_Value_delete(vec: vector_Value*);

    func vector_Constant_new(): vector_Constant*;
    func vector_Constant_push(vec: vector_Constant*, elem: Constant*);
    func vector_Constant_delete(vec: vector_Constant*);

    func vector_Metadata_new(): vector_Metadata*;
    func vector_Metadata_push(vec: vector_Metadata*, elem: Metadata*);
    func vector_Metadata_delete(vec: vector_Metadata*);

    //func printDefaultTargetAndDetectedCPU();
    func getDefaultTargetTriple(ptr: i8*): i32;
    func InitializeAllTargets();
    func InitializeAllTargetInfos();
    func InitializeAllTargetMCs();
    func InitializeAllAsmParsers();
    func InitializeAllAsmPrinters();
    func lookupTarget(triple: i8*): Target*;

    func createTargetMachine(triple: i8*, reloc: i32): TargetMachine*;

    func llvm_InitializeX86TargetInfo();
    func llvm_InitializeX86Target();
    func llvm_InitializeX86TargetMC();
    func llvm_InitializeX86AsmParser();
    func llvm_InitializeX86AsmPrinter();
    func llvm_InitializeAArch64TargetInfo();
    func llvm_InitializeAArch64Target();
    func llvm_InitializeAArch64TargetMC();
    func llvm_InitializeAArch64AsmParser();
    func llvm_InitializeAArch64AsmPrinter();

    func LLVMContext_new(): LLVMContext*;
    func Module_new(name: i8*, ctx: LLVMContext*, tm: TargetMachine*, triple: i8*): LLVMModule*;
    func verifyModule(md: LLVMModule*): bool;
    func IRBuilder_new(ctx: LLVMContext*): IRBuilder*;
    func destroy_ctx();
    func destroy_llvm(tm: TargetMachine*);
    //func emit_llvm(out: i8*);
    func Module_emit(md: LLVMModule*, file: i8*): i8*;
    func emit_object(md: LLVMModule*, file: i8*, tm: TargetMachine*);
    
    //dbg enums
    func get_dwarf_cpp(): i32;
    func get_dwarf_cpp20(): i32;
    func get_dwarf_c(): i32;
    func get_dwarf_c17(): i32;
    func get_dwarf_rust(): i32;
    func get_dwarf_zig(): i32;
    func get_dwarf_swift(): i32;
    func SPFlagMainSubprogram(): i32;
    func SPFlagDefinition(): i32;
    func DIFlags_FlagZero(): i32;
    func DIFlags_FlagArtificial(): i32;
    func DIFlags_FlagObjectPointer(): i32;
    func DW_ATE_boolean(): i32;
    func DW_ATE_signed(): i32;
    func DW_ATE_unsigned(): i32;
    func DW_ATE_float(): i32;
    
    func DIBuilder_new(module: LLVMModule*): DIBuilder*;
    func createFile(dib: DIBuilder*, file: i8*, dir: i8*): DIFile*;
    func createCompileUnit(dib: DIBuilder*, lang: i32, file: DIFile*, producer: i8*): DICompileUnit*;
    func SetCurrentDebugLocation(ib: IRBuilder*, scope: DIScope*, line: i32, pos: i32);
    func DILocation_get(dib: DIBuilder*, scope: DIScope*, line: i32, pos: i32): DILocation*;
    
    func createFunction(dib: DIBuilder*, scope: DIScope*, name: i8*, linkage_name: i8*, file: DIFile*, line: i32, ft: DISubroutineType*, spflags: i32): DISubprogram*;
    func setSubprogram(f: Function*, sp: DISubprogram*);
    func finalizeSubprogram(dib: DIBuilder*, sp: DISubprogram*);
    func createLexicalBlock(dib: DIBuilder*, scope: DIScope*, file: DIFile*, line: i32, col: i32): DILexicalBlock*;
    
    func createParameterVariable(dib: DIBuilder*, scope: DIScope*, name: i8*, idx: i32, file: DIFile*, line: i32, type: DIType*, preserve: bool, flags: i32): DILocalVariable*;
    func createAutoVariable(dib: DIBuilder*, scope :DIScope*, name: i8*, file: DIFile *, line: i32, ty: DIType*): DILocalVariable*;
    func insertDeclare(dib: DIBuilder*, value: Value*, var_info: DILocalVariable*, expr: DIExpression*, loc: DILocation*, bb: BasicBlock*);
    func createExpression(dib: DIBuilder*): DIExpression*;
    //types
    func createBasicType(dib: DIBuilder*, name: i8*, size: i64, encoding: i32): DIType*;
    func createPointerType(dib: DIBuilder*, elem: DIType*, size: i64): DIType*;
    func createObjectPointerType(type: DIType*): DIType*;
    func createSubroutineType(dib: DIBuilder*, tys: Metadata**, len: i32): DISubroutineType*;
    func createStructType(dib: DIBuilder*, ctx: LLVMContext*, scope: DIScope*, name: i8*, file: DIFile*, line: i32, size: i64, elems: Metadata**, len: i32): DICompositeType*;
    func createStructType_ident(dib: DIBuilder*, scope: DIScope*, name: i8*, file: DIFile*, line: i32, size: i64, elems: vector_Metadata*, ident: i8*): DICompositeType*;
    func getOrCreateSubrange(dib: DIBuilder*, lo: i64, count: i64): Metadata*;
    func createArrayType(dib: DIBuilder*, size: i64, ty: DIType*, elems: Metadata**, len: i32): DIType*;
    func make_di_flags(artificial: bool): u32;
    func createMemberType(dib: DIBuilder*, scope: DIScope*, name: i8*, file: DIFile*, line: i32, size: i64, off: i64, flags: i32, ty: DIType*): DIDerivedType*;
    func createVariantPart(dib: DIBuilder*, scope: DIScope*, name: i8*, file: DIFile*, line: i32, size: i64, disc: DIDerivedType*, elems: Metadata**, len: i32): DICompositeType*;
    func createVariantMemberType(dib: DIBuilder*, scope: DIScope *, name: i8*, file: DIFile *, line: i32, size: i64, off: i64, idx: i32, ty: DIType *): DIDerivedType*;
    
    func DIType_getSizeInBits(ty: DIType*): i64;
    func getStructLayout(st: StructType*): StructLayout*;
    func DataLayout_getTypeSizeInBits(md: LLVMModule*, ty: llvm_Type*): i64;
    func getElementOffsetInBits(sl: StructLayout*, idx: i32): i64;
    func replaceElements(st: DICompositeType*, elems: Metadata**, len: i32);
    
    //glob dbg
    func createGlobalVariableExpression(dib: DIBuilder*, scope: DIScope*, name: i8*, lname: i8*, file :DIFile*, line: i32, type: DIType*): DIGlobalVariableExpression*;
    func addDebugInfo(gv: GlobalVariable*, gve: DIGlobalVariableExpression*);
    func replaceGlobalVariables(cu: DICompileUnit*, vec: vector_Metadata*);

    func make_struct_ty(ctx: LLVMContext*, name: i8*, elems: llvm_Type**, len: i32): StructType*;
    func make_struct_ty2(ctx: LLVMContext*, name: i8*): StructType*;
    func make_struct_ty_noname(ctx: LLVMContext*, elems: vector_Type*): StructType*;
    func StructType_setBody(st: StructType*, elems: llvm_Type**, len: i32);
    func getSizeInBits(st: StructType*): i32;
    func StructType_getNumElements(st: StructType*): i32;
    func getPrimitiveSizeInBits(st: llvm_Type*): i32;
    func intTy(ctx: LLVMContext*, bits: i32): llvm_Type*;
    func ConstantInt_get(ty: IntegerType*, val: i64, isSigned: bool): ConstantInt*;
    func makeInt(ctx: LLVMContext*, val: i64, bits: i32): ConstantInt*;
    func makeFloat(ctx: LLVMContext*, val: f32): Constant*;
    func makeDouble(ctx: LLVMContext*, val: f64): Constant*;
    func getFloatTy(ctx: LLVMContext*): llvm_Type*;
    func getDoubleTy(ctx: LLVMContext*): llvm_Type*;
    func getPointerTo(type: llvm_Type*): PointerType*;
    func ArrayType_get(elem: llvm_Type*, size: i32): ArrayType*; 
    func getVoidTy(builder: IRBuilder*): llvm_Type*;
    func isVoidTy(type: llvm_Type*): bool;
    func isPointerTy(type: llvm_Type*): bool;
    func getPtr(ctx: LLVMContext*): llvm_Type*;//todo PointerType
    func Value_isPointerTy(val: Value*): bool;
    func ConstantPointerNull_get(ty: PointerType*): Value*;
    func CreateFPCast(builder: IRBuilder*, val: Value*, trg: llvm_Type*): Value*;
    func CreateSIToFP(builder: IRBuilder*, val: Value*, trg: llvm_Type*): Value*;
    func CreateUIToFP(builder: IRBuilder*, val: Value*, trg: llvm_Type*): Value*;
    func CreateFPToSI(builder: IRBuilder*, val: Value*, trg: llvm_Type*): Value*;
    func CreateFPToUI(builder: IRBuilder*, val: Value*, trg: llvm_Type*): Value*;
    func CreateFPExt(builder: IRBuilder*, val: Value*, trg: llvm_Type*): Value*;
    func CreateFPTrunc(builder: IRBuilder*, val: Value*, trg: llvm_Type*): Value*;
    
    func make_ft(ret: llvm_Type*, args: llvm_Type**, len: i32, vararg: bool): llvm_FunctionType*;
    func ext(): i32;
    func odr(): i32;
    func internal(): i32;
    func make_func(ft: llvm_FunctionType*, l: i32, name: i8*, module: LLVMModule*): Function*;
    func getFunction(name: i8*): Function*;
    func setSection(f: Function *, sec: i8*);
    func Function_getArg(f: Function*, i: i32): Argument*;
    func Argument_setname(a: Argument*, name: i8*);
    func Argument_setsret(ctx: LLVMContext*, a: Argument*, ty: llvm_Type*): i32;
    func setCallingConv(f: Function*);
    func Function_print(f: Function*);
    func verifyFunction(f: Function*): bool;
    
    func create_bb(ctx: LLVMContext*, name: i8*, f: Function*): BasicBlock*;
    func SetInsertPoint(builder: IRBuilder*, bb: BasicBlock*);
    func GetInsertBlock(builder: IRBuilder*): BasicBlock*;
    func func_insert(f: Function*, bb: BasicBlock*);
    
    func Value_setName(v: Value*, name: i8*);
    func Value_getType(val: Value*): llvm_Type*;
    //func Value_dump(v: Value*);
    //func Type_dump(t: llvm_Type*);
    func CreateAlloca(builder: IRBuilder*, ty: llvm_Type*): Value*;
    func CreateStore(builder: IRBuilder*, val: Value*, ptr: Value*);
    func CreateMemCpy(builder: IRBuilder*, trg: Value*, src: Value*, size: i64);
    func CreateRet(builder: IRBuilder*, val: Value*);
    func CreateRetVoid(builder: IRBuilder*);
    func CreateSExt(builder: IRBuilder*, val: Value*, type: llvm_Type*): Value*;
    func CreateZExt(builder: IRBuilder*, val: Value*, type: llvm_Type*): Value*;
    func CreateTrunc(builder: IRBuilder*, val: Value*, type: llvm_Type*): Value*;
    func CreatePtrToInt(builder: IRBuilder*, val: Value*, type: llvm_Type*): Value*;
    func CreateStructGEP(builder: IRBuilder*, type: llvm_Type*, ptr: Value*, idx: i32): Value*;
    func CreateInBoundsGEP(builder: IRBuilder*, type: llvm_Type *, ptr: Value*, idx: Value**, len: i32): Value*;
    func CreateGEP(builder: IRBuilder*, type: llvm_Type*, ptr: Value*, idx: Value**, len: i32): Value*;
    func CreateGlobalStringPtr(builder: IRBuilder*, s: i8*): Value*;
    func CreateGlobalString(builder: IRBuilder*, s: i8*): GlobalVariable*;
    func CreateCall(builder: IRBuilder*, f: Function*, args: Value**, len: i32): Value*;
    func CreateCall_ft(builder: IRBuilder*, ft: llvm_FunctionType*, val: Value*, args: Value**, len: i32): Value*;
    func CreateUnreachable(builder: IRBuilder*);
    func CreateCondBr(builder: IRBuilder*, cond: Value*, true_bb: BasicBlock*, false_bb: BasicBlock*);
    func CreateBr(builder: IRBuilder*, bb: BasicBlock*);
    func CreateCmp(builder: IRBuilder*, op: i32, l: Value*, r: Value*): Value*;
    func get_comp_op(op: i8*): i32;
    func get_comp_op_float(op: i8*): i32;
    func CreateLoad(builder: IRBuilder*, type: llvm_Type*, val: Value*): Value*;
    func getTrue(builder: IRBuilder*): Value*;
    func getFalse(builder: IRBuilder*): Value*;
    func CreatePHI(builder: IRBuilder*, type: llvm_Type*, cnt: i32): PHINode*;
    func phi_addIncoming(phi: PHINode*, val: Value*, bb: BasicBlock*);
    //globals
    func make_global(module: LLVMModule*, ty: llvm_Type*, init: Constant*, linkage: i32, name: i8*): GlobalVariable*;
    func ConstantAggregateZero_get(ty: llvm_Type*): Constant*;
    func ConstantStruct_get_elems(ty: StructType*, elems: Constant**, len: i32): Constant*;
    func ConstantStruct_getAnon(elems: Constant**, len: i32): Constant*;
    func ConstantStruct_get(ty: StructType*): Constant*;
    func ConstantArray_get(ty: ArrayType*, elems: Constant**, len: i32): Constant*;
    func GlobalValue_ext(): i32;
    func GlobalValue_appending(): i32;
    func CreateSwitch(builder: IRBuilder*, cond: Value*, def_bb: BasicBlock*, num_cases: i32): SwitchInst*;
    func SwitchInst_addCase(node: SwitchInst*, OnVal: ConstantInt*, Dest: BasicBlock*);

    func CreateNSWAdd(builder: IRBuilder*, l: Value*, r: Value*): Value*;
    func CreateFAdd(builder: IRBuilder*, l: Value*, r: Value*): Value*;
    func CreateAdd(builder: IRBuilder*, l: Value*, r: Value*): Value*;
    func CreateNSWSub(builder: IRBuilder*, l: Value*, r: Value*): Value*;
    func CreateSub(builder: IRBuilder*, l: Value*, r: Value*): Value*;
    func CreateFSub(builder: IRBuilder*, l: Value*, r: Value*): Value*;
    func CreateNSWMul(builder: IRBuilder*, l: Value*, r: Value*): Value*;
    func CreateFMul(builder: IRBuilder*, l: Value*, r: Value*): Value*;
    func CreateSDiv(builder: IRBuilder*, l: Value*, r: Value*): Value*;
    func CreateFDiv(builder: IRBuilder*, l: Value*, r: Value*): Value*;
    func CreateSRem(builder: IRBuilder*, l: Value*, r: Value*): Value*;
    func CreateFRem(builder: IRBuilder*, l: Value*, r: Value*): Value*;
    func CreateAnd(builder: IRBuilder*, l: Value*, r: Value*): Value*;
    func CreateOr(builder: IRBuilder*, l: Value*, r: Value*): Value*;
    func CreateXor(builder: IRBuilder*, l: Value*, r: Value*): Value*;
    func CreateShl(builder: IRBuilder*, l: Value*, r: Value*): Value*;
    func CreateAShr(builder: IRBuilder*, l: Value*, r: Value*): Value*;
    func CreateNeg(builder: IRBuilder*, l: Value*): Value*;
    func CreateFNeg(builder: IRBuilder*, l: Value*): Value*;

    func get_last_write_time(path: i8*): i64;
    //func set_as_executable(path: i8*);
}

func getDefaultTargetTriple2(): String{
    let arr = [0u8; 100];
    let ptr = arr.ptr();
    let len = getDefaultTargetTriple(ptr as i8*);
    return String::new(arr[0..len + 1]);
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

struct Emitter2{
    tm: TargetMachine*;
    ctx: LLVMContext*;
    module: LLVMModule*;
    builder: IRBuilder*;
}

impl Emitter2{
  func new(module_name: str): Emitter2{
      LLVMInitializeAllTargetInfos();
      LLVMInitializeAllTargets();
      LLVMInitializeAllTargetMCs();
      LLVMInitializeAllAsmPrinters();
      LLVMInitializeAllAsmParsers();

      let target_triple = getDefaultTargetTriple2().cstr();
      let env_triple = std::getenv("target_triple");
      if(env_triple.is_some()){
          target_triple.drop();
          target_triple = env_triple.unwrap().owned().cstr();
      }

      let tm = createTargetMachine(target_triple.ptr(), RelocMode::PIC_{}.int());  

      let ctx = LLVMContext_new();
      let name = module_name.cstr();
      let md = Module_new(name.ptr(), ctx, tm, target_triple.ptr());

      let builder = IRBuilder_new(ctx);

      name.drop();
      target_triple.drop();
      return Emitter2{tm: tm, ctx: ctx, module: md, builder: builder};
  }

  func make_stdout(self): Value*{
      let ty = getPtr(self.ctx);
      let init = ptr::null<Constant>();
      let res = make_global(self.module, ty, init, ext(), "stdout".ptr());
      return res as Value*;
  }

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
    // let opt = LLVMCreatePassBuilderOptions();
    // LLVMPassBuilderOptionsSetLoopInterleaving(opt, LLVMBoolTrue());
    // LLVMPassBuilderOptionsSetLoopVectorization(opt, LLVMBoolTrue());
    // LLVMPassBuilderOptionsSetSLPVectorization(opt, LLVMBoolTrue());
    // LLVMPassBuilderOptionsSetLoopUnrolling(opt, LLVMBoolTrue());
    // LLVMPassBuilderOptionsSetForgetAllSCEVInLoopUnroll(opt, LLVMBoolTrue());
    // LLVMPassBuilderOptionsSetCallGraphProfile(opt, LLVMBoolTrue());
    // LLVMPassBuilderOptionsSetMergeFunctions(opt, LLVMBoolTrue());
    // let err = LLVMRunPasses(self.module, pipeline .ptr(), self.tm, opt);
    // if(err as u64 != 0){
    //   let msg = LLVMGetErrorMessage(err);
    //   printf("LLVMRunPasses failed msg=%s\n", msg);
    //   LLVMDisposeErrorMessage(msg);
    //   panic("");
    // }
    // LLVMDisposePassBuilderOptions(opt);
  }

  func emit_module(self, file: str){
      let file_c = file.cstr();
      let error: i8* = Module_emit(self.module, file_c.ptr());
      if(error as u64 != 0){
        panic("cant emit file {:?}, err: {:?}", file, CStr::new(error));
      }
      file_c.drop();
  }

  func emit_obj(self, file: str){
      verifyModule(self.module);

      let file_c = file.cstr();
      let err = ptr::null<i8>();
      emit_object(self.module, file_c.ptr(), self.tm);
  }

  func makeInt(self, val: i64, bits: i32): Value*{
    let ty = intTy(self.ctx, bits);
    return ConstantInt_get(ty as IntegerType*, val, true) as Value*;
  }
  func makeFloat(self, val: f32): Value*{
    return makeFloat(self.ctx, val) as Value*;
  }
  func makeDouble(self, val: f64): Value*{
    return makeDouble(self.ctx, val) as Value*;
  } 
  
  func gep_arr(self, type: llvm_Type*, ptr: Value*, i1: Value*, i2: Value*): Value*{
    let args = [i1, i2];
    return CreateInBoundsGEP(self.builder, type, ptr, args.ptr(), 2);
  }
  
  func gep_arr(self, type: llvm_Type*, ptr: Value*, i1: i32, i2: i32): Value*{
    return self.gep_arr(type, ptr, self.makeInt(i1, 64), self.makeInt(i2, 64));
  }

  func gep_ptr(self, type: llvm_Type*, ptr: Value*, i1: Value*): Value*{
    let idx = [i1];
    return CreateGEP(self.builder, type, ptr, idx.ptr(), 1);
  }

  func loadPtr(self, val: Value*): Value*{
    return CreateLoad(self.builder, getPtr(self.ctx), val);
  }

  func sizeOf(self, ty: llvm_Type*): i64{
    return DataLayout_getTypeSizeInBits(self.module, ty);
  }

  func sizeOf(self, val: Value*): i64{
    let ty = Value_getType(val);
    return DataLayout_getTypeSizeInBits(self.module, ty);
  }

  func intPtr(self, bits: i32): llvm_Type*{
    let ty = intTy(self.ctx, bits);
    return getPointerTo(ty) as llvm_Type*;
  }

  func glob_str(self, str: str): Value*{
    let cs = str.cstr();
    let res = CreateGlobalString(self.builder, cs.ptr());
    cs.drop();
    return res as Value*;
  }
}
