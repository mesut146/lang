#include "Compiler.h"
#include "Resolver.h"
#include "TypeUtils.h"
#include "parser/Ast.h"
#include "parser/Parser.h"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <unordered_map>
#include <variant>


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


namespace fs = std::filesystem;

std::vector<std::string> Compiler::global_protos;

std::string getName(const std::string &path) {
    auto i = path.rfind('/');
    return path.substr(i + 1);
}

std::string trimExtenstion(const std::string &name) {
    auto i = name.rfind('.');
    if (i == std::string::npos) {
        return name;
    }
    return name.substr(0, i);
}

std::string get_out_file(const std::string &path) {
    auto name = getName(path);
    auto noext = trimExtenstion(name);
    return noext + ".o";
}


std::string read_file(const std::string &path) {
    std::fstream stream;
    stream.open(path, std::fstream::in);
    if (!stream.is_open()) throw std::system_error(errno, std::system_category(), "failed to open " + path);
    std::stringstream ss;
    ss << stream.rdbuf();
    auto buf = ss.str();
    stream.close();
    return buf;
}


void Compiler::init() {
    TargetTriple = llvm::sys::getDefaultTargetTriple();
    llvm::InitializeAllTargetInfos();
    llvm::InitializeAllTargets();
    llvm::InitializeAllTargetMCs();
    llvm::InitializeAllAsmParsers();
    llvm::InitializeAllAsmPrinters();

    std::string Error;
    //llvm::TargetRegistry::printRegisteredTargetsForVersion(llvm::outs());
    auto Target = llvm::TargetRegistry::lookupTarget(TargetTriple, Error);

    if (!Target) {
        throw std::runtime_error(Error);
    }
    auto CPU = "generic";
    auto Features = "";

    llvm::TargetOptions opt;
    auto RM = std::optional<llvm::Reloc::Model>(llvm::Reloc::Model::PIC_);
    TargetMachine = Target->createTargetMachine(TargetTriple, CPU, Features, opt, RM);
    Resolver::init_prelude();

    //llvm::sys::PrintStackTraceOnErrorSignal("lang");
    cache2.read_cache();
    Compiler::global_protos.clear();
}

void Compiler::compileAll() {
    single_mode = false;
    init();
    for (const auto &e : fs::recursive_directory_iterator(srcDir)) {
        if (e.is_directory()) continue;
        compile(e.path().string());
    }
    //compile main file last so that we collect all globals
    if (main_file.has_value()) {
        compile(main_file.value());
    }

    link_run("", "");
    /*for (auto &[k, v] : Resolver::resolverMap) {
        //v.reset();
        //v->unit.reset();
    }*/
}

void Compiler::link_run(const std::string &name0, const std::string &args) {
    auto name = name0;
    if (name0.empty()) {
        name = "a.out";
    }
    if (fs::exists(name)) {
        system(("rm " + name).c_str());
    }
    std::string cmd = "clang-16 -no-pie ";
    cmd.append("-o ").append(name).append(" ");
    for (auto &obj : compiled) {
        cmd.append(obj);
        cmd.append(" ");
    }
    compiled.clear();
    cmd.append(args);
    if (system(cmd.c_str()) == 0) {
        auto code = system(("./" + name).c_str());
        if (code != 0) {
            print("code = " + std::to_string(code));
            exit(1);
        }
    } else {
        print(cmd + "\n");
        throw std::runtime_error("link failed");
    }
}

void Compiler::build_library(const std::string &name, bool shared) {
    std::string cmd = "";
    if (shared) {
        cmd += "clang-16 ";
        cmd += "-shared -o ";
        cmd += name;
    } else {
        cmd += "ar rcs ";
        cmd += name;
    }
    cmd += " ";
    for (auto &obj : compiled) {
        cmd.append(obj);
        cmd.append(" ");
    }
    compiled.clear();
    if (system(cmd.c_str()) == 0) {
        print("build library " + name);
    } else {
        print(cmd + "\n");
        throw std::runtime_error("link failed");
    }
}

void Compiler::emit(std::string &Filename) {
    if (Config::debug) DBuilder->finalize();

    mod->setDataLayout(TargetMachine->createDataLayout());
    mod->setTargetTriple(TargetTriple);

    std::error_code EC;
    llvm::raw_fd_ostream dest(Filename, EC, llvm::sys::fs::OF_None);

    if (EC) {
        std::cerr << "Could not open file: " << EC.message();
        exit(1);
    }

    //TargetMachine->setOptLevel(llvm::CodeGenOpt::Aggressive);

    llvm::legacy::PassManager pass;
    if (TargetMachine->addPassesToEmitFile(pass, dest, nullptr, llvm::CGFT_ObjectFile)) {
        std::cerr << "TargetMachine can't emit a file of this type";
        exit(1);
    }
    pass.run(*mod);

    dest.flush();
    dest.close();
    if (Config::verbose) {
        std::cout << "writing " << Filename << std::endl;
    }
}

void initModule(const std::string &path, Compiler *c) {
    auto name = getName(path);
    if (!c->ctxp) {
        c->ctxp = std::make_unique<llvm::LLVMContext>();
    }
    c->mod = std::make_unique<llvm::Module>(name, c->ctx());
    c->mod->setTargetTriple(c->TargetTriple);
    c->mod->setDataLayout(c->TargetMachine->createDataLayout());
    c->Builder = std::make_unique<llvm::IRBuilder<>>(c->ctx());
    c->init_dbg(path);
    /*c->mod->addModuleFlag(llvm::Module::Warning, "branch-target-enforcement", (uint32_t) 0);
    c->mod->addModuleFlag(llvm::Module::Warning, "sign-return-address", (uint32_t) 0);
    c->mod->addModuleFlag(llvm::Module::Warning, "sign-return-address-all", (uint32_t) 0);
    c->mod->addModuleFlag(llvm::Module::Warning, "sign-return-address-with-bkey", (uint32_t) 0);
    c->mod->addModuleFlag(llvm::Module::Warning, "uwtable", (uint32_t) 0);
    c->mod->addModuleFlag(llvm::Module::Warning, "frame-pointer", (uint32_t) 0);*/
}

void copy_file(const std::string &path, const std::string &outDir, const std::string &name) {
    std::ifstream src;
    src.open(path, std::ifstream::binary);
    std::ofstream trg;
    trg.open(outDir + "/" + name, std::ofstream::binary);
    trg << src.rdbuf();
}

llvm::Constant *getDefault(Type &type, Compiler *c) {
    if (type.isPointer()) {
        return llvm::ConstantPointerNull::get(c->Builder->getPtrTy());
    }
    if (type.isArray()) {
        int snt = type.size;
        //create llvm array
        auto ty = c->mapType(type);
        std::vector<llvm::Constant *> vals;
        auto arr = llvm::ConstantArray::get((llvm::ArrayType *) ty, vals);
        return arr;
        //return llvm::ConstantExpr::getGetElementPtr(arr, llvm::ConstantInt::get(c->Builder->getInt32Ty(), 0));
    }
    auto s = type.print();
    auto bits = c->getSize2(type);
    if (s == "bool" || s == "i8" || s == "i16" || s == "i32" || s == "i64") {
        return c->makeInt(0, bits);
    }
    if (isStruct(type)) {
        //return zero init
        auto ty = c->mapType(type);
        return llvm::ConstantStruct::get((llvm::StructType *) ty);
    }
    throw std::runtime_error("def " + s);
}

std::string mangle_unit(const std::string &path) {
    std::string res;
    for (auto c : path) {
        if (c == '.') {
            c = '_';
        } else if (c == '/') {
            c = '_';
        }
        res.insert(res.end(), 1, c);
    }
    return res;
}

std::string mangle_static(const std::string &path) {
    return mangle_unit(path) + "_static_init";
}

llvm::Function *make_init_proto(const std::string &path, Compiler *c) {
    std::vector<llvm::Type *> argTypes;
    auto fr = llvm::FunctionType::get(c->Builder->getVoidTy(), argTypes, false);
    auto linkage = llvm::Function::ExternalLinkage;
    std::string mangled = mangle_static(path);
    return llvm::Function::Create(fr, linkage, mangled, *c->mod);
}

void dbg_glob(Compiler *c, Global &g, const Type &type) {
    if (!Config::debug) return;
    auto sp = c->di.sp;
    //auto v = c->DBuilder->createAutoVariable(sp, name, c->di.file, line, c->map_di(type), true);
    auto val = c->NamedValues[g.name];
    auto lc = llvm::DILocation::get(sp->getContext(), g.line, g.pos, sp);
    auto e = c->DBuilder->createExpression();
    //c->DBuilder->insertDeclare(val, v, e, lc, c->Builder->GetInsertBlock());
    //c->DBuilder->createGlobalVariableExpression(nullptr, g.name, g.name, nullptr, g.line, c->map_di(type), false, true, val);
}

void init_globals(Compiler *c) {
    for (auto &is : c->resolv->get_imports()) {
        auto res = Resolver::getResolver(is, c->resolv->root);
        for (auto &g : res->unit->globals) {
            //auto type = c->resolv->getType(g.expr.get());
            auto type = res->getType(g.expr.get());
            auto ty = c->mapType(type);
            auto linkage = llvm::GlobalValue::LinkageTypes::ExternalLinkage;
            //auto linkage = llvm::GlobalValue::LinkOnceODRLinkage;
            llvm::Constant *init = nullptr;//getDefault(type, c);
            auto gv = new llvm::GlobalVariable(*c->mod, ty, false, linkage, init, g.name);
            c->globals[g.name] = gv;
            c->NamedValues[g.name] = gv;
        }
    }
    if (c->unit->globals.empty()) {
        return;
    }
    auto staticf = make_init_proto(c->unit->path, c);
    std::string mangled = staticf->getName().str();
    Compiler::global_protos.push_back(c->unit->path);
    Method m(c->unit->path);
    m.type = Type("void");
    m.name = mangled;
    c->dbg_func(&m, staticf);
    auto bb = llvm::BasicBlock::Create(c->ctx(), "", staticf);
    c->Builder->SetInsertPoint(bb);
    for (Global &g : c->unit->globals) {
        auto rt = c->resolv->resolve(g.expr.get());
        auto &type = rt.type;
        auto ty = c->mapType(type);
        auto linkage = llvm::GlobalValue::LinkageTypes::ExternalLinkage;
        //auto linkage = llvm::GlobalValue::LinkOnceODRLinkage;
        llvm::Constant *init = getDefault(type, c);
        auto gv = new llvm::GlobalVariable(*c->mod, ty, false, linkage, init, g.name);
        c->globals[g.name] = gv;
        c->NamedValues[g.name] = gv;
        auto glob_di = c->DBuilder->createGlobalVariableExpression(c->di.cu, g.name, g.name, nullptr, g.line, c->map_di(type), false, true, nullptr);
        gv->addDebugInfo(glob_di);

        c->loc(0, 0);
        if (rt.targetMethod && isStruct(type)) {
            auto mc = dynamic_cast<MethodCall *>(g.expr.get());
            c->call(mc, gv);
        } else if (!type.isArray()) {
            //todo move & drop of global
            c->setField(g.expr.get(), type, gv);
        }
        //dbg_glob();
    }
    c->Builder->CreateRetVoid();

    if (Config::debug) {
        c->DBuilder->finalizeSubprogram(c->di.sp);
        c->di.sp = nullptr;
    }

    if (llvm::verifyFunction(*staticf, &llvm::outs())) {
        staticf->dump();
        error(mangled + " has errors");
    }
}

bool has_main(Unit *unit) {
    for (auto &it : unit->items) {
        if (it->isMethod()) {
            auto m = dynamic_cast<Method *>(it.get());
            if (m && is_main(m)) {
                return true;
            }
        }
    }
    return false;
}

std::optional<std::string> Compiler::compile(const std::string &path) {
    fs::path p(path);
    auto outFile = get_out_file(path);
    if (!cache2.need_compile(path)) {
        compiled.push_back(outFile);
        return outFile;
    }
    auto ext = p.extension().string();
    if (ext != ".x") {
        error("invalid extension " + path);
    }
    if (Config::verbose) {
        std::cout << "compiling " << path << std::endl;
    }
    resolv = Resolver::getResolver(path, srcDir);
    curOwner.init(this);
    unit = resolv->unit;
    if (has_main(unit.get())) {
        main_file = path;
        if (!single_mode) {//compile last
            return outFile;
        }
    }
    resolv->resolveAll();

    initModule(path, this);
    createProtos();
    init_globals(this);

    for (auto &m : getMethods(unit.get())) {
        genCode(m);
    }
    for (int i = 0; i < resolv->generatedMethods.size(); i++) {
        auto m = resolv->generatedMethods.at(i);
        genCode(m);
    }
    int lastpos = unit->items.size();
    for (auto &imp : curOwner.drop_impls) {
        auto m = &imp->methods.at(0);
        AstCopier cp;
        auto item = std::make_unique<Impl>(imp->type);
        auto res = std::any_cast<Method *>(cp.visitMethod(m));
        res->parent = m->parent;
        item->methods.push_back(std::move(*res));
        unit->items.push_back(std::move(item));
    }
    for (int i = lastpos; i < unit->items.size(); ++i) {
        auto it = unit->items[i].get();
        auto imp = dynamic_cast<Impl *>(it);
        auto m = &imp->methods.at(0);
        print("resolve drop_impl " + imp->type.print() + " => " + mangle(m));
        imp->accept(resolv.get());
    }
    for (int i = lastpos; i < unit->items.size(); ++i) {
        auto it = unit->items[i].get();
        auto imp = dynamic_cast<Impl *>(it);
        auto m = &imp->methods.at(0);
        print("make_proto " + imp->type.print());
        make_proto(m);
    }
    for (int i = lastpos; i < unit->items.size(); ++i) {
        auto it = unit->items[i].get();
        auto imp = dynamic_cast<Impl *>(it);
        auto m = &imp->methods.at(0);
        print("genCode drop_impl " + imp->type.print() + " => " + mangle(m));
        genCode(m);
    }

    //emit llvm
    auto name = getName(path);
    auto noext = trimExtenstion(name);
    auto llvm_file = noext + ".ll";
    std::error_code ec;
    llvm::raw_fd_ostream fd(llvm_file, ec);
    mod->print(fd, nullptr);
    if (Config::verbose) {
        print("writing " + llvm_file);
    }

    llvm::verifyModule(*mod, &llvm::outs());

    //todo fullpath

    emit(outFile);
    cleanup();
    compiled.push_back(outFile);
    cache2.update(p);
    cache2.write_cache();
    return outFile;
}

void Compiler::cleanup() {
    // for (auto &[k, v] : funcMap) {
    //     v->eraseFromParent();
    // }
    funcMap.clear();
    classMap.clear();
    // for (auto &[k, v] : NamedValues) {
    //     v->deleteValue();
    // }
    NamedValues.clear();
    //ctxp.reset();
    //mod.reset();
    //Builder.reset();
    virtuals.clear();
    vtables.clear();
    virtualIndex.clear();
    globals.clear();
    //delete staticf;
}

llvm::Value *Compiler::branch(llvm::Value *val) {
    auto ty = llvm::cast<llvm::IntegerType>(val->getType());
    if (!ty) return val;
    auto w = ty->getBitWidth();
    if (w == 1) return val;
    return Builder->CreateTrunc(val, getInt(1));
}

llvm::Value *Compiler::load(llvm::Value *val) {
    auto ty = val->getType();
    return Builder->CreateLoad(ty, val);
}
llvm::Value *Compiler::load(llvm::Value *val, const Type &type) {
    auto ty = mapType(type);
    return Builder->CreateLoad(ty, val);
}

bool isVar(Expression *e) {
    auto de = dynamic_cast<DerefExpr *>(e);
    if (de) {
        return isVar(de->expr.get());
    }
    return dynamic_cast<SimpleName *>(e) ||
           dynamic_cast<FieldAccess *>(e) ||
           dynamic_cast<ArrayAccess *>(e);
}

//load if alloca
llvm::Value *Compiler::loadPtr(Expression *e) {
    auto val = gen(e);
    if (!isVar(e)) return val;
    if (!val->getType()->isPointerTy()) {
        return val;
    }
    //local, fa, aa
    auto rt = resolv->resolve(e);
    return load(val, rt.type);
}

llvm::Value *extend(llvm::Value *val, const Type &srcType, const Type &trgType, Compiler *c) {
    auto src = val->getType()->getPrimitiveSizeInBits();
    int bits = c->getSize2(trgType);
    if (src < bits) {
        if (isUnsigned(srcType)) {
            return c->Builder->CreateZExt(val, c->getInt(bits));
        }
        return c->Builder->CreateSExt(val, c->getInt(bits));
    } else if (src > bits) {
        return c->Builder->CreateTrunc(val, c->getInt(bits));
    }
    return val;
}

llvm::Value *Compiler::cast(Expression *expr, const Type &trgType) {
    auto val = loadPtr(expr);
    if (trgType.isPrim()) {
        return extend(val, resolv->getType(expr), trgType, this);
    }
    return val;
}

void Compiler::setField(Expression *expr, const Type &type, llvm::Value *ptr, Expression* lhs) {
    auto de = dynamic_cast<DerefExpr *>(expr);
    if (de && isStruct(type)) {
        auto val = get_obj_ptr(de->expr.get());
        curOwner.beginAssign(lhs, ptr);
        copy(ptr, val, type);
        return;
    }
    if (isRvo(expr)) {
        auto val = gen(expr);
        //curOwner.drop(expr, ptr);
        curOwner.beginAssign(lhs, ptr);
        copy(ptr, val, type);
        return;
    }
    //dynamic_cast<MethodCall *>(expr)
    if (doesAlloc(expr)) {
        child(expr, ptr);
    } else if (isStruct(type)) {//todo mc
        auto val = gen(expr);
        //curOwner.drop(expr, ptr);
        curOwner.beginAssign(lhs, ptr);
        copy(ptr, val, type);
    } else if (type.isPointer()) {
        auto val = get_obj_ptr(expr);
        Builder->CreateStore(val, ptr);
    } else {
        auto val = cast(expr, type);
        Builder->CreateStore(val, ptr);
    }
}

void Compiler::make_proto(std::unique_ptr<Method> &m) {
    make_proto(m.get());
}

llvm::Function *Compiler::make_proto(Method *m) {
    if (m->isGeneric) {
        //print("skip generic " + printMethod(m));
        return nullptr;
    }
    auto mangled = mangle(m);
    if (funcMap.contains(mangled)) {
        return funcMap.at(mangled);
    }
    resolv->curMethod = m;
    std::vector<llvm::Type *> argTypes;
    bool rvo = isRvo(m);
    if (rvo) {
        argTypes.push_back(mapType(m->type)->getPointerTo());
    }
    if (m->self) {
        auto &self_type = *m->self->type;
        llvm::Type *ty = mapType(self_type);
        if (isStruct(self_type)) {
            //structs are always pass by ptr
            ty = ty->getPointerTo();
        }
        argTypes.push_back(ty);
    }
    for (auto &prm : m->params) {
        auto ty = mapType(*prm.type);
        if (isStruct(*prm.type)) {
            //structs are always pass by ptr
            ty = ty->getPointerTo();
        }
        argTypes.push_back(ty);
    }
    llvm::Type *retType;
    if (rvo) {
        retType = Builder->getVoidTy();
    } else if (is_main(m) && m->type.print() == "void") {
        retType = getInt(32);
    } else {
        retType = mapType(m->type);
    }
    auto fr = llvm::FunctionType::get(retType, argTypes, false);
    auto linkage = llvm::Function::ExternalLinkage;
    if (!m->typeArgs.empty() || (m->parent.is_impl() && !m->parent.type->typeArgs.empty())) {
        linkage = llvm::Function::LinkOnceODRLinkage;
    }
    auto f = llvm::Function::Create(fr, linkage, mangled, *mod);
    /*f->addFnAttr(llvm::Attribute::MustProgress);
    f->addFnAttr(llvm::Attribute::NoInline);
    f->addFnAttr(llvm::Attribute::NoUnwind);
    f->addFnAttr(llvm::Attribute::OptimizeNone);*/
    /*f->addFnAttr("frame-pointer", "non-leaf");
    f->addFnAttr("min-legal-vector-width", "0");
    f->addFnAttr("no-trapping-math", "true");
    f->addFnAttr("stack-protector-buffer-size", "8");
    f->addFnAttr("target-cpu", "generic");*/
    int i = 0;
    if (rvo) {
        f->getArg(0)->setName("ret");
        f->getArg(0)->addAttr(llvm::Attribute::StructRet);
        i++;
    }
    if (m->self) {
        //f->getArg(i)->setName(m->self->name);
        i++;
    }
    for (int pi = 0; i < f->arg_size(); i++) {
        //f->getArg(i)->setName(m->params[pi].name);
        pi++;
    }
    funcMap[mangled] = f;
    resolv->curMethod = nullptr;
    if (m->isVirtual) virtuals.push_back(m);
    return f;
}

std::vector<Method *> getVirtual(StructDecl *decl, Unit *unit) {
    std::vector<Method *> arr;
    for (auto &item : unit->items) {
        if (!item->isImpl()) continue;
        auto imp = (Impl *) item.get();
        if (imp->type.name != decl->type.name) continue;
        for (auto &m : imp->methods) {
            if (m.isVirtual) {
                arr.push_back(&m);
            }
        }
    }
    return arr;
}

llvm::Type *get_variant_type(const Type &type, Compiler *c) {
    auto id = type.print();
    if (c->classMap.contains(id)) {
        return c->classMap.at(id);
    }
    throw std::runtime_error("get_variant_type " + type.print());
}

llvm::Type *Compiler::makeDecl(BaseDecl *bd) {
    //print("makeDecl " + bd->type.print());
    if (bd->isGeneric) {
        return nullptr;
    }
    auto mangled = bd->type.print();
    if (!classMap.contains(mangled)) {
        auto ty = llvm::StructType::create(ctx(), mangled);
        classMap[mangled] = ty;
        return ty;
    }
    //fill body
    auto *r = resolv.get();

    auto ty = (llvm::StructType *) classMap.at(mangled);
    if (bd->isEnum()) {
        auto ed = dynamic_cast<EnumDecl *>(bd);
        int max = 0;
        for (auto &ev : ed->variants) {
            std::vector<llvm::Type *> var_elems;
            for (auto &field : ev.fields) {
                var_elems.push_back(mapType(&field.type));
            }
            auto var_mangled = mangled + "::" + ev.name;
            auto var_ty = llvm::StructType::create(ctx(), var_elems, var_mangled);
            classMap[var_mangled] = var_ty;
            auto var_size = mod->getDataLayout().getStructLayout(var_ty)->getSizeInBits();
            if (var_size > max) {
                max = var_size;
            }
        }
        auto sz = max / 8;
        auto tag = getInt(ENUM_TAG_BITS);
        auto data = llvm::ArrayType::get(getInt(8), sz);
        if (bd->base) {
            auto base_ty = mapType(bd->base.value(), resolv.get());
            Layout::set_elems_enum(ty, base_ty, tag, data);
        } else {
            Layout::set_elems_enum(ty, nullptr, tag, data);
        }
    } else {
        auto td = dynamic_cast<StructDecl *>(bd);
        std::vector<llvm::Type *> elems;
        for (auto &field : td->fields) {
            elems.push_back(mapType(&field.type, r));
        }
        //vtable ptr
        if (!getVirtual(td, unit.get()).empty()) {
            elems.push_back(getInt(8)->getPointerTo()->getPointerTo());
        }
        if (bd->base) {
            auto base_ty = mapType(bd->base.value(), resolv.get());
            Layout::set_elems_struct(ty, base_ty, elems);
        } else {
            Layout::set_elems_struct(ty, nullptr, elems);
        }
    }
    return ty;
}

void Compiler::createProtos() {
    if (!sliceType) {
        sliceType = make_slice_type();
    }
    if (!stringType) {
        stringType = make_string_type();
    }
    std::vector<BaseDecl *> list;
    for (auto bd : getTypes(unit.get())) {
        if (bd->isGeneric) continue;
        list.push_back(bd);
        //print("local "+bd->type.print());
    }
    for (auto bd : resolv->usedTypes) {
        if (bd->isGeneric) {
            //error("gen");
            continue;
        }
        list.push_back(bd);
        //print("used "+bd->type.print());
    }
    sort(list, resolv.get());
    for (auto bd : list) {
        makeDecl(bd);
    }
    for (auto bd : list) {
        makeDecl(bd);
    }
    for (auto bd : list) {
        map_di_proto(bd);
    }
    for (auto bd : list) {
        map_di_fill(bd);
    }
    //methods
    for (auto m : getMethods(unit.get())) {
        make_proto(m);
    }
    //generic methods from resolver
    for (auto gm : resolv->generatedMethods) {
        make_proto(gm);
    }
    for (auto m : resolv->usedMethods) {
        make_proto(m);
    }

    printf_proto = make_printf();
    fflush_proto = make_fflush();
    exit_proto = make_exit();
    mallocf = make_malloc();
    make_vtables();
    stdout_ptr = new llvm::GlobalVariable(*mod, getPtr(), false, llvm::GlobalValue::ExternalLinkage, nullptr, "stdout");
    stdout_ptr->addAttribute("global");
}

int find_idx(std::vector<Method *> &vt, Method *m) {
    for (int i = 0; i < vt.size(); i++) {
        if (Resolver::do_override(m, vt[i])) return i;
    }
    throw std::runtime_error("internal error");
}

void Compiler::make_vtables() {
    std::map<std::string, std::vector<Method *>> map;
    for (auto m : virtuals) {
        auto p = m->self->type->unwrap().print();
        map[p].push_back(m);
        virtualIndex[m] = map[p].size() - 1;
    }
    //override
    std::vector<std::string> done;
    for (auto [df, basef] : resolv->overrideMap) {
        auto base = basef->self->type->unwrap().print();
        auto key = df->self->type->unwrap().print() + "." + base;
        if (std::find(done.begin(), done.end(), key) != done.end()) {
            continue;
        }
        done.push_back(key);
        auto &vt = map[base];
        auto dvt = vt;
        //now update base vt by overrides
        dvt[find_idx(vt, df)] = df;
        //other bases can override other methods of base
        auto decl = resolv->resolve(&*df->self->type).targetDecl;
        std::map<Method *, Type> mrm;
        mrm[basef] = *df->self->type;
        while (decl->base && decl->base->print() != base) {
            for (auto [k2, v2] : resolv->overrideMap) {
                //check we override same vt
                if (v2->self->type->print() != base) continue;
                //prevent my upper overriding base bc we care below us
                if (Resolver::do_override(k2, basef)) continue;
                //if(k2->self->type->print() != decl->base->print()) continue;
                //keep outermost
                auto it = mrm.find(v2);
                if (it != mrm.end()) {
                    //already overrode, keep outermost
                    auto dcl = resolv->resolve(it->second).targetDecl;
                    if (resolv->is_base_of(*k2->self->type, dcl)) {
                        continue;
                    }
                }
                dvt[find_idx(vt, k2)] = k2;
                mrm[v2] = k2->self->type->unwrap();
            }
            decl = resolv->resolve(*decl->base).targetDecl;
        }
        map[key] = dvt;
    }
    for (auto &[k, v] : map) {
        auto i8p = getInt(8)->getPointerTo();
        auto arrt = llvm::ArrayType::get(i8p, 1);
        auto linkage = llvm::GlobalValue::ExternalLinkage;
        std::vector<llvm::Constant *> arr;
        for (auto m : v) {
            auto f = funcMap.at(mangle(m));
            auto fcast = llvm::ConstantExpr::getCast(llvm::Instruction::BitCast, f, i8p);
            arr.push_back(fcast);
        }
        auto init = llvm::ConstantArray::get(arrt, arr);
        auto vt = new llvm::GlobalVariable(*mod, arrt, true, linkage, init, k + ".vt");
        vtables[k] = vt;
    }
}

void Compiler::allocParams(Method *m) {
    //alloc
    //auto ff = funcMap[mangle(m)];
    int arg_idx = 0;
    if (isRvo(m)) arg_idx++;
    if (m->self) {
        auto &prm = *m->self;
        auto ty = mapType(*prm.type);
        auto ptr = Builder->CreateAlloca(ty);
        ptr->setName(prm.name);
        NamedValues[prm.name] = ptr;
        ++arg_idx;
    }
    for (auto &prm : m->params) {
        auto ty = mapType(*prm.type);
        auto ptr = Builder->CreateAlloca(ty);
        ptr->setName(prm.name);
        NamedValues[prm.name] = ptr;
        ++arg_idx;
    }
}

void storeParams(Method *m, Compiler *c) {
    auto func = c->funcMap.at(mangle(m));
    int argIdx = c->isRvo(m) ? 1 : 0;
    int didx = 1;
    if (m->self) {
        auto ptr = c->NamedValues[m->self->name];
        auto val = func->getArg(argIdx);
        if (isStruct(*m->self->type)) {
            c->copy(ptr, val, *m->self->type);
            //self is always ptr?
            //c->dbg_prm(*m->self, Type(Type::Pointer, m->self->type.value()), didx);
            c->dbg_prm(*m->self, m->self->type.value(), didx);
        } else {
            c->Builder->CreateStore(val, ptr);
            c->dbg_prm(*m->self, m->self->type.value(), didx);
        }
        didx++;
        argIdx++;
        c->curOwner.addPrm(m->self.value(), ptr, true);
    }
    for (auto i = 0; i < m->params.size(); i++) {
        auto &prm = m->params[i];
        auto val = func->getArg(argIdx);
        ++argIdx;
        auto ptr = c->NamedValues[prm.name];
        if (isStruct(*prm.type)) {
            c->copy(ptr, val, *prm.type);
            c->dbg_prm(prm, prm.type.value(), didx);
        } else {
            c->Builder->CreateStore(val, ptr);
            c->dbg_prm(prm, prm.type.value(), didx);
        }
        ++didx;
        c->curOwner.addPrm(prm, ptr, false);
    }
}

enum class ExitType {
    NONE,
    RETURN,
    PANIC,
    BREAK,
    CONTINE,
};

struct Exit {
    ExitType kind;
    std::unique_ptr<Exit> if_kind;
    std::unique_ptr<Exit> else_kind;

    Exit(const ExitType &kind) : kind(kind) {}
    Exit() {}
};


Exit get_exit_type(Statement *stmt) {
    if (dynamic_cast<ReturnStmt *>(stmt)) return ExitType::RETURN;
    if (dynamic_cast<BreakStmt *>(stmt)) return ExitType::BREAK;
    if (dynamic_cast<ContinueStmt *>(stmt)) return ExitType::CONTINE;
    auto expr = dynamic_cast<ExprStmt *>(stmt);
    if (expr) {
        auto mc = dynamic_cast<MethodCall *>(expr->expr);
        if (mc && !mc->scope && mc->name == "panic") {
            return ExitType::PANIC;
        }
        return ExitType::NONE;
    }
    auto block = dynamic_cast<Block *>(stmt);
    if (block && !block->list.empty()) {
        auto &last = block->list.back();
        return get_exit_type(last.get());
    }
    auto is = dynamic_cast<IfStmt *>(stmt);
    if (is) {
        auto res = Exit{ExitType::NONE};
        auto if_type = get_exit_type(is->thenStmt.get());
        res.if_kind = std::make_unique<Exit>(std::move(if_type));
        if (is->elseStmt) {
            auto else_kind = get_exit_type(is->thenStmt.get());
            res.else_kind = std::make_unique<Exit>(std::move(else_kind));
        }
        return res;
    }
    return ExitType::NONE;
}

bool ends_with_return(Statement *stmt) {
    if (dynamic_cast<ReturnStmt *>(stmt)) return true;
    auto expr = dynamic_cast<ExprStmt *>(stmt);
    if (expr) {
        auto mc = dynamic_cast<MethodCall *>(expr->expr);
        return mc && !mc->scope && mc->name == "panic";
    }
    auto block = dynamic_cast<Block *>(stmt);
    if (block && !block->list.empty()) {
        auto &last = block->list.back();
        return ends_with_return(last.get());
    }
    auto is = dynamic_cast<IfStmt *>(stmt);
    if (is) {
        if (is->elseStmt) {
            return ends_with_return(is->thenStmt.get()) || ends_with_return(is->elseStmt.get());
        }
        //return ends_with_return(is->thenStmt.get());
    }
    return false;
}

bool isReturnLast(Statement *stmt) {
    if (isRet(stmt)) {
        return true;
    }
    auto block = dynamic_cast<Block *>(stmt);
    if (block && !block->list.empty()) {
        auto &last = block->list.back();
        if (isRet(last.get())) {
            return true;
        }
    }
    return false;
}

Type prm_type(const Type &type) {
    if (isStruct(type)) {
        return Type(Type::Pointer, type);
    }
    return type;
}

void Compiler::genCode(std::unique_ptr<Method> &m) {
    genCode(m.get());
}

void Compiler::genCode(Method *m) {
    if (m->isGeneric || !m->body) {
        return;
    }
    resolv->curMethod = m;
    curMethod = m;
    auto id = mangle(m);
    //print("genCode " + id + "\n");
    curOwner.init(m);
    if (funcMap.contains(id)) {
        func = funcMap.at(id);
    } else {
        func = make_proto(m);
    }
    NamedValues.clear();
    auto bb = llvm::BasicBlock::Create(ctx(), "", func);
    Builder->SetInsertPoint(bb);
    //dbg
    dbg_func(m, func);

    allocParams(m);
    makeLocals(m->body.get());
    storeParams(curMethod, this);
    if (is_main(m)) {
        for (auto &init_proto_path : Compiler::global_protos) {
            loc(0, 0);
            auto init_proto = mod->getFunction(mangle_static(init_proto_path));
            if (!init_proto) {
                init_proto = make_init_proto(init_proto_path, this);
            }
            std::vector<llvm::Value *> args2;
            Builder->CreateCall(init_proto, args2);
        }
    }
    resolv->max_scope = 0;
    resolv->newScope();
    m->body->accept(this);
    if (!ends_with_return(m->body.get())) {
        //return already drops all
        curOwner.endScope(*curOwner.main_scope);
    }
    //exit code 0
    if (is_main(m) && m->type.print() == "void") {
        if (!ends_with_return(m->body.get())) {
            Builder->CreateRet(makeInt(0, 32));
        }
    } else if (!isReturnLast(m->body.get()) && m->type.print() == "void") {
        if (!m->body->list.empty()) {
            loc(m->body->list.back()->line + 1, 0);
        }
        Builder->CreateRetVoid();
    }
    if (Config::debug) {
        DBuilder->finalizeSubprogram(di.sp);
        di.sp = nullptr;
    }
    /*if (llvm::verifyFunction(*func, &llvm::outs())) {
        error("func " + printMethod(m) + " has errors");
    }*/
    func = nullptr;
    curMethod = nullptr;
}


llvm::Value *Compiler::gen(Expression *expr) {
    auto val = expr->accept(this);
    auto res = std::any_cast<llvm::Value *>(val);
    if (!res) error("val null " + expr->print() + " " + val.type().name());
    return res;
}

llvm::Value *Compiler::gen(std::unique_ptr<Expression> &expr) {
    return gen(expr.get());
}

std::any Compiler::visitBlock(Block *node) {
    for (auto &stmt : node->list) {
        loc(stmt.get());
        stmt->accept(this);
    }
    return nullptr;
}

std::any Compiler::visitReturnStmt(ReturnStmt *node) {
    loc(node);
    if (!node->expr) {
        curOwner.doReturn(node->line);
        if (is_main(curMethod)) {
            return Builder->CreateRet(makeInt(0, 32));
        }
        return Builder->CreateRetVoid();
    }
    auto &type = curMethod->type;
    auto e = node->expr.get();
    if (type.isPointer()) {
        auto val = get_obj_ptr(e);
        curOwner.doReturn(node->line);
        return Builder->CreateRet(val);
    }
    if (!isStruct(type)) {
        auto expr_type = resolv->getType(type);
        curOwner.doReturn(node->line);
        return Builder->CreateRet(cast(e, expr_type));
    }
    //rvo
    auto ptr = func->getArg(0);

    curOwner.check(e);
    if (e->print() == "self.str().cstr()") {
        int aa = 555;
    }

    if (doesAlloc(e)) {
        child(e, ptr);
        curOwner.doReturn(node->line);
        return Builder->CreateRetVoid();
    }
    auto de = dynamic_cast<DerefExpr *>(e);
    if (de) {
        auto val = get_obj_ptr(de->expr.get());
        copy(ptr, val, resolv->getType(e));
    } else {
        auto val = gen(e);
        copy(ptr, val, resolv->getType(e));
    }
    //todo move
    curOwner.doMoveReturn(e);//todo delete this?
    curOwner.doReturn(node->line);
    return Builder->CreateRetVoid();
}

std::any Compiler::visitExprStmt(ExprStmt *node) {
    return node->expr->accept(this);
}

std::any Compiler::visitParExpr(ParExpr *node) {
    return node->expr->accept(this);
}

bool is_logic(Expression *e) {
    auto p = dynamic_cast<ParExpr *>(e);
    if (p) return is_logic(p->expr);
    auto i = dynamic_cast<Infix *>(e);
    if (i) return (i->op == "&&") || (i->op == "||");
    return false;
}

void Compiler::set_and_insert(llvm::BasicBlock *bb) {
    Builder->SetInsertPoint(bb);
    func->insert(func->end(), bb);
}

std::pair<llvm::Value *, llvm::BasicBlock *> Compiler::andOr(Infix *node) {
    bool isand = node->op == "&&";
    auto l = loadPtr(node->left);
    auto bb = Builder->GetInsertBlock();
    auto then = llvm::BasicBlock::Create(ctx(), "rhs", func);
    auto next = llvm::BasicBlock::Create(ctx(), "end");
    if (isand) {
        Builder->CreateCondBr(branch(l), then, next);
    } else {
        Builder->CreateCondBr(branch(l), next, then);
    }
    Builder->SetInsertPoint(then);
    llvm::Value *r;
    if (is_logic(node->right)) {
        auto p = dynamic_cast<ParExpr *>(node->right);
        auto rr = andOr(p ? (Infix *) p->expr : (Infix *) node->right);
        r = rr.first;
        then = rr.second;
    } else {
        r = loadPtr(node->right);
    }
    auto rbit = Builder->CreateZExt(r, getInt(8));
    Builder->CreateBr(next);
    set_and_insert(next);
    auto phi = Builder->CreatePHI(getInt(8), 2);
    phi->addIncoming(isand ? makeInt(0, 8) : makeInt(1, 8), bb);
    phi->addIncoming(rbit, then);
    return {Builder->CreateZExt(phi, getInt(8)), next};
}

llvm::CmpInst::Predicate get_comp_op(const std::string &op) {
    if (op == "==") {
        return llvm::CmpInst::ICMP_EQ;
    }
    if (op == "!=") {
        return llvm::CmpInst::ICMP_NE;
    }
    if (op == "<") {
        return llvm::CmpInst::ICMP_SLT;
    }
    if (op == ">") {
        return llvm::CmpInst::ICMP_SGT;
    }
    if (op == "<=") {
        return llvm::CmpInst::ICMP_SLE;
    }
    if (op == ">=") {
        return llvm::CmpInst::ICMP_SGE;
    }
    throw std::runtime_error("get_comp_op");
}

std::any Compiler::visitInfix(Infix *node) {
    loc(node->left);
    auto &op = node->op;
    if (op == "&&" || op == "||") {
        return andOr(node).first;
    }
    auto lt = resolv->resolve(node->left);
    auto t1 = lt.type.print();
    auto t2 = resolv->getType(node->right).print();
    auto t3 = t1 == "bool" ? Type("i1") : binCast(t1, t2).type;
    auto l = cast(node->left, t3);
    auto r = cast(node->right, t3);
    if (isComp(op)) {
        return Builder->CreateCmp(get_comp_op(op), l, r);
    }
    if (op == "+") {
        return Builder->CreateNSWAdd(l, r);
    }
    if (op == "-") {
        if (isUnsigned(lt.type)) {
            return Builder->CreateSub(l, r);
        } else {
            return Builder->CreateNSWSub(l, r);
        }
    }
    if (op == "*") {
        return Builder->CreateNSWMul(l, r);
    }
    if (op == "/") {
        return Builder->CreateSDiv(l, r);
    }
    if (op == "%") {
        return Builder->CreateSRem(l, r);
    }
    if (op == "^") {
        return Builder->CreateXor(l, r);
    }
    if (op == "&") {
        return Builder->CreateAnd(l, r);
    }
    if (op == "|") {
        return Builder->CreateOr(l, r);
    }
    if (op == "<<") {
        return Builder->CreateShl(l, r);
    }
    if (op == ">>") {
        return Builder->CreateAShr(l, r);
    }
    throw std::runtime_error("infix: " + node->print());
}

std::any Compiler::visitUnary(Unary *node) {
    loc(node);
    auto val = loadPtr(node->expr);
    llvm::Value *res;
    if (node->op == "+") {
        res = val;
    } else if (node->op == "-") {
        auto bits = val->getType()->getPrimitiveSizeInBits();
        res = Builder->CreateNSWSub(makeInt(0, bits), val);
    } else if (node->op == "++") {
        auto v = gen(node->expr);
        auto bits = val->getType()->getPrimitiveSizeInBits();
        res = Builder->CreateNSWAdd(val, makeInt(1, bits));
        Builder->CreateStore(res, v);
    } else if (node->op == "--") {
        auto v = gen(node->expr);
        auto bits = val->getType()->getPrimitiveSizeInBits();
        res = Builder->CreateNSWSub(val, makeInt(1, bits));
        Builder->CreateStore(res, v);
    } else if (node->op == "!") {
        res = Builder->CreateTrunc(val, getInt(1));
        res = Builder->CreateXor(res, Builder->getTrue());
        res = Builder->CreateZExt(res, getInt(8));
    } else if (node->op == "~") {
        auto bits = val->getType()->getPrimitiveSizeInBits();
        res = Builder->CreateXor(val, makeInt(-1, bits));
    } else {
        throw std::runtime_error("Unary: " + node->print());
    }
    return res;
}

//gen lhs ptr without own check
llvm::Value *gen_left(Expression *lhs, Compiler *c) {
    auto sn = dynamic_cast<SimpleName *>(lhs);
    if (sn) {
        if (c->globals.contains(sn->name)) {
            return c->globals[sn->name];
        }
        return c->NamedValues[sn->name];
    }
    auto aa = dynamic_cast<ArrayAccess *>(lhs);
    if (aa) {
        //todo
        return c->gen(lhs);
    }
    auto fa = dynamic_cast<FieldAccess *>(lhs);
    if (fa) {
        //todo
        return c->gen(lhs);
    }
    auto de = dynamic_cast<DerefExpr *>(lhs);
    if (de) {
        return c->get_obj_ptr(de->expr.get());
    }
    c->resolv->err(lhs, "gen left");
    return nullptr;
}

std::any Compiler::visitAssign(Assign *node) {
    loc(node);
    llvm::Value *l = gen_left(node->left, this);
    auto lt = resolv->getType(node->left);
    if (node->op == "=") {
        //todo move this to setField where lhs is used completely
        if (dynamic_cast<ObjExpr *>(node->right)) {
            //dont delete, setField can't handle this
            auto rhs = gen(node->right);
            curOwner.beginAssign(node->left, l);
            copy(l, rhs, lt);
        } else {
            //curOwner.beginAssign(node->left, l);
            setField(node->right, lt, l, node->left);
        }
        curOwner.endAssign(node->left, node->right);
        return l;
    }
    auto val = l;
    auto r = cast(node->right, lt);
    if (l->getType()->isPointerTy()) {
        val = load(l, lt);
    }
    if (node->op == "+=") {
        auto tmp = Builder->CreateNSWAdd(val, r);
        return (llvm::Value *) Builder->CreateStore(tmp, l);
    }
    if (node->op == "-=") {
        auto tmp = Builder->CreateNSWSub(val, r);
        return (llvm::Value *) Builder->CreateStore(tmp, l);
    }
    if (node->op == "*=") {
        auto tmp = Builder->CreateNSWMul(val, r);
        return (llvm::Value *) Builder->CreateStore(tmp, l);
    }
    if (node->op == "/=") {
        auto tmp = Builder->CreateSDiv(val, r);
        return (llvm::Value *) Builder->CreateStore(tmp, l);
    }
    throw std::runtime_error("assign: " + node->print());
}

std::any Compiler::visitSimpleName(SimpleName *node) {
    if (globals.contains(node->name)) {
        return globals[node->name];
    }
    curOwner.check(node);
    return NamedValues[node->name];
}

llvm::Value *callMalloc(llvm::Value *sz, Compiler *c) {
    std::vector<llvm::Value *> args = {sz};
    return (llvm::Value *) c->Builder->CreateCall(c->mallocf, args);
}

void callPrint(MethodCall *mc, Compiler *c) {
    std::vector<llvm::Value *> args;
    for (auto a : mc->args) {
        if (isStrLit(a)) {
            auto l = dynamic_cast<Literal *>(a);
            auto str = c->Builder->CreateGlobalStringPtr(l->val.substr(1, l->val.size() - 2));
            args.push_back(str);
            continue;
        }
        auto arg_type = c->resolv->getType(a);
        if (arg_type.print() == "i8*" || arg_type.print() == "u8*") {
            auto src = c->get_obj_ptr(a);
            args.push_back(src);
            continue;
        }
        if (arg_type.isString()) {
            auto src = c->gen(a);
            //get ptr to inner char array
            if (src->getType()->isPointerTy()) {
                auto slice = c->gep2(src, SLICE_PTR_INDEX, c->stringType);
                args.push_back(c->load(slice, c->getPtr()));
            } else {
                args.push_back(src);
            }
        } else {
            auto av = c->loadPtr(a);
            args.push_back(av);
        }
    }
    c->Builder->CreateCall(c->printf_proto, args);
    //flush
    std::vector<llvm::Value *> args2;
    args2.push_back(c->load(c->stdout_ptr));
    c->Builder->CreateCall(c->fflush_proto, args2);
}

std::any callPanic(MethodCall *mc, Compiler *c) {
    std::string message = "\"panic ";
    message += c->curMethod->path + ":" + std::to_string(mc->line);
    message += " " + printMethod(c->curMethod);
    if (!mc->args.empty()) {
        message += "\n";
        auto val = dynamic_cast<Literal *>(mc->args[0])->val;
        message += val.substr(1, val.size() - 2);
    }
    message.append("\n\"");
    MethodCall mc2;
    mc2.args.push_back(new Literal(Literal::STR, message));
    mc2.args.insert(mc2.args.end(), mc->args.begin() + 1, mc->args.end());
    callPrint(&mc2, c);
    //call exit
    std::vector<llvm::Value *> exit_args = {c->makeInt(1)};
    c->Builder->CreateCall(c->exit_proto, exit_args);
    c->Builder->CreateUnreachable();
    return (llvm::Value *) c->Builder->getVoidTy();
}

std::any Compiler::visitMethodCall(MethodCall *mc) {
    loc(mc);
    if (is_std_no_drop(mc)) {
        auto arg = mc->args.at(0);
        curOwner.doMoveCall(arg);//fake move, so the will be no drop
        return (llvm::Value *) Builder->getVoidTy();
    }
    if (Resolver::is_std_is_ptr(mc)) {
        if (mc->typeArgs[0].isPointer()) {
            return (llvm::Value *) Builder->getTrue();
        }
        return (llvm::Value *) Builder->getFalse();
    }
    if (Resolver::is_std_size(mc)) {
        if (!mc->args.empty()) {
            auto ty = resolv->getType(mc->args[0]);
            return (llvm::Value *) makeInt(getSize2(ty), 64);
        } else {
            auto ty = resolv->getType(mc->typeArgs[0]);
            return (llvm::Value *) makeInt(getSize2(ty), 64);
        }
    }
    if (is_ptr_get(mc)) {
        auto elem_type = resolv->getType(mc).unwrap();
        auto src = get_obj_ptr(mc->args[0]);
        auto idx = loadPtr(mc->args[1]);
        return gep(src, idx, mapType(elem_type));
    }
    if (is_ptr_copy(mc)) {
        //ptr::copy(src_ptr, src_idx, elem)
        auto src_ptr = get_obj_ptr(mc->args[0]);
        auto idx = cast(mc->args[1], Type("i64"));
        auto val = gen(mc->args[2]);
        auto elem_type = resolv->getType(mc->args[2]);
        auto trg_ptr = gep(src_ptr, idx, mapType(elem_type));
        copy(trg_ptr, val, elem_type);
        return (llvm::Value *) Builder->getVoidTy();
    }
    if (is_ptr_deref(mc)) {
        auto src_ptr = get_obj_ptr(mc->args[0]);
        auto rt = resolv->getType(mc);
        if (rt.isPrim()) {
            return load(src_ptr, mapType(rt));
        }
        return src_ptr;
    }
    if (resolv->is_slice_get_ptr(mc)) {
        auto elem_type = resolv->getType(mc).unwrap();
        auto src = get_obj_ptr(mc->scope.get());
        auto ptr = gep(src, SLICE_PTR_INDEX, sliceType);
        return load(ptr, getPtr());
    }
    if (resolv->is_slice_get_len(mc)) {
        auto slice = get_obj_ptr(mc->scope.get());
        auto len_ptr = gep2(slice, SLICE_LEN_INDEX, sliceType);
        return load(len_ptr, getInt(SLICE_LEN_BITS));
    }
    if (resolv->is_array_get_len(mc)) {
        auto scope = resolv->getType(mc->scope.get()).unwrap();
        return (llvm::Value *) makeInt(scope.size, 64);
    }
    if (resolv->is_array_get_ptr(mc)) {
        auto src = get_obj_ptr(mc->scope.get());
        return src;
    }
    if (mc->name == "print" && !mc->scope) {
        callPrint(mc, this);
        return nullptr;
    } else if (mc->name == "malloc" && !mc->scope) {
        auto size = cast(mc->args[0], Type("i64"));
        if (!mc->typeArgs.empty()) {
            int typeSize = getSize2(mc->typeArgs[0]) / 8;
            size = Builder->CreateNSWMul(size, makeInt(typeSize, 64));
        }
        return callMalloc(size, this);
    } else if (mc->name == "panic" && !mc->scope) {
        return callPanic(mc, this);
    } else if (mc->name == "format" && !mc->scope) {
        error("format not implemented");
        //return callFormat(mc, this);
    }
    if (is_drop_call(mc)) {
        auto argt = resolv->resolve(mc->args.at(0));
        if (argt.type.print().ends_with("**")) {
            //dont drop
            return (llvm::Value *) Builder->getVoidTy();
        }
        if (argt.type.print().ends_with("*")) {
            //dont drop
            return (llvm::Value *) Builder->getVoidTy();
        }
        if (curOwner.isDropType(argt)) {
            auto arg = mc->args.at(0);
            auto ptr = gen(arg);
            curOwner.call_drop(argt.type, ptr);
            //todo bc of partial drop we have to comment below
            if (dynamic_cast<SimpleName *>(arg)) {
                //todo f.access
                curOwner.doMoveCall(arg);
            }
        }
        return (llvm::Value *) Builder->getVoidTy();
    }
    auto rt = resolv->resolve(mc);
    auto target = rt.targetMethod;
    if (isRvo(target)) {
        auto ptr = getAlloc(mc);
        curOwner.addPtr(mc, ptr);
        return call(mc, ptr);
    } else {
        return call(mc, nullptr);
    }
}

llvm::Value *Compiler::call(MethodCall *mc, llvm::Value *ptr) {
    auto rt = resolv->resolve(mc);
    auto target = rt.targetMethod;
    auto mangled = mangle(target);
    llvm::Function *f = nullptr;
    if (funcMap.contains(mangled)) {
        f = funcMap.at(mangled);
    } else {
        if (is_drop_call(mc)) {
            f = make_proto(target);
        }
    }
    if (f == nullptr) {
        resolv->err(mc, "proto not found");
    }
    std::vector<llvm::Value *> args;
    int paramIdx = 0;
    if (ptr) {
        args.push_back(ptr);
    }
    llvm::Value *obj = nullptr;
    if (target->self && !mc->is_static) {
        //add this object
        obj = get_obj_ptr(mc->scope.get());
        args.push_back(obj);
        paramIdx++;
        if (target->self->is_deref) {
            curOwner.doMoveCall(mc->scope.get());
        }
    }
    std::vector<Param *> params;
    if (target->self) {
        params.push_back(&target->self.value());
    }
    for (auto &p : target->params) {
        params.push_back(&p);
    }
    //print(mc->print());
    for (int i = 0, e = mc->args.size(); i != e; ++i) {
        auto a = mc->args[i];
        auto &pt = *params[paramIdx]->type;
        auto at = resolv->getType(a);
        llvm::Value *av;
        if (at.isPointer()) {
            av = get_obj_ptr(a);
        } else if (isStruct(at)) {
            auto de = dynamic_cast<DerefExpr *>(a);
            if (de) {
                av = get_obj_ptr(de->expr.get());
            } else {
                av = gen(a);
            }
        } else {
            av = cast(a, pt);
        }
        args.push_back(av);
        paramIdx++;
        if (!is_drop_call(mc)) {
            curOwner.doMoveCall(a);
        }
    }

    //virtual logic
    llvm::Value *res;
    auto it = resolv->overrideMap.find(target);
    Method *base = nullptr;
    if (it != resolv->overrideMap.end()) base = it->second;
    if (target->isVirtual || base) {
        auto scp = resolv->resolve(mc->scope.get());
        if (scp.type.isPointer()) {
            scp.type = *scp.type.scope.get();
        }
        int index;
        if (target->isVirtual) {
            index = virtualIndex[target];
        } else {
            index = virtualIndex[base];
        }
        if (target->isVirtual) {
            scp = resolv->resolve(*target->self->type);
        } else {
            scp = resolv->resolve(*base->self->type);
        }
        auto decl = (StructDecl *) scp.targetDecl;
        int vt_index = decl->fields.size() + (decl->base ? 1 : 0);
        auto vt = gep2(obj, vt_index, decl->type);
        vt = load(vt);
        auto ft = f->getType();
        auto real = llvm::ArrayType::get(ft, 1);
        auto fptr = load(gep(vt, 0, index, real));
        auto ff = f->getFunctionType();
        res = (llvm::Value *) Builder->CreateCall(ff, fptr, args);
    } else {
        res = (llvm::Value *) Builder->CreateCall(f, args);
    }
    if (ptr) {
        return args[0];
    }
    return res;
}

void Compiler::strLit(llvm::Value *ptr, Literal *node) {
    auto trimmed = node->val.substr(1, node->val.size() - 2);
    auto src = Builder->CreateGlobalStringPtr(trimmed);
    auto slice_ptr = gep2(ptr, 0, stringType);
    auto data_target = gep2(slice_ptr, SLICE_PTR_INDEX, sliceType);
    auto len_target = gep2(slice_ptr, SLICE_LEN_INDEX, sliceType);
    //set ptr
    Builder->CreateStore(src, data_target);
    //set len
    auto len = makeInt(trimmed.size(), SLICE_LEN_BITS);
    Builder->CreateStore(len, len_target);
}

std::any Compiler::visitLiteral(Literal *node) {
    loc(node);
    if (node->type == Literal::STR) {
        auto ptr = getAlloc(node);
        strLit(ptr, node);
        return (llvm::Value *) ptr;
    } else if (node->type == Literal::CHAR) {
        auto trimmed = node->val.substr(1, node->val.size() - 2);
        auto chr = trimmed[0];
        return (llvm::Value *) llvm::ConstantInt::get(getInt(32), chr);
    } else if (node->type == Literal::INT) {
        auto bits = 32;
        if (node->suffix) {
            bits = getSize2(*node->suffix);
        }
        int base = 10;
        if (node->val[0] == '0' && node->val[1] == 'x') base = 16;
        auto val = std::stoll(node->val, nullptr, base);
        return (llvm::Value *) llvm::ConstantInt::get(getInt(bits), val);
    } else if (node->type == Literal::BOOL) {
        return (llvm::Value *) (node->val == "true" ? makeInt(1, 8) : makeInt(0, 8));
    } else if (node->type == Literal::FLOAT) {
        //auto ty = resolv->getType(n);
        auto ty = mapType(Type("f64"));
        return (llvm::Value *) llvm::ConstantFP::get(ty, std::stod(node->val.c_str()));
    }
    throw std::runtime_error("literal: " + node->print());
}

void Compiler::copy(llvm::Value *trg, llvm::Value *src, const Type &type) {
    //src->dump();
    //trg->dump();
    //print("---------------");
    Builder->CreateMemCpy(trg, llvm::MaybeAlign(0), src, llvm::MaybeAlign(0), getSize2(type) / 8);
}

std::any Compiler::visitVarDecl(VarDecl *node) {
    node->decl->accept(this);
    return {};
}

std::any Compiler::visitVarDeclExpr(VarDeclExpr *node) {
    for (auto &f : node->list) {
        auto rhs = f.rhs.get();
        auto type = f.type ? resolv->getType(*f.type) : resolv->getType(rhs);
        NamedValues[f.name] = varAlloc[getId(f.name)];
        loc(&f);
        curOwner.check(rhs);
        auto ptr = NamedValues[f.name];
        if (!isStruct(type)) {
            auto val = cast(rhs, type);
            Builder->CreateStore(val, ptr);
        } else if (doesAlloc(rhs)) {
            //no unnecessary alloc
            auto val = gen(rhs);
            curOwner.addVar(f, type, val, rhs);
        } else {
            auto val = gen(rhs);
            copy(ptr, val, type);
            curOwner.addVar(f, type, ptr, rhs);
        }
        //dbg after init
        dbg_var(f, type);
    }
    return nullptr;
}

std::any Compiler::visitRefExpr(RefExpr *node) {
    auto inner = gen(node->expr);
    //todo rvalue
    auto mc = dynamic_cast<MethodCall *>(node->expr.get());
    if (mc) {
        throw std::runtime_error("visitRefExpr mc" + node->print());
    }
    return inner;
}

std::any Compiler::visitDerefExpr(DerefExpr *node) {
    auto type = resolv->getType(node);
    auto val = get_obj_ptr(node->expr.get());
    if (type.isPrim() || type.isPointer()) {
        return load(val, type);
    }
    return val;
}

EnumDecl *findEnum(const Type &type, Resolver *resolv) {
    auto rt = resolv->resolve(type);
    return dynamic_cast<EnumDecl *>(rt.targetDecl);
}

std::any Compiler::visitObjExpr(ObjExpr *node) {
    loc(node);
    auto tt = resolv->resolve(node);
    llvm::Value *ptr = getAlloc(node);
    curOwner.addPtr(node, ptr);
    object(node, ptr, tt, nullptr);
    return ptr;
}

void Compiler::object(ObjExpr *node, llvm::Value *ptr, const RType &tt, std::string *derived) {
    auto ty = mapType(tt.type);
    //set base
    for (auto arg : node->entries) {
        if (arg.isBase) {
            auto base_index = tt.targetDecl->isClass() ? STRUCT_BASE_INDEX : ENUM_BASE_INDEX;
            auto base_ptr = gep2(ptr, base_index, ty);
            auto val = dynamic_cast<ObjExpr *>(arg.value);
            if (val) {
                auto key = tt.targetDecl->type.print();
                object(val, base_ptr, resolv->resolve(arg.value), derived ? derived : &key);
            } else {
                auto val_ptr = gen(arg.value);
                copy(base_ptr, val_ptr, tt.type);
                //setField(arg.value, resolv->getType(arg.value), base_ptr);
            }
            break;
        }
    }
    if (tt.targetDecl->isEnum()) {
        //enum
        auto decl = dynamic_cast<EnumDecl *>(tt.targetDecl);
        auto variant_index = Resolver::findVariant(decl, node->type.name);
        setOrdinal(variant_index, ptr, decl);
        auto data_index = Layout::get_data_index(decl);
        auto dataPtr = gep2(ptr, data_index, ty);
        auto &fields = decl->variants[variant_index].fields;
        auto var_ty = get_variant_type(node->type, this);
        setFields(fields, node->entries, decl, var_ty, dataPtr);
    } else {
        //class
        auto decl = dynamic_cast<StructDecl *>(tt.targetDecl);
        if (!getVirtual(decl, unit.get()).empty()) {
            //set vtable
            auto vt = vtables[decl->type.print()];
            //use modified vtable of derived
            if (derived) {
                auto it = vtables.find(*derived + "." + decl->type.print());
                if (it != vtables.end()) {
                    vt = it->second;
                }
            }
            int vt_index = decl->fields.size() + (decl->base ? 1 : 0);
            auto vt_target = gep2(ptr, vt_index, ty);
            Builder->CreateStore(vt, vt_target);
        }
        int field_idx = 0;
        for (int i = 0; i < node->entries.size(); i++) {
            auto &e = node->entries[i];
            if (e.isBase) continue;
            FieldDecl *field;
            int real_idx;
            if (e.key) {
                auto index = fieldIndex(decl->fields, e.key.value(), decl->type);
                field = &decl->fields[index];
                real_idx = index;
            } else {
                real_idx = field_idx;
                field = &decl->fields[field_idx];
                ++field_idx;
            }
            if (decl->base) real_idx++;
            auto field_target_ptr = gep2(ptr, real_idx, ty);
            setField(e.value, field->type, field_target_ptr);
            curOwner.moveToField(e.value);
        }
    }
}

void Compiler::setFields(std::vector<FieldDecl> &fields, std::vector<Entry> &entries, BaseDecl *decl, llvm::Type *ty, llvm::Value *ptr) {
    int field_idx = 0;
    for (int i = 0; i < entries.size(); i++) {
        auto &e = entries[i];
        if (e.isBase) continue;
        FieldDecl *field;
        int real_idx;
        if (e.key) {
            auto index = fieldIndex(fields, e.key.value(), decl->type);
            field = &fields[index];
            real_idx = index;
        } else {
            real_idx = field_idx;
            field = &fields[field_idx];
            ++field_idx;
        }
        if (decl->base && decl->isClass()) real_idx++;
        auto field_target_ptr = gep2(ptr, real_idx, ty);
        setField(e.value, field->type, field_target_ptr);
        curOwner.moveToField(e.value);
    }
}

std::any Compiler::visitType(Type *node) {
    if (!node->scope) {
        throw std::runtime_error("type has no scope");
    }
    //enum variant without struct
    auto ptr = getAlloc(node);
    curOwner.addPtr(node, ptr);
    simpleVariant(*node, ptr);
    return ptr;
}

llvm::Value *Compiler::get_obj_ptr(Expression *e) {
    auto pe = dynamic_cast<ParExpr *>(e);
    if (pe) {
        e = pe->expr;
    }
    auto de = dynamic_cast<DerefExpr *>(e);
    if (de) {
        auto val = gen(de);
        return val;
    }
    auto val = gen(e);
    if (dynamic_cast<ObjExpr *>(e)) {
        return val;
    }
    auto sn = dynamic_cast<SimpleName *>(e);
    if (sn) {
        //local, localptr, prm, prm ptr, mut prm
        auto rt = resolv->resolve(e);
        if (rt.type.isPointer()) {
            //auto deref
            if (rt.vh->prm) {
                //always alloca
                return load(val, getPtr());
            } else {
                //local ptr
                return load(val, getPtr());
            }
        } else {
            if (rt.vh->prm) {
                //mut or not has no effect
                return val;
            } else {
                //local
                return val;
            }
        }
        //return val;
    }
    if (dynamic_cast<MethodCall *>(e)) {
        return val;
    }
    if (dynamic_cast<ArrayAccess *>(e) || dynamic_cast<FieldAccess *>(e)) {
        auto rt = resolv->resolve(e);
        if (rt.type.isPointer()) {
            //deref gep
            return load(val, getPtr());
        } else {
            return val;
        }
    }
    if (dynamic_cast<RefExpr *>(e) || dynamic_cast<Literal *>(e) || dynamic_cast<Unary *>(e) || dynamic_cast<AsExpr *>(e)) {
        return val;
    }

    throw std::runtime_error("get_obj_ptr " + e->print());
}

std::any Compiler::visitFieldAccess(FieldAccess *node) {
    auto rt = resolv->resolve(node->scope);
    auto scope = get_obj_ptr(node->scope);
    auto decl = rt.targetDecl;
    auto [sd, index] = resolv->findField(node->name, decl, rt.type);
    if (index == -1) {
        resolv->err(node, "internal error");
    }
    auto sd_ty = mapType(sd->type);
    if (sd->base) index++;
    return gep2(scope, index, sd_ty);
}

llvm::Value *Compiler::getTag(Expression *expr) {
    auto rt = resolv->resolve(expr);
    auto tag_idx = Layout::get_tag_index(rt.targetDecl);
    auto tag = get_obj_ptr(expr);
    tag = gep2(tag, tag_idx, rt.type.unwrap());
    return load(tag, getInt(ENUM_TAG_BITS));
}

std::any Compiler::visitIsExpr(IsExpr *node) {
    llvm::Value *tag1 = getTag(node->expr);
    llvm::Value *tag2;
    auto rhs_type = dynamic_cast<Type *>(node->rhs);
    if (rhs_type) {
        auto decl = (EnumDecl *) resolv->resolve(rhs_type).targetDecl;
        auto index = Resolver::findVariant(decl, rhs_type->name);
        tag2 = makeInt(index, ENUM_TAG_BITS);
    } else {
        tag2 = getTag(node->rhs);
    }
    return (llvm::Value *) Builder->CreateCmp(llvm::CmpInst::ICMP_EQ, tag1, tag2);
}

std::any Compiler::visitAsExpr(AsExpr *node) {
    auto lhs = resolv->getType(node->expr);
    auto ty = resolv->getType(&node->type);
    //ptr to int
    if (lhs.isPointer() && ty.print() == "u64") {
        auto val = get_obj_ptr(node->expr);
        return Builder->CreatePtrToInt(val, mapType(ty));
    }
    if (ty.isPrim()) {
        auto val = loadPtr(node->expr);
        return extend(val, lhs, ty, this);
    }
    return get_obj_ptr(node->expr);
}

std::any Compiler::slice(ArrayAccess *node, llvm::Value *sp, const Type &arrty) {
    auto val_start = cast(node->index, Type("i32"));
    //set array ptr
    auto src = gen(node->array);
    auto &elemty = *arrty.scope.get();
    if (arrty.isSlice()) {
        //deref inner pointer
        src = load(src, getPtr());
    } else if (arrty.isPointer()) {
        src = load(src);
    } else {
        //array
    }
    //shift by start
    auto ptr_ty = mapType(elemty);
    src = gep(src, val_start, ptr_ty);
    //i8*
    auto ptr_target = gep2(sp, SLICE_PTR_INDEX, sliceType);
    Builder->CreateStore(src, ptr_target);
    //set len
    auto len_target = gep2(sp, SLICE_LEN_INDEX, sliceType);
    auto val_end = cast(node->index2.get(), Type("i32"));
    auto len = Builder->CreateSub(val_end, val_start);
    len = Builder->CreateSExt(len, getInt(SLICE_LEN_BITS));
    Builder->CreateStore(len, len_target);
    return sp;
}

std::any Compiler::visitArrayAccess(ArrayAccess *node) {
    auto type = resolv->getType(node->array);
    if (node->index2) {
        auto sp = getAlloc(node);
        slice(node, sp, type);
        return sp;
    }
    auto src = get_obj_ptr(node->array);
    type = type.unwrap();
    if (type.isArray()) {
        //regular array access
        auto i1 = makeInt(0, 64);
        auto i2 = cast(node->index, Type("i64"));
        return gep(src, i1, i2, mapType(type));
    }
    //slice access
    auto elem = type.scope.get();
    auto elemty = mapType(*elem);
    //read array ptr
    auto arr = gep2(src, SLICE_PTR_INDEX, sliceType);
    arr = load(arr);
    auto index = cast(node->index, Type("i64"));
    return gep(arr, index, elemty);
}

std::any Compiler::visitArrayExpr(ArrayExpr *node) {
    auto ptr = getAlloc(node);
    //todo curOwner.addPtr(node, ptr);
    array(node, ptr);
    return ptr;
}

void Compiler::child(Expression *e, llvm::Value *ptr) {
    auto a = dynamic_cast<ArrayExpr *>(e);
    if (a) {
        array(a, ptr);
        return;
    }
    auto aa = dynamic_cast<ArrayAccess *>(e);
    if (aa) {
        auto arrty = resolv->getType(aa->array);
        slice(aa, ptr, arrty);
        return;
    }
    auto obj = dynamic_cast<ObjExpr *>(e);
    if (obj) {
        object(obj, ptr, resolv->resolve(obj), nullptr);
        return;
    }
    auto t = dynamic_cast<Type *>(e);
    if (t) {
        simpleVariant(*t, ptr);
        return;
    }
    auto mc = dynamic_cast<MethodCall *>(e);
    if (mc) {
        call(mc, ptr);
        return;
    }
    auto lit = dynamic_cast<Literal *>(e);
    if (lit) {
        strLit(ptr, lit);
        return;
    }
    error("child: " + e->print());
}

std::any Compiler::array(ArrayExpr *node, llvm::Value *ptr) {
    auto type = resolv->getType(node->list[0]);
    auto arr_ty = mapType(resolv->getType(node));
    if (!node->isSized()) {
        int i = 0;
        for (auto e : node->list) {
            auto elem_target = gep(ptr, 0, i, arr_ty);
            i++;
            setField(e, resolv->getType(e), elem_target);
        }
        return ptr;
    }
    auto elem = node->list[0];
    std::optional<llvm::Value *> elem_ptr;
    auto elem_ty = mapType(type);
    if (doesAlloc(elem)) {
        elem_ptr = gen(elem);
    }
    auto bb = Builder->GetInsertBlock();
    auto cur = gep(ptr, 0, 0, arr_ty);
    auto end = gep(ptr, 0, node->size.value(), arr_ty);
    //create cons and memcpy
    auto condbb = llvm::BasicBlock::Create(ctx(), "cond");
    auto setbb = llvm::BasicBlock::Create(ctx(), "set");
    auto nextbb = llvm::BasicBlock::Create(ctx(), "next");
    Builder->CreateBr(condbb);
    set_and_insert(condbb);
    auto phi_ty = elem_ty->getPointerTo();
    auto phi = Builder->CreatePHI(phi_ty, 2);
    phi->addIncoming(cur, bb);
    auto ne = Builder->CreateCmp(llvm::CmpInst::ICMP_NE, phi, end);
    Builder->CreateCondBr(branch(ne), setbb, nextbb);
    set_and_insert(setbb);
    if (elem_ptr) {
        copy(phi, elem_ptr.value(), type);
    } else {
        setField(node->list[0], type, phi);
    }
    auto step = gep(phi, 1, elem_ty);
    phi->addIncoming(step, setbb);
    Builder->CreateBr(condbb);
    set_and_insert(nextbb);
    return ptr;
}

std::any Compiler::visitAssertStmt(AssertStmt *node) {
    loc(node);
    auto str = node->expr->print();
    auto cond = loadPtr(node->expr.get());
    auto then = llvm::BasicBlock::Create(ctx(), "assert_body_" + std::to_string(node->line));
    auto next = llvm::BasicBlock::Create(ctx(), "assert_next_" + std::to_string(node->line));
    Builder->CreateCondBr(branch(cond), next, then);
    set_and_insert(then);
    //print error and exit
    auto msg = curMethod->path;
    msg += ":";
    msg += std::to_string(node->line);
    msg += "\n";
    msg += std::string("assertion ") + str + " failed in " + printMethod(curMethod) + "\n";
    std::vector<llvm::Value *> pr_args = {Builder->CreateGlobalStringPtr(msg)};
    Builder->CreateCall(printf_proto, pr_args, "");
    std::vector<llvm::Value *> args = {makeInt(1)};
    Builder->CreateCall(exit_proto, args);
    Builder->CreateUnreachable();
    set_and_insert(next);
    return nullptr;
}

std::any Compiler::visitIfStmt(IfStmt *node) {
    auto cond = branch(loadPtr(node->expr));
    auto then = llvm::BasicBlock::Create(ctx(), "if_then_" + std::to_string(node->line));
    auto elsebb = llvm::BasicBlock::Create(ctx(), "if_else_" + std::to_string(node->line));
    auto next = llvm::BasicBlock::Create(ctx(), "if_next_" + std::to_string(node->line));
    Builder->CreateCondBr(cond, then, elsebb);
    set_and_insert(then);
    resolv->newScope();
    int cur_scope = curOwner.last_scope->id;
    auto then_returns = ends_with_return(node->thenStmt.get());
    auto then_scope = curOwner.newScope(ScopeId::IF, then_returns, cur_scope, node->thenStmt->line);
    node->thenStmt->accept(this);
    if (!then_scope->ends_with_return) {
        auto &last_ins = Builder->GetInsertBlock()->back();
        if (!last_ins.isTerminator()) {
            curOwner.endScope(*then_scope);
        }
    }
    if (!isReturnLast(node->thenStmt.get())) {
        Builder->CreateBr(next);
    }
    set_and_insert(elsebb);
    curOwner.setScope(cur_scope);//else inserted into main scope, not then scope
    auto else_scope = curOwner.newScope(ScopeId::ELSE, false, cur_scope, node->thenStmt->line);
    else_scope->sibling = then_scope->id;
    then_scope->sibling = else_scope->id;
    if (node->elseStmt) {
        resolv->newScope();
        else_scope->ends_with_return = ends_with_return(node->elseStmt.get());
        else_scope->line = node->elseStmt->line;
        node->elseStmt->accept(this);
        if (!else_scope->ends_with_return) {
            curOwner.endScope(*else_scope);
            curOwner.end_branch(*else_scope);
        }
        if (!isReturnLast(node->elseStmt.get())) {
            Builder->CreateBr(next);
        } else {
            //return cleans all
        }
    } else {
        curOwner.endScope(*else_scope);
        curOwner.end_branch(*else_scope);
        Builder->CreateBr(next);
    }
    set_and_insert(next);
    auto then_clean = llvm::BasicBlock::Create(ctx(), "then_clean_" + std::to_string(node->line));
    auto next2 = llvm::BasicBlock::Create(ctx(), "next2_" + std::to_string(node->line));
    Builder->CreateCondBr(cond, then_clean, next2);
    set_and_insert(then_clean);
    curOwner.end_branch(*then_scope);
    Builder->CreateBr(next2);
    set_and_insert(next2);
    curOwner.setScope(cur_scope);
    return nullptr;
}


std::any Compiler::visitIfLetStmt(IfLetStmt *node) {
    auto decl = findEnum(node->type, resolv.get());
    auto rhs = get_obj_ptr(node->rhs.get());
    auto tag = gep2(rhs, Layout::get_tag_index(decl), decl->type);
    tag = load(tag, getInt(ENUM_TAG_BITS));

    auto index = Resolver::findVariant(decl, node->type.name);
    auto cmp = Builder->CreateCmp(llvm::CmpInst::ICMP_EQ, tag, makeInt(index, ENUM_TAG_BITS));

    auto then = llvm::BasicBlock::Create(ctx(), "if_then_" + std::to_string(node->line));
    auto elsebb = llvm::BasicBlock::Create(ctx(), "if_else_" + std::to_string(node->line));
    auto next = llvm::BasicBlock::Create(ctx(), "if_next_" + std::to_string(node->line));

    auto cond = branch(cmp);

    Builder->CreateCondBr(cond, then, elsebb);
    set_and_insert(then);
    resolv->newScope();
    int cur_scope = curOwner.last_scope->id;
    auto then_scope = curOwner.newScope(ScopeId::IF, ends_with_return(node->thenStmt.get()), cur_scope, node->thenStmt->line);
    curOwner.doMoveCall(node->rhs.get());

    auto &variant = decl->variants[index];
    if (!variant.fields.empty()) {
        //declare vars
        auto &fields = variant.fields;
        auto data_index = Layout::get_data_index(decl);
        auto dataPtr = gep2(rhs, data_index, decl->type);
        auto var_ty = get_variant_type(node->type, this);
        for (int i = 0; i < fields.size(); i++) {
            //regular var decl
            auto &fd = fields[i];
            auto arg = node->args[i];
            auto field_ptr = gep2(dataPtr, i, var_ty);
            auto alloc_ptr = varAlloc[getId(arg.name)];
            NamedValues[arg.name] = alloc_ptr;
            if (arg.ptr) {
                Builder->CreateStore(field_ptr, alloc_ptr);
                dbg_var(arg.name, node->rhs->line, 0, Type(Type::Pointer, fd.type));
            } else {
                if (fd.type.isPrim() || fd.type.isPointer()) {
                    Builder->CreateStore(load(field_ptr, mapType(fd.type)), alloc_ptr);
                } else {
                    //resolv->err("iflet deref");
                    copy(alloc_ptr, field_ptr, fd.type);
                    curOwner.add(fd.name, fd.type, alloc_ptr, arg.id, arg.line);
                }
                dbg_var(arg.name, node->rhs->line, 0, fd.type);
            }
        }
    }
    node->thenStmt->accept(this);
    if (!then_scope->ends_with_return) {
        curOwner.endScope(*then_scope);
    }
    if (!isReturnLast(node->thenStmt.get())) {
        Builder->CreateBr(next);
    }
    set_and_insert(elsebb);
    curOwner.setScope(cur_scope);//else inserted into main scope, not then scope
    auto else_scope = curOwner.newScope(ScopeId::ELSE, false, cur_scope, node->thenStmt->line);
    else_scope->sibling = then_scope->id;
    then_scope->sibling = else_scope->id;
    if (node->elseStmt) {
        resolv->newScope();
        else_scope->ends_with_return = ends_with_return(node->elseStmt.get());
        else_scope->line = node->elseStmt->line;
        node->elseStmt->accept(this);
        if (!else_scope->ends_with_return) {
            curOwner.endScope(*else_scope);
            curOwner.end_branch(*else_scope);
        }
        if (!isReturnLast(node->elseStmt.get())) {
            Builder->CreateBr(next);
        } else {
            //return cleans all
        }
    } else {
        curOwner.endScope(*else_scope);
        curOwner.end_branch(*else_scope);
        Builder->CreateBr(next);
    }
    set_and_insert(next);
    auto then_clean = llvm::BasicBlock::Create(ctx(), "then_clean_" + std::to_string(node->line));
    auto next2 = llvm::BasicBlock::Create(ctx(), "next2_" + std::to_string(node->line));
    Builder->CreateCondBr(cond, then_clean, next2);
    set_and_insert(then_clean);
    curOwner.end_branch(*then_scope);
    Builder->CreateBr(next2);
    set_and_insert(next2);
    curOwner.setScope(cur_scope);
    return nullptr;
}

std::any Compiler::visitWhileStmt(WhileStmt *node) {
    auto then = llvm::BasicBlock::Create(ctx(), "while_body_" + std::to_string(node->line));
    auto condbb = llvm::BasicBlock::Create(ctx(), "while_cond_" + std::to_string(node->line), func);
    auto next = llvm::BasicBlock::Create(ctx(), "while_next_" + std::to_string(node->line));
    Builder->CreateBr(condbb);
    Builder->SetInsertPoint(condbb);
    auto c = loadPtr(node->expr.get());
    Builder->CreateCondBr(branch(c), then, next);
    set_and_insert(then);
    loops.push_back(condbb);
    loopNext.push_back(next);
    resolv->newScope();
    auto cur_scope = curOwner.last_scope->id;
    auto then_scope = curOwner.newScope(ScopeId::WHILE, ends_with_return(node->body.get()), cur_scope, node->body->line);
    node->body->accept(this);
    curOwner.endScope(*then_scope);
    curOwner.setScope(cur_scope);
    loops.pop_back();
    loopNext.pop_back();
    Builder->CreateBr(condbb);
    set_and_insert(next);
    return nullptr;
}

std::any Compiler::visitForStmt(ForStmt *node) {
    auto cur_scope = curOwner.last_scope->id;
    auto then_scope = curOwner.newScope(ScopeId::FOR, ends_with_return(node->body.get()), cur_scope, node->body->line);
    resolv->newScope();
    if (node->decl) {
        node->decl->accept(this);
    }
    auto then = llvm::BasicBlock::Create(ctx(), "body");
    auto condbb = llvm::BasicBlock::Create(ctx(), "cont_test", func);
    auto updatebb = llvm::BasicBlock::Create(ctx(), "update", func);
    auto next = llvm::BasicBlock::Create(ctx(), "next");
    Builder->CreateBr(condbb);
    Builder->SetInsertPoint(condbb);
    if (node->cond) {
        auto c = loadPtr(node->cond.get());
        Builder->CreateCondBr(branch(c), then, next);
    } else {
        Builder->CreateBr(then);
    }
    set_and_insert(then);
    loops.push_back(updatebb);
    loopNext.push_back(next);
    int backup = resolv->max_scope;
    node->body->accept(this);
    curOwner.endScope(*then_scope);
    curOwner.setScope(cur_scope);
    int backup2 = resolv->max_scope;
    resolv->max_scope = backup;
    Builder->CreateBr(updatebb);
    Builder->SetInsertPoint(updatebb);
    for (auto &u : node->updaters) {
        u->accept(this);
    }
    resolv->max_scope = backup2;
    loops.pop_back();
    loopNext.pop_back();
    Builder->CreateBr(condbb);
    set_and_insert(next);
    return {};
}

std::any Compiler::visitContinueStmt(ContinueStmt *node) {
    curOwner.jump_continue();
    Builder->CreateBr(loops.back());
    return nullptr;
}

std::any Compiler::visitBreakStmt(BreakStmt *node) {
    curOwner.jump_break();
    Builder->CreateBr(loopNext.back());
    return nullptr;
}