import parser/bridge

struct Emitter{
    tm: LLVMOpaqueTargetMachine*;
    ctx: LLVMOpaqueContext*;
    module: LLVMOpaqueModule*;
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
        name.drop();
        target_triple.drop();
        return Emitter{tm: tm, ctx: ctx, module: md};
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

}