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

    func make_struct_ty(name: i8*): StructType*;
    func make_struct_ty2(name: i8*, elems: vector*): StructType*;
    func setBody(st: StructType*, elems: vector*);
    func getSizeInBits(st: StructType*): i32;
    func getInt(bits: i32): llvm_Type*;
    func getPointerTo(type: llvm_Type*): llvm_Type*;
    func getArrTy(elem: llvm_Type*, size: i32): ArrayType*; 
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