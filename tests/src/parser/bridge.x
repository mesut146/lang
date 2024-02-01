struct vector;
struct Target;
struct TargetMachine;
struct Module;
struct LLVMContext;
struct IRBuilder;
struct StructType;
struct llvm_Type;
struct PointerType;
struct ArrayType;
struct FunctionType;
struct LinkageTypes;
struct Function;
struct Argument;
struct AttrKind;
struct Value;
struct BasicBlock;

extern{
    func make_vec(): vector*;
    func vec_push(vec: vector*, elem: llvm_Type*);

    func getDefaultTargetTriple(ptr: i8*): i32;
    func InitializeAllTargetInfos();
    func InitializeAllTargets();
    func InitializeAllTargetMCs();
    func InitializeAllAsmParsers();
    func InitializeAllAsmPrinters();
    func lookupTarget(triple: i8*): Target*;
    func createTargetMachine(triple: i8*): TargetMachine*;
    func make_module(name: i8*, tm: TargetMachine*, triple: i8*): Module*;
    func make_ctx(): LLVMContext*;
    func make_builder(): IRBuilder*;
    func emit_llvm(out: i8*);

    func make_struct_ty(name: i8*): StructType*;
    func make_struct_ty2(name: i8*, elems: vector*): StructType*;
    func setBody(st: StructType*, elems: vector*);
    func getSizeInBits(st: StructType*): i32;
    func getPrimitiveSizeInBits(st: llvm_Type*): i32;
    func getInt(bits: i32): llvm_Type*;
    func makeInt(val: i64, bits: i32): Value*;
    func getPointerTo(type: llvm_Type*): llvm_Type*;
    func getArrTy(elem: llvm_Type*, size: i32): ArrayType*; 
    func getVoidTy(): llvm_Type*;
    
    func make_ft(ret: llvm_Type*, args: vector*, vararg: bool): FunctionType*;
    func ext(): i32;
    func odr(): i32;
    func make_func(fr: FunctionType*, l: i32, name: i8*): Function*;
    func get_arg(f: Function*, i: i32): Argument*;
    func arg_attr(a: Argument* , at: i32*);
    func get_sret(): i32;
    func setCallingConv(f: Function*);
    func verifyFunction(f: Function*): bool;
    
    func make_stdout(): Value*;
    
    func create_bb2(f: Function*): BasicBlock*;
    func SetInsertPoint(bb: BasicBlock *);
    
    func Value_setName(v: Value*, name: i8*);
    func Value_getType(val: Value*): llvm_Type*;
    func CreateAlloca(ty: llvm_Type*): Value*;
    func CreateStore(val: Value*, ptr: Value*);
    func CreateMemCpy(trg: Value*, src: Value*, size: i64);
    func CreateRet(val: Value*);
    func CreateRetVoid();
    func CreateSExt(val: Value*, type: llvm_Type*): Value*;
    func CreateZExt(val: Value*, type: llvm_Type*): Value*;
    func CreateTrunc(val: Value*, type: llvm_Type*): Value*;
    func CreateStructGEP(ptr: Value*, idx: i32, type: llvm_Type *): Value*;
}

func getDefaultTargetTriple2(): String{
    let arr = [0i8; 100];
    let ptr = arr.ptr();
    let len = getDefaultTargetTriple(ptr);
    return String::new(arr[0..len]);
}


func bridge_test(){
    let arr = [0i8; 100];
    let ptr = arr.ptr();
    let len = getDefaultTargetTriple(ptr);
    let str = String::new(arr[0..len]);
    print("target=%s\n", ptr);
}