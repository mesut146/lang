

struct vector_Type;
struct vector_Value;
struct vector_Constant;//std::vector<llvm::Constant*>
struct vector_Metadata;

struct Target;
struct TargetMachine;
struct LLVMModule;
struct LLVMContext;
struct IRBuilder;
struct StructType;
struct llvm_Type;
struct PointerType;
struct ArrayType;
struct llvm_FunctionType;
struct LinkageTypes;
struct Function;
struct Argument;
struct AttrKind;
struct Value;
struct BasicBlock;
struct PHINode;
struct SwitchInst;
struct Constant;
struct ConstantInt;
struct GlobalVariable;
struct DIGlobalVariableExpression;

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
struct StructLayout;

extern{
    func setModule(md: LLVMModule*);
    func setCtx(ctx: LLVMContext*);
    func setBuilder(b: IRBuilder*);
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

    func createTargetMachine(triple: i8*): TargetMachine*;

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

    func make_module(name: i8*, tm: TargetMachine*, triple: i8*): LLVMModule*;
    func make_ctx(): LLVMContext*;
    func make_builder(): IRBuilder*;
    func destroy_ctx();
    func destroy_llvm(tm: TargetMachine*);
    func emit_llvm(out: i8*);
    func emit_object(name: i8*, tm: TargetMachine*, triple: i8*);

    func init_dbg();
    func createFile(file: i8*, dir: i8*): DIFile*;
    func createCompileUnit(lang: i32, file: DIFile*): DICompileUnit*;
    func SetCurrentDebugLocation(scope: DIScope*, line: i32, pos: i32);
    func createObjectPointerType(type: DIType*): DIType*;
    func createSubroutineType(tys: vector_Metadata*): DISubroutineType*;
    func make_spflags(is_main: bool): i32;
    func getFunction(name: i8*): Function*;
    func setSection(f: Function *, sec: i8*);
    func createFunction(scope: DIScope*, name: i8*, linkage_name: i8*, file: DIFile*, line: i32, ft: DISubroutineType*, spflags: i32): DISubprogram*;
    func setSubprogram(f: Function*, sp: DISubprogram*);
    func finalizeSubprogram(sp: DISubprogram*);
    func createLexicalBlock(scope: DIScope*, file: DIFile*, line: i32, col: i32): DILexicalBlock*;
    func createParameterVariable(scope: DIScope*, name: i8*, idx: i32, file: DIFile*, line: i32, type: DIType*, preserve: bool, is_self: bool): DILocalVariable*;
    func createAutoVariable(scope :DIScope*, name: i8*, file: DIFile *, line: i32, ty: DIType*): DILocalVariable*;
    func DILocation_get(scope: DIScope*, line: i32, pos: i32): DILocation*;
    func createExpression(): DIExpression*;
    func insertDeclare(value: Value*, var_info: DILocalVariable*, expr: DIExpression*, loc: DILocation*, bb: BasicBlock*);
    func createStructType(scope: DIScope*, name: i8*, file: DIFile*, line: i32, size: i64, elems: vector_Metadata*): DICompositeType*;
    func createStructType_ident(scope: DIScope*, name: i8*, file: DIFile*, line: i32, size: i64, elems: vector_Metadata*, ident: i8*): DICompositeType*;
    func get_di_null(): DIType*;
    func get_null_scope(): DIScope*;
    func createBasicType(name: i8*, size: i64, enco: i32): DIType*;
    func DW_ATE_boolean(): i32;
    func DW_ATE_signed(): i32;
    func DW_ATE_unsigned(): i32;
    func DW_ATE_float(): i32;
    func createPointerType(elem: DIType*, size: i64): DIType*;
    func getOrCreateSubrange(lo: i64, count: i64): Metadata*;
    func createArrayType(size: i64, ty: DIType*, elems: vector_Metadata*): DIType*;
    func make_di_flags(artificial: bool): u32;
    func createMemberType(scope: DIScope*, name: i8*, file: DIFile*, line: i32, size: i64, off: i64, flags: u32, ty: DIType*): DIDerivedType*;
    func DIType_getSizeInBits(ty: DIType*): i64;
    func getStructLayout(st: StructType*): StructLayout*;
    func DataLayout_getTypeSizeInBits(ty: llvm_Type*): i64;
    func getElementOffsetInBits(sl: StructLayout*, idx: i32): i64;
    func replaceElements(st: DICompositeType*, elems: vector_Metadata*);
    func createVariantPart(scope: DIScope*, name: i8*, file: DIFile*, line: i32, size: i64, disc: DIDerivedType*, elems: vector_Metadata*): DICompositeType*;
    func createVariantMemberType(scope: DIScope *, name: i8*, file: DIFile *, line: i32, size: i64, off: i64, idx: i32, ty: DIType *): DIDerivedType*;
    //glob dbg
    func createGlobalVariableExpression(scope: DIScope*, name: i8*, lname: i8*, file :DIFile*, line: i32, type: DIType*): DIGlobalVariableExpression*;
    func addDebugInfo(gv: GlobalVariable*, gve: DIGlobalVariableExpression*);
    func replaceGlobalVariables(cu: DICompileUnit*, vec: vector_Metadata*);
    func get_dwarf_cpp(): i32;
    func get_dwarf_cpp20(): i32;
    func get_dwarf_c(): i32;
    func get_dwarf_c17(): i32;
    func get_dwarf_rust(): i32;
    func get_dwarf_zig(): i32;
    func get_dwarf_swift(): i32;

    func make_struct_ty(name: i8*): StructType*;
    func make_struct_ty2(name: i8*, elems: vector_Type*): StructType*;
    func make_struct_ty_noname(elems: vector_Type*): StructType*;
    func setBody(st: StructType*, elems: vector_Type*);
    func getSizeInBits(st: StructType*): i32;
    func StructType_getNumElements(st: StructType*): i32;
    func getPrimitiveSizeInBits(st: llvm_Type*): i32;
    func getInt(bits: i32): llvm_Type*;
    func makeInt(val: i64, bits: i32): ConstantInt*;
    func makeFloat(val: f32): Constant*;
    func makeDouble(val: f64): Constant*;
    func getFloatTy(): llvm_Type*;
    func getDoubleTy(): llvm_Type*;
    func getPointerTo(type: llvm_Type*): PointerType*;
    func getArrTy(elem: llvm_Type*, size: i32): ArrayType*; 
    func getVoidTy(): llvm_Type*;
    func isVoidTy(type: llvm_Type*): bool;
    func isPointerTy(type: llvm_Type*): bool;
    func getPtr(): llvm_Type*;
    func Value_isPointerTy(val: Value*): bool;
    func ConstantPointerNull_get(ty: PointerType*): Value*;
    func CreateFPCast(val: Value*, trg: llvm_Type*): Value*;
    func CreateSIToFP(val: Value*, trg: llvm_Type*): Value*;
    func CreateUIToFP(val: Value*, trg: llvm_Type*): Value*;
    func CreateFPToSI(val: Value*, trg: llvm_Type*): Value*;
    func CreateFPToUI(val: Value*, trg: llvm_Type*): Value*;
    func CreateFPExt(val: Value*, trg: llvm_Type*): Value*;
    func CreateFPTrunc(val: Value*, trg: llvm_Type*): Value*;
    
    func make_ft(ret: llvm_Type*, args: vector_Type*, vararg: bool): llvm_FunctionType*;
    func ext(): i32;
    func odr(): i32;
    func internal(): i32;
    func make_func(fr: llvm_FunctionType*, l: i32, name: i8*): Function*;
    func get_arg(f: Function*, i: i32): Argument*;
    func Argument_setname(a: Argument*, name: i8*);
    func Argument_setsret(a: Argument*, ty: llvm_Type*): i32;
    func setCallingConv(f: Function*);
    func Function_print(f: Function*);
    func verifyFunction(f: Function*): bool;
    func verifyModule(): bool;
    
    func make_stdout(): Value*;
    
    func create_bb(): BasicBlock*;
    func create_bb_named(name: i8*): BasicBlock*;
    func create_bb2(f: Function*): BasicBlock*;
    func create_bb2_named(f: Function*, name: i8*): BasicBlock*;
    func SetInsertPoint(bb: BasicBlock*);
    func GetInsertBlock(): BasicBlock*;
    func func_insert(f: Function*, bb: BasicBlock*);
    
    func Value_setName(v: Value*, name: i8*);
    func Value_getType(val: Value*): llvm_Type*;
    //func Value_dump(v: Value*);
    //func Type_dump(t: llvm_Type*);
    func CreateAlloca(ty: llvm_Type*): Value*;
    func CreateStore(val: Value*, ptr: Value*);
    func CreateMemCpy(trg: Value*, src: Value*, size: i64);
    func CreateRet(val: Value*);
    func CreateRetVoid();
    func CreateSExt(val: Value*, type: llvm_Type*): Value*;
    func CreateZExt(val: Value*, type: llvm_Type*): Value*;
    func CreateTrunc(val: Value*, type: llvm_Type*): Value*;
    func CreatePtrToInt(val: Value*, type: llvm_Type*): Value*;
    func CreateStructGEP(ptr: Value*, idx: i32, type: llvm_Type*): Value*;
    func CreateInBoundsGEP(type: llvm_Type *, ptr: Value*, idx: vector_Value*): Value*;
    func CreateGEP(type: llvm_Type*, ptr: Value*, idx: vector_Value*): Value*;
    func CreateGlobalStringPtr(s: i8*): Value*;
    func CreateGlobalString(s: i8*): GlobalVariable*;
    func CreateCall(f: Function*, args: vector_Value*): Value*;
    func CreateCall_ft(ft: llvm_FunctionType*, val: Value*, args: vector_Value*): Value*;
    func CreateUnreachable();
    func CreateCondBr(cond: Value*, true_bb: BasicBlock*, false_bb: BasicBlock*);
    func CreateBr(bb: BasicBlock*);
    func CreateCmp(op: i32, l: Value*, r: Value*): Value*;
    func get_comp_op(op: i8*): i32;
    func get_comp_op_float(op: i8*): i32;
    func CreateLoad(type: llvm_Type*, val: Value*): Value*;
    func getTrue(): Value*;
    func getFalse(): Value*;
    func CreatePHI(type: llvm_Type*, cnt: i32): PHINode*;
    func phi_addIncoming(phi: PHINode*, val: Value*, bb: BasicBlock*);
    func make_global(name: i8*, ty: llvm_Type*, init: Constant*): GlobalVariable*;
    func make_global_linkage(name: i8*, ty: llvm_Type*, init: Constant*, linkage: i32): GlobalVariable*;
    func ConstantStruct_get(ty: StructType*): Constant*;
    func ConstantStruct_get_elems(ty: StructType*, elems: vector_Constant*): Constant*;
    func ConstantArray_get(ty: ArrayType*, elems: vector_Constant*): Constant*;
    func GlobalValue_ext(): i32;
    func GlobalValue_appending(): i32;
    func CreateSwitch(cond: Value*, def_bb: BasicBlock*, num_cases: i32): SwitchInst*;
    func SwitchInst_addCase(node: SwitchInst*, OnVal: ConstantInt*, Dest: BasicBlock*);

    func CreateNSWAdd(l: Value*, r: Value*): Value*;
    func CreateFAdd(l: Value*, r: Value*): Value*;
    func CreateAdd(l: Value*, r: Value*): Value*;
    func CreateNSWSub(l: Value*, r: Value*): Value*;
    func CreateSub(l: Value*, r: Value*): Value*;
    func CreateFSub(l: Value*, r: Value*): Value*;
    func CreateNSWMul(l: Value*, r: Value*): Value*;
    func CreateFMul(l: Value*, r: Value*): Value*;
    func CreateSDiv(l: Value*, r: Value*): Value*;
    func CreateFDiv(l: Value*, r: Value*): Value*;
    func CreateSRem(l: Value*, r: Value*): Value*;
    func CreateFRem(l: Value*, r: Value*): Value*;
    func CreateAnd(l: Value*, r: Value*): Value*;
    func CreateOr(l: Value*, r: Value*): Value*;
    func CreateXor(l: Value*, r: Value*): Value*;
    func CreateShl(l: Value*, r: Value*): Value*;
    func CreateAShr(l: Value*, r: Value*): Value*;
    func CreateNeg(l: Value*): Value*;
    func CreateFNeg(l: Value*): Value*;

    func get_last_write_time(path: i8*): i64;
    //func set_as_executable(path: i8*);
}

/*func getDefaultTargetTriple2(): CStr{
    let arr = [0u8; 100];
    let ptr = arr.ptr();
    let len = getDefaultTargetTriple(ptr as i8*);
    return CStr::new(arr[0..len + 1]);
}*/