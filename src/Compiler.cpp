#include "Compiler.h"
#include "Resolver.h"
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
#include <llvm/Support/FileSystem.h>
#include <llvm/Support/Host.h>
#include <llvm/Support/TargetRegistry.h>
#include <llvm/Support/TargetSelect.h>
#include <llvm/Target/TargetOptions.h>


namespace fs = std::filesystem;

const int SLICE_LEN_INDEX = 1;

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
    std::cout << "triple: " << TargetTriple << std::endl;
    std::cout << "target: " << Target->getName() << std::endl;

    if (!Target) {
        throw std::runtime_error(Error);
    }
    auto CPU = "generic";
    auto Features = "";

    llvm::TargetOptions opt;
    auto RM = llvm::Optional<llvm::Reloc::Model>();
    TargetMachine = Target->createTargetMachine(TargetTriple, CPU, Features, opt, RM);
}

void Compiler::compileAll() {
    init();
    //prelude
    for (auto &pre : Resolver::prelude) {
        Resolver::getResolver(srcDir + "/" + pre + ".x", srcDir);
    }
    std::string cmd = "clang-13 ";
    for (const auto &e : fs::recursive_directory_iterator(srcDir)) {
        if (e.is_directory()) continue;
        auto obj = compile(e.path().string());
        if (obj) {
            cmd.append(obj.value());
            cmd.append(" ");
        }
    }
    system("rm a.out");
    system((cmd + " && ./a.out").c_str());
    for (auto &[k, v] : Resolver::resolverMap) {
        v.reset();
        //v->unit.reset();
    }
}

void Compiler::emit(std::string &Filename) {
    if (debug) DBuilder->finalize();
    //todo init once
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
    std::cout << "writing " << Filename << std::endl;
}

void initModule(const std::string &path, Compiler *c) {
    auto name = getName(path);
    if (!c->ctxp)
        c->ctxp = std::make_unique<llvm::LLVMContext>();
    c->mod = std::make_unique<llvm::Module>(name, c->ctx());
    c->mod->setDataLayout("e-m:e-i8:8:32-i16:16:32-i64:64-i128:128-n32:64-S128");
    c->mod->setTargetTriple(c->TargetTriple);
    c->Builder = std::make_unique<llvm::IRBuilder<>>(c->ctx());
    if (c->debug) {
        c->DBuilder = std::make_unique<llvm::DIBuilder>(*c->mod);
        auto dfile = c->DBuilder->createFile(path, ".");
        c->di.cu = c->DBuilder->createCompileUnit(llvm::dwarf::DW_LANG_C_plus_plus_14, dfile, "lang dbg", false, "", 0);
        c->mod->addModuleFlag(llvm::Module::Warning, "Dwarf Version", 4);
        c->mod->addModuleFlag(llvm::Module::Warning, "Debug Info Version", 3);
    }
    c->mod->addModuleFlag(llvm::Module::Warning, "branch-target-enforcement", (uint32_t) 0);
    c->mod->addModuleFlag(llvm::Module::Warning, "sign-return-address", (uint32_t) 0);
    c->mod->addModuleFlag(llvm::Module::Warning, "sign-return-address-all", (uint32_t) 0);
    c->mod->addModuleFlag(llvm::Module::Warning, "sign-return-address-with-bkey", (uint32_t) 0);
    c->mod->addModuleFlag(llvm::Module::Warning, "uwtable", (uint32_t) 0);
    c->mod->addModuleFlag(llvm::Module::Warning, "frame-pointer", (uint32_t) 0);
}

std::optional<std::string> Compiler::compile(const std::string &path) {
    auto name = getName(path);
    if (path.compare(path.size() - 2, 2, ".x") != 0) {
        //copy res
        std::ifstream src;
        src.open(path, src.binary);
        std::ofstream trg;
        trg.open(outDir + "/" + name, trg.binary);
        trg << src.rdbuf();
        return {};
    }
    std::cout << "compiling " << path << std::endl;
    resolv = Resolver::getResolver(path, srcDir);
    unit = resolv->unit;
    resolv->resolveAll();

    initModule(path, this);
    createProtos();

    for (auto &m : getMethods(unit.get())) {
        genCode(m);
    }
    for (auto m : resolv->generatedMethods) {
        genCode(m);
    }

    llvm::verifyModule(*mod, &llvm::outs());

    //emit llvm
    auto noext = trimExtenstion(name);
    auto llvm_file = noext + ".ll";
    std::error_code ec;
    llvm::raw_fd_ostream fd(llvm_file, ec);
    mod->print(fd, nullptr);
    print("writing " + llvm_file);

    //todo fullpath
    auto outFile = noext + ".o";
    emit(outFile);
    cleanup();
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
}

llvm::Value *Compiler::branch(llvm::Value *val) {
    auto ty = llvm::cast<llvm::IntegerType>(val->getType());
    if (ty) {
        auto w = ty->getBitWidth();
        if (w != 1) {
            return Builder->CreateTrunc(val, getInt(1));
        }
    }
    return val;
}

bool isObj(Expression *e) {
    auto obj = dynamic_cast<ObjExpr *>(e);
    return obj && !obj->isPointer || dynamic_cast<Type *>(e);
}

bool need_alloc(Method &m, std::string &name, Type *type, Compiler *c) {
    auto it = c->resolv->mut_params.find(prm_id(m, name));
    if (it == c->resolv->mut_params.end()) return false;//not mutated
    auto kind = it->second;
    return kind == MutKind::WHOLE || isStruct(type);
}

bool need_alloc(Method &m, Param &p, Compiler *c) {
    auto type = p.type.get();
    return need_alloc(m, p.name, type, c);
}

llvm::Value *Compiler::load(llvm::Value *val) {
    auto ty = val->getType()->getPointerElementType();
    return Builder->CreateLoad(ty, val);
}

bool isPtr(llvm::Value *val) {
    return val->getType()->isPointerTy();
}

bool isVar(Expression *e) {
    if (dynamic_cast<DerefExpr *>(e)) {
        return true;
    }
    return dynamic_cast<SimpleName *>(e) ||
           dynamic_cast<FieldAccess *>(e) ||
           dynamic_cast<ArrayAccess *>(e);
}

bool isAlloc(Expression *e, Compiler *c) {
    if (dynamic_cast<SimpleName *>(e)) {
        auto rt = c->resolv->resolve(e);
        if (rt.vh && rt.vh->prm) return need_alloc(*c->curMethod, rt.vh->name, rt.type, c);
        return true;//local
    }
    return false;
}

//load if alloca
llvm::Value *Compiler::loadPtr(Expression *e) {
    auto val = gen(e);
    auto rt = resolv->resolve(e);
    if (!isVar(e)) return val;
    if (rt.vh && rt.vh->prm) {
        auto alc = need_alloc(*curMethod, rt.vh->name, rt.type, this);
        if (!alc) return val;
    }
    //local, fa, aa
    return load(val);
}

llvm::Value *Compiler::loadPtr(std::unique_ptr<Expression> &e) {
    return loadPtr(e.get());
}

llvm::Value *extend(llvm::Value *val, Type *type, Compiler *c) {
    int src = val->getType()->getPrimitiveSizeInBits();
    int bits = c->getSize(type);
    if (src < bits) {
        return c->Builder->CreateZExt(val, c->getInt(bits));
    }
    if (src > bits) {
        return c->Builder->CreateTrunc(val, c->getInt(bits));
    }
    return val;
}

llvm::Value *Compiler::cast(Expression *expr, Type *type) {
    auto lit = dynamic_cast<Literal *>(expr);
    if (lit && lit->type == Literal::INT) {
        auto bits = getSize(type);
        if (lit->suffix) {
            bits = getSize(lit->suffix.get());
        }
        return llvm::ConstantInt::get(getInt(bits), atoi(lit->val.c_str()));
    }
    auto val = loadPtr(expr);
    if (type->isPrim()) {
        return extend(val, type, this);
    }
    return val;
}

void Compiler::setField(Expression *expr, Type *type, bool do_cast, llvm::Value *ptr) {
    if (do_cast) {
        auto targetTy = mapType(type);
        ptr = Builder->CreateBitCast(ptr, targetTy->getPointerTo());
    }
    auto de = dynamic_cast<DerefExpr *>(expr);
    if (de) {
        if (isStruct(type)) {
            auto val = gen(de->expr.get());
            copy(ptr, val, type);
            return;
        }
    }
    if (is_simple_enum(type)) {
        auto val = gen(expr);
        if (val->getType()->isPointerTy()) {
            val = load(val);
        }
        Builder->CreateStore(val, ptr);
    } else if (doesAlloc(expr)) {
        child(expr, ptr);
    } else if (isStruct(type) && !dynamic_cast<MethodCall *>(expr)) {//todo mc
        auto val = gen(expr);
        copy(ptr, val, type);
    } else {
        auto val = cast(expr, type);
        Builder->CreateStore(val, ptr);
    }
}

void Compiler::make_proto(std::unique_ptr<Method> &m) {
    make_proto(m.get());
}

void Compiler::make_proto(Method *m) {
    if (m->isGeneric) {
        return;
    }
    resolv->curMethod = m;
    std::vector<llvm::Type *> argTypes;
    bool rvo = isRvo(m);
    if (rvo) {
        argTypes.push_back(mapType(m->type.get())->getPointerTo());
    }
    if (m->self) {
        auto st = m->self->type.get();
        auto real = PointerType::unwrap(st);
        if (is_simple_enum(real)) {
            st = real;
        }
        auto ty = mapType(st);
        argTypes.push_back(ty);
    }
    for (auto &prm : m->params) {
        auto ty = mapType(prm.type.get());
        if (isStruct(prm.type.get()) && !is_simple_enum(prm.type.get())) {
            //structs are always pass by ptr
            ty = ty->getPointerTo();
        }
        argTypes.push_back(ty);
    }
    llvm::Type *retType;
    if (rvo) {
        retType = Builder->getVoidTy();
    } else {
        retType = mapType(m->type.get());
    }
    auto mangled = mangle(m);
    auto fr = llvm::FunctionType::get(retType, argTypes, false);
    auto linkage = llvm::Function::ExternalLinkage;
    if (!m->typeArgs.empty()) {
        linkage = llvm::Function::LinkOnceODRLinkage;
    }
    auto f = llvm::Function::Create(fr, linkage, mangled, *mod);
    f->addFnAttr(llvm::Attribute::MustProgress);
    f->addFnAttr(llvm::Attribute::NoInline);
    f->addFnAttr(llvm::Attribute::NoUnwind);
    f->addFnAttr(llvm::Attribute::OptimizeNone);
    f->addFnAttr(llvm::Attribute::UWTable);
    f->addFnAttr("frame-pointer", "non-leaf");
    f->addFnAttr("min-legal-vector-width", "0");
    f->addFnAttr("no-trapping-math", "true");
    f->addFnAttr("stack-protector-buffer-size", "8");
    f->addFnAttr("target-cpu", "generic");
    f->addFnAttr("target-features", "+neon,+outline-atomics");
    int i = 0;
    if (rvo) {
        f->getArg(0)->setName("ret");
        f->getArg(0)->addAttr(llvm::Attribute::StructRet);
        i++;
    }
    if (m->self) {
        f->getArg(i)->setName(m->self->name);
        i++;
    }
    for (int pi = 0; i < f->arg_size(); i++) {
        f->getArg(i)->setName(m->params[pi++].name);
    }
    funcMap[mangled] = f;
    resolv->curMethod = nullptr;
    if (m->isVirtual) virtuals.push_back(m);
}

std::vector<Method *> getVirtual(StructDecl *decl, Unit *unit) {
    std::vector<Method *> arr;
    for (auto &item : unit->items) {
        if (!item->isImpl()) continue;
        auto imp = (Impl *) item.get();
        if (imp->type->name != decl->type->name) continue;
        for (auto &m : imp->methods) {
            if (m.isVirtual) {
                arr.push_back(&m);
            }
        }
    }
    return arr;
}

llvm::Type *Compiler::makeDecl(BaseDecl *bd) {
    if (bd->isGeneric) {
        return nullptr;
    }
    if (bd->type->print() == "str") {
        return stringType;
    }
    auto mangled = bd->type->print();
    auto it = classMap.find(mangled);
    if (it != classMap.end()) return (llvm::StructType *) it->second;
    std::vector<llvm::Type *> elems;
    if (bd->isEnum()) {
        auto ed = dynamic_cast<EnumDecl *>(bd);
        if (Resolver::is_simple_enum(ed)) {
            auto ty = getInt(ENUM_INDEX_SIZE);
            classMap[mangled] = ty;
            return ty;
        }
        //ordinal, i32
        elems.push_back(getInt(ENUM_INDEX_SIZE));
        //data, i8*
        auto sz = getSize(ed);
        elems.push_back(llvm::ArrayType::get(getInt(8), (sz - ENUM_INDEX_SIZE) / 8));
    } else {
        auto td = dynamic_cast<StructDecl *>(bd);
        if (td->base) {
            elems.push_back(mapType(td->base.get()));
        }
        for (auto &field : td->fields) {
            elems.push_back(mapType(field.type));
        }
        if (!getVirtual(td, unit.get()).empty()) {
            elems.push_back(getInt(8)->getPointerTo()->getPointerTo());
        }
    }
    auto ty = llvm::StructType::create(ctx(), elems, mangled);
    classMap[mangled] = ty;
    return ty;
}

void Compiler::createProtos() {
    std::vector<BaseDecl *> list;
    for (auto bd : getTypes(unit.get())) {
        if (bd->isGeneric) continue;
        list.push_back(bd);
    }
    for (auto gt : resolv->genericTypes) {
        list.push_back(gt);
    }
    for (auto bd : resolv->usedTypes) {
        list.push_back(bd);
    }
    sort(list);
    for (auto bd : list) {
        makeDecl(bd);
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
    exit_proto = make_exit();
    mallocf = make_malloc();
    if (!sliceType) {
        sliceType = make_slice_type();
    }
    if (!stringType) {
        stringType = make_string_type();
    }
    make_vtables();
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
        auto p = PointerType::unwrap(m->self->type.get())->print();
        map[p].push_back(m);
        virtualIndex[m] = map[p].size() - 1;
    }
    //override
    std::vector<std::string> done;
    for (auto [df, basef] : resolv->overrideMap) {
        auto base = PointerType::unwrap(basef->self->type.get())->print();
        auto key = PointerType::unwrap(df->self->type.get())->print() + "." + base;
        if (std::find(done.begin(), done.end(), key) != done.end()) {
            continue;
        }
        done.push_back(key);
        auto &vt = map[base];
        auto dvt = vt;
        //now update base vt by overrides
        dvt[find_idx(vt, df)] = df;
        //other bases can override other methods of base
        auto decl = resolv->resolve(df->self->type.get()).targetDecl;
        std::map<Method *, Type *> mrm;
        mrm[basef] = df->self->type.get();
        while (decl->base && decl->base->print() != base) {
            for (auto [k2, v2] : resolv->overrideMap) {
                //check we override same vt
                if (v2->self->type->print() != base) continue;
                //prevent my upper overriding base bc we care below us
                if (Resolver::do_override(k2, basef)) continue;
                //if(k2->self->type->print() != decl->base->print()) continue;
                //keep outermost
                auto it = mrm[v2];
                if (it) {
                    //already overrode, keep outermost
                    if (resolv->is_base_of(k2->self->type.get(), resolv->resolve(it).targetDecl)) {
                        continue;
                    }
                }
                dvt[find_idx(vt, k2)] = k2;
                mrm[v2] = PointerType::unwrap(k2->self->type.get());
            }
            decl = resolv->resolve(decl->base.get()).targetDecl;
        }
        map[key] = dvt;
    }
    for (auto &[k, v] : map) {
        auto i8p = getInt(8)->getPointerTo();
        auto arrt = llvm::ArrayType::get(i8p, 1);
        auto linkage = llvm::GlobalValue::ExternalLinkage;
        std::vector<llvm::Constant *> arr;
        for (auto m : v) {
            auto f = funcMap[mangle(m)];
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
    auto ff = funcMap[mangle(m)];
    int arg_idx = 0;
    if (isRvo(m)) arg_idx++;
    if (m->self) {
        auto &prm = *m->self;
        llvm::Value *arg = ff->getArg(arg_idx++);
        if (need_alloc(*m, prm, this)) {
            auto ty = mapType(prm.type.get());
            auto ptr = Builder->CreateAlloca(ty);
            NamedValues[prm.name] = ptr;
        } else {
            NamedValues[prm.name] = arg;
        }
    }
    for (auto &prm : m->params) {
        llvm::Value *arg = ff->getArg(arg_idx++);
        //non mut structs dont need alloc
        if (!need_alloc(*m, prm, this)) {
            NamedValues[prm.name] = arg;
        } else {
            auto ty = mapType(prm.type.get());
            auto ptr = Builder->CreateAlloca(ty);
            NamedValues[prm.name] = ptr;
        }
    }
}

void dbg_prm(Param &p, int idx, llvm::Function *func, Compiler *c) {
    if (!c->debug) return;
    auto sp = c->di.sp;
    llvm::DIType *dt;
    if (isStruct(p.type.get())) {
        dt = c->map_di(new PointerType(p.type.get()));
    } else {
        dt = c->map_di(p.type.get());
    }
    auto v = c->DBuilder->createParameterVariable(sp, p.name, idx, c->di.file, p.line, dt, true);
    auto val = c->NamedValues[p.name];
    auto lc = llvm::DILocation::get(sp->getContext(), p.line, p.pos, sp);
    c->DBuilder->insertDeclare(val, v, c->DBuilder->createExpression(), lc, c->Builder->GetInsertBlock());
}

void storeParams(Method *m, Compiler *c) {
    auto func = c->funcMap[mangle(m)];
    int argIdx = c->isRvo(m) ? 1 : 0;
    int didx = 1;
    if (m->self) {
        if (need_alloc(*m, *m->self, c)) {
            auto ptr = c->NamedValues[m->self->name];
            auto val = func->getArg(argIdx);
            if (isStruct(m->self->type.get())) {
                c->copy(ptr, val, m->self->type.get());
            } else {
                c->Builder->CreateStore(val, ptr);
            }
        }
        dbg_prm(*m->self, didx++, func, c);
        argIdx++;
    }
    for (auto i = 0; i < m->params.size(); i++) {
        auto &prm = m->params[i];
        auto val = func->getArg(argIdx++);
        auto ptr = c->NamedValues[prm.name];
        if (need_alloc(*m, prm, c)) {
            if (isStruct(prm.type.get())) {
                c->copy(ptr, val, prm.type.get());
            } else {
                c->Builder->CreateStore(val, ptr);
            }
        }
        dbg_prm(prm, didx++, func, c);
    }
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

void Compiler::loc(Node *e) {
    if (!debug) return;
    if (!e) {
        Builder->SetCurrentDebugLocation(0);
        return;
    }
    if (e->line == 0) {
        auto expr = dynamic_cast<Expression *>(e);
        if (expr)
            error(std::string("line 0, ") + expr->print());
        else
            error(std::string("line 0, ") + typeid(*e).name());
    }
    loc(e->line, 0);
}

void Compiler::loc(int line, int pos) {
    if (!debug) return;
    auto scope = di.sp;
    if (!scope) {
        scope = di.cu;
    }
    Builder->SetCurrentDebugLocation(llvm::DILocation::get(scope->getContext(), line, pos, scope));
}

void dbg_var(Fragment &f, Type *type, Compiler *c) {
    if (!c->debug) return;
    auto sp = c->di.sp;
    //auto ff = c->DBuilder->createFile(c->di.cu->getFilename(), c->di.cu->getDirectory());
    auto v = c->DBuilder->createAutoVariable(sp, f.name, c->di.file, f.line, c->map_di(type), true);
    auto val = c->NamedValues[f.name];
    auto lc = llvm::DILocation::get(sp->getContext(), f.line, f.pos, sp);
    auto e = c->DBuilder->createExpression();
    c->DBuilder->insertDeclare(val, v, e, lc, c->Builder->GetInsertBlock());
}

void dbg_func(Method *m, llvm::Function *func, Compiler *c) {
    if (!c->debug) return;
    llvm::SmallVector<llvm::Metadata *, 8> tys;
    tys.push_back(c->map_di(m->type.get()));
    if (m->self) {
        tys.push_back(c->map_di(m->self->type.get()));
    }
    for (auto &p : m->params) {
        tys.push_back(c->map_di(p.type.get()));
    }
    auto ft = c->DBuilder->createSubroutineType(c->DBuilder->getOrCreateTypeArray(tys));
    auto file = c->DBuilder->createFile(m->unit->path, ".");
    c->di.file = file;
    std::string linkage_name;
    auto spflags = llvm::DISubprogram::SPFlagDefinition;
    if (m->name == "main") {
        spflags |= llvm::DISubprogram::SPFlagMainSubprogram;
    } else {
        linkage_name = mangle(m);
    }
    auto name = methodParent(m);
    auto sp = c->DBuilder->createFunction(file, name, linkage_name, file, m->line, ft, m->line, llvm::DINode::FlagPrototyped, spflags);
    c->di.sp = sp;
    func->setSubprogram(sp);
    c->loc(nullptr);
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
    func = funcMap[mangle(m)];
    NamedValues.clear();
    auto bb = llvm::BasicBlock::Create(ctx(), "", func);
    Builder->SetInsertPoint(bb);
    //dbg
    if (debug) {
        dbg_func(m, func, this);
    }
    allocParams(m);
    makeLocals(m->body.get());
    storeParams(curMethod, this);
    m->body->accept(this);
    if (!isReturnLast(m->body.get()) && m->type->print() == "void") {
        if (!m->body->list.empty()) {
            loc(m->body->list.back()->line + 1, 0);
        }
        Builder->CreateRetVoid();
    }
    if (debug) {
        DBuilder->finalizeSubprogram((llvm::DISubprogram *) di.sp);
        di.sp = nullptr;
    }
    llvm::verifyFunction(*func);
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

std::any Compiler::visitBlock(Block *b) {
    for (auto &s : b->list) {
        s->accept(this);
    }
    return nullptr;
}

std::any Compiler::visitReturnStmt(ReturnStmt *t) {
    loc(t);
    if (!t->expr) {
        return Builder->CreateRetVoid();
    }
    if (!isStruct(curMethod->type.get())) {
        auto type = resolv->getType(curMethod->type.get());
        return Builder->CreateRet(cast(t->expr.get(), type));
    }
    if (is_simple_enum(curMethod->type.get())) {
        auto val = gen(t->expr.get());
        if (isAlloc(t->expr.get(), this)) {
            val = load(val);
        }
        return Builder->CreateRet(val);
    }
    //rvo
    auto ptr = func->getArg(0);
    if (doesAlloc(t->expr.get())) {
        child(t->expr.get(), ptr);
        return Builder->CreateRetVoid();
    }
    auto val = gen(t->expr.get());
    copy(ptr, val, resolv->getType(t->expr.get()));
    return Builder->CreateRetVoid();
}

std::any Compiler::visitExprStmt(ExprStmt *b) {
    return b->expr->accept(this);
}

std::any Compiler::visitParExpr(ParExpr *i) {
    return i->expr->accept(this);
}

bool is_logic(Expression *e) {
    auto p = dynamic_cast<ParExpr *>(e);
    if (p) return is_logic(p->expr);
    auto i = dynamic_cast<Infix *>(e);
    if (i) return (i->op == "&&") || (i->op == "||");
    return false;
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
    auto rbit = Builder->CreateTrunc(r, getInt(1));
    Builder->CreateBr(next);
    Builder->SetInsertPoint(next);
    func->getBasicBlockList().push_back(next);
    auto phi = Builder->CreatePHI(getInt(1), 2);
    phi->addIncoming(isand ? Builder->getFalse() : Builder->getTrue(), bb);
    phi->addIncoming(rbit, then);
    return {Builder->CreateZExt(phi, getInt(1)), next};
}

std::any Compiler::visitInfix(Infix *i) {
    loc(i->left);
    if (i->op == "&&" || i->op == "||") {
        return andOr(i).first;
    }
    auto lt = resolv->resolve(i->left);
    auto t1 = lt.type->print();
    auto t2 = resolv->resolve(i->right).type->print();
    auto t3 = t1 == "bool" ? new Type("i1") : binCast(t1, t2).type;
    auto l = cast(i->left, t3);
    auto r = cast(i->right, t3);
    if (isComp(i->op)) {
        if (i->op == "==") {
            /*if(lt.targetDecl){
                auto idx_ptr = Builder->CreateStructGEP(l->getType()->getPointerElementType(), l, 0);
                auto idx_ptr2 = Builder->CreateStructGEP(r->getType()->getPointerElementType(), r, 0);
                l = load(idx_ptr);
                r = load(idx_ptr2);
            }*/
            return Builder->CreateCmp(llvm::CmpInst::ICMP_EQ, l, r);
        }
        if (i->op == "!=") {
            return Builder->CreateCmp(llvm::CmpInst::ICMP_NE, l, r);
        }
        if (i->op == "<") {
            return Builder->CreateCmp(llvm::CmpInst::ICMP_SLT, l, r);
        }
        if (i->op == ">") {
            return Builder->CreateCmp(llvm::CmpInst::ICMP_SGT, l, r);
        }
        if (i->op == "<=") {
            return Builder->CreateCmp(llvm::CmpInst::ICMP_SLE, l, r);
        }
        if (i->op == ">=") {
            return Builder->CreateCmp(llvm::CmpInst::ICMP_SGE, l, r);
        }
    }
    if (i->op == "+") {
        return Builder->CreateNSWAdd(l, r);
    }
    if (i->op == "-") {
        return Builder->CreateNSWSub(l, r);
    }
    if (i->op == "*") {
        return Builder->CreateNSWMul(l, r);
    }
    if (i->op == "/") {
        return Builder->CreateSDiv(l, r);
    }
    if (i->op == "%") {
        return Builder->CreateSRem(l, r);
    }
    if (i->op == "^") {
        return Builder->CreateXor(l, r);
    }
    if (i->op == "&") {
        return Builder->CreateAnd(l, r);
    }
    if (i->op == "|") {
        return Builder->CreateOr(l, r);
    }
    if (i->op == "<<") {
        return Builder->CreateShl(l, r);
    }
    if (i->op == ">>") {
        return Builder->CreateAShr(l, r);
    }
    throw std::runtime_error("infix: " + i->print());
}

std::any Compiler::visitUnary(Unary *u) {
    loc(u);
    auto val = loadPtr(u->expr);
    llvm::Value *res;
    if (u->op == "+") {
        res = val;
    } else if (u->op == "-") {
        res = (llvm::Value *) Builder->CreateNSWSub(makeInt(0), val);
    } else if (u->op == "++") {
        auto v = gen(u->expr);
        auto bits = val->getType()->getPrimitiveSizeInBits();
        res = Builder->CreateNSWAdd(val, makeInt(1, bits));
        Builder->CreateStore(res, v);
    } else if (u->op == "--") {
        auto v = gen(u->expr);
        res = Builder->CreateNSWSub(val, makeInt(1));
        Builder->CreateStore(res, v);
    } else if (u->op == "!") {
        res = Builder->CreateTrunc(val, getInt(1));
        res = Builder->CreateXor(res, Builder->getTrue());
        res = Builder->CreateZExt(res, getInt(8));
    } else if (u->op == "~") {
        res = (llvm::Value *) Builder->CreateXor(val, makeInt(-1));
    } else {
        throw std::runtime_error("Unary: " + u->print());
    }
    return res;
}

std::any Compiler::visitAssign(Assign *i) {
    loc(i);
    auto de = dynamic_cast<DerefExpr *>(i->left);
    if (de) print(i->print());
    llvm::Value *l;
    if (de) {
        l = gen(de->expr.get());
        if (isAlloc(de->expr.get(), this)) {
            l = load(l);
        }
    } else {
        l = gen(i->left);
    }
    auto val = l;
    auto lt = resolv->getType(i->left);
    if (i->op == "=") {
        setField(i->right, lt, false, l);
        return l;
    }
    auto r = cast(i->right, lt);
    if (isVar(i->left)) {
        val = load(l);
    }
    if (i->op == "+=") {
        auto tmp = Builder->CreateNSWAdd(val, r);
        return (llvm::Value *) Builder->CreateStore(tmp, l);
    }
    if (i->op == "-=") {
        auto tmp = Builder->CreateNSWSub(val, r);
        return (llvm::Value *) Builder->CreateStore(tmp, l);
    }
    if (i->op == "*=") {
        auto tmp = Builder->CreateNSWMul(val, r);
        return (llvm::Value *) Builder->CreateStore(tmp, l);
    }
    if (i->op == "/=") {
        auto tmp = Builder->CreateSDiv(val, r);
        return (llvm::Value *) Builder->CreateStore(tmp, l);
    }
    throw std::runtime_error("assign: " + i->print());
}

std::any Compiler::visitSimpleName(SimpleName *n) {
    auto it = NamedValues.find(n->name);
    if (it != NamedValues.end()) {
        return it->second;
    }
    throw std::runtime_error("compiler bug; sym not found: " + n->name + " in " + curMethod->name);
}

llvm::Value *callMalloc(llvm::Value *sz, Compiler *c) {
    std::vector<llvm::Value *> args = {sz};
    return (llvm::Value *) c->Builder->CreateCall(c->mallocf, args);
}

std::any callPanic(MethodCall *mc, Compiler *c) {
    std::string message;
    if (mc->args.empty()) {
        message = "panic";
    } else {
        auto val = dynamic_cast<Literal *>(mc->args[0])->val;
        message = "panic: " + val.substr(1, val.size() - 2);
    }
    message.append("\n");
    auto str = c->Builder->CreateGlobalStringPtr(message);
    std::vector<llvm::Value *> args;
    args.push_back(str);
    if (!mc->args.empty()) {
        for (int i = 1; i < mc->args.size(); ++i) {
            auto a = mc->args[i];
            auto av = c->loadPtr(a);
            args.push_back(av);
        }
    }
    auto call = c->Builder->CreateCall(c->printf_proto, args);
    std::vector<llvm::Value *> exit_args = {c->makeInt(1)};
    c->Builder->CreateCall(c->exit_proto, exit_args);
    c->Builder->CreateUnreachable();
    return (llvm::Value *) c->Builder->getVoidTy();
}

void callPrint(MethodCall *mc, Compiler *c) {
    std::vector<llvm::Value *> args;
    for (auto a : mc->args) {
        if (isStrLit(a)) {
            auto l = dynamic_cast<Literal *>(a);
            auto str = c->Builder->CreateGlobalStringPtr(l->val.substr(1, l->val.size() - 2));
            args.push_back(str);
        } else {
            auto arg_type = c->resolv->getType(a);
            if (arg_type->isString()) {
                auto src = c->gen(a);
                //get ptr to inner char array
                if (src->getType()->isPointerTy()) {
                    auto slice = c->Builder->CreateStructGEP(src->getType()->getPointerElementType(), src, 0);
                    auto str = c->Builder->CreateLoad(c->getInt(8)->getPointerTo(), slice);
                    args.push_back(str);
                } else {
                    args.push_back(src);
                }
            } else {
                auto av = c->loadPtr(a);
                args.push_back(av);
            }
        }
    }
    c->Builder->CreateCall(c->printf_proto, args);
}

std::any Compiler::visitMethodCall(MethodCall *mc) {
    loc(mc);
    if (mc->name == "print" && !mc->scope) {
        callPrint(mc, this);
        return nullptr;
    } else if (mc->name == "malloc" && !mc->scope) {
        auto lt = new Type("i64");
        auto size = cast(mc->args[0], lt);
        if (!mc->typeArgs.empty()) {
            int typeSize = getSize(mc->typeArgs[0]) / 8;
            size = Builder->CreateNSWMul(size, makeInt(typeSize, 64));
        }
        auto call = callMalloc(size, this);
        auto rt = resolv->getType(mc);
        return Builder->CreateBitCast(call, mapType(rt));
    } else if (mc->name == "panic" && !mc->scope) {
        return callPanic(mc, this);
    }
    auto rt = resolv->resolve(mc);
    auto target = rt.targetMethod;
    if (isRvo(target)) {
        return call(mc, getAlloc(mc));
    } else {
        return call(mc, nullptr);
    }
}

bool isAlloc(Expression *e, llvm::Value *val) {
    if (dynamic_cast<FieldAccess *>(e)) return true;
    if (!dynamic_cast<SimpleName *>(e)) return false;
    if (dynamic_cast<RefExpr *>(e)) return true;
    if (llvm::isa<llvm::AllocaInst>(val)) {
        return true;
    }
    return false;
}

llvm::Value *Compiler::call(MethodCall *mc, llvm::Value *ptr) {
    auto rt = resolv->resolve(mc);
    auto target = rt.targetMethod;
    auto f = funcMap[mangle(target)];
    std::vector<llvm::Value *> args;
    int paramIdx = 0;
    if (ptr) {
        args.push_back(ptr);
    }
    llvm::Value *obj = nullptr;
    RType scp;
    if (target->self && !dynamic_cast<Type *>(mc->scope.get())) {
        //add this object
        auto e = mc->scope.get();
        obj = gen(e);
        scp = resolv->resolve(e);
        auto scope_type = scp.type;
        if (scope_type->isPointer() && isAlloc(e, obj) ||
            (scope_type->isPrim() && isVar(e) && !scp.vh->prm) ||
            is_simple_enum(scope_type) && isPtr(obj)) {
            //auto deref
            obj = load(obj);
        }
        //base method
        if (PointerType::unwrap(target->self->type.get())->print() != PointerType::unwrap(scope_type)->print()) {
            obj = Builder->CreateBitCast(obj, mapType(target->self->type.get()));
        }
        args.push_back(obj);
        paramIdx++;
    }
    std::vector<Param *> params;
    if (target->self) {
        params.push_back(&target->self.value());
    }
    for (auto &p : target->params) {
        params.push_back(&p);
    }
    for (int i = 0, e = mc->args.size(); i != e; ++i) {
        auto a = mc->args[i];
        auto pt = params[paramIdx]->type.get();
        auto at = resolv->getType(a);
        llvm::Value *av;
        if (at->isPointer()) {
            av = gen(a);
            if (isAlloc(a, av)) av = load(av);
        } else if (isStruct(at)) {
            auto de = dynamic_cast<DerefExpr *>(a);//rakkas
            if (de && isStruct(pt)) {
                av = gen(de->expr);
            } else {
                av = gen(a);
                if (is_simple_enum(pt) && isPtr(av)) {
                    av = load(av);
                }
            }
        } else {
            av = cast(a, pt);
        }
        args.push_back(av);
        paramIdx++;
    }

    //virtual logic
    llvm::Value *res;
    auto it = resolv->overrideMap.find(target);
    Method *base = nullptr;
    if (it != resolv->overrideMap.end()) base = it->second;
    if (target->isVirtual || base) {
        if (scp.type->isPointer()) {
            scp.type = ((PointerType *) scp.type)->type;
        }
        int index;
        if (target->isVirtual) {
            index = virtualIndex[target];
        } else {
            index = virtualIndex[base];
            obj = Builder->CreateBitCast(obj, mapType(base->self->type.get()));
        }
        if (target->isVirtual) {
            scp = resolv->resolve(target->self->type.get());
        } else {
            scp = resolv->resolve(base->self->type.get());
        }
        auto decl = (StructDecl *) scp.targetDecl;
        int vt_index = decl->fields.size() + (decl->base ? 1 : 0);
        auto vt = Builder->CreateStructGEP(obj->getType()->getPointerElementType(), obj, vt_index, "vtptr");
        vt = load(vt);
        auto ft = f->getType();
        auto real = llvm::ArrayType::get(ft, 1)->getPointerTo();

        vt = Builder->CreateBitCast(vt, real);
        auto fptr = load(gep(vt, 0, index));
        auto ff = (llvm::FunctionType *) f->getFunctionType();
        res = (llvm::Value *) Builder->CreateCall(ff, fptr, args);
    } else {
        res = (llvm::Value *) Builder->CreateCall(f, args);
    }
    if (ptr) {
        return args[0];
    }
    return res;
}

void Compiler::strLit(llvm::Value *ptr, Literal *n) {
    auto trimmed = n->val.substr(1, n->val.size() - 2);
    auto src = Builder->CreateGlobalStringPtr(trimmed);
    auto slice_ptr = Builder->CreateBitCast(ptr, sliceType->getPointerTo());
    //store s in slice_ptr
    auto data_target = Builder->CreateStructGEP(slice_ptr->getType()->getPointerElementType(), slice_ptr, 0);
    Builder->CreateStore(src, data_target);
    //store len in slice_ptr
    auto len_target = Builder->CreateStructGEP(slice_ptr->getType()->getPointerElementType(), slice_ptr, 1);
    auto len = makeInt(trimmed.size(), 32);
    Builder->CreateStore(len, len_target);
}

std::any Compiler::visitLiteral(Literal *n) {
    loc(n);
    if (n->type == Literal::STR) {
        auto ptr = getAlloc(n);
        strLit(ptr, n);
        return (llvm::Value *) ptr;
    } else if (n->type == Literal::CHAR) {
        auto trimmed = n->val.substr(1, n->val.size() - 2);
        auto chr = trimmed[0];
        return (llvm::Value *) llvm::ConstantInt::get(getInt(32), chr);
    } else if (n->type == Literal::INT) {
        auto bits = 32;
        if (n->suffix) {
            bits = getSize(n->suffix.get());
        }
        return (llvm::Value *) llvm::ConstantInt::get(getInt(bits), atoi(n->val.c_str()));
    } else if (n->type == Literal::BOOL) {
        return (llvm::Value *) (n->val == "true" ? Builder->getTrue() : Builder->getFalse());
    }
    throw std::runtime_error("literal: " + n->print());
}

std::any Compiler::visitAssertStmt(AssertStmt *n) {
    loc(n);
    auto str = n->expr->print();
    auto cond = loadPtr(n->expr.get());
    auto then = llvm::BasicBlock::Create(ctx(), "", func);
    auto next = llvm::BasicBlock::Create(ctx(), "");
    Builder->CreateCondBr(branch(cond), next, then);
    Builder->SetInsertPoint(then);
    //print error and exit
    auto msg = std::string("assertion ") + str + " failed in " + printMethod(curMethod) + "\n";
    std::vector<llvm::Value *> pr_args = {Builder->CreateGlobalStringPtr(msg)};
    Builder->CreateCall(printf_proto, pr_args, "");
    std::vector<llvm::Value *> args = {makeInt(1)};
    Builder->CreateCall(exit_proto, args);
    Builder->CreateUnreachable();
    Builder->SetInsertPoint(next);
    func->getBasicBlockList().push_back(next);
    return nullptr;
}
std::any Compiler::visitVarDecl(VarDecl *node) {
    node->decl->accept(this);
    return {};
}
void Compiler::copy(llvm::Value *trg, llvm::Value *src, Type *type) {
    Builder->CreateMemCpy(trg, llvm::MaybeAlign(0), src, llvm::MaybeAlign(0), getSize2(type) / 8);
}
std::any Compiler::visitVarDeclExpr(VarDeclExpr *n) {
    for (auto &f : n->list) {
        auto rhs = f.rhs.get();
        auto type = f.type ? f.type.get() : resolv->getType(rhs);
        dbg_var(f, type, this);
        //no unnecessary alloc
        if (doesAlloc(rhs)) {
            gen(rhs);
            continue;
        }
        auto ptr = NamedValues[f.name];
        if (isStruct(type)) {
            auto val = gen(rhs);
            if (is_simple_enum(type)) {
                if (val->getType()->isPointerTy()) {
                    val = load(val);
                }
                Builder->CreateStore(val, ptr);
            } else if (val->getType()->isPointerTy()) {
                copy(ptr, val, type);
            } else {
                Builder->CreateStore(val, ptr);
            }
        } else {
            auto val = cast(rhs, type);
            Builder->CreateStore(val, ptr);
        }
    }
    return nullptr;
}

std::any Compiler::visitRefExpr(RefExpr *n) {
    auto inner = gen(n->expr);
    //todo rvalue
    return inner;
}

std::any Compiler::visitDerefExpr(DerefExpr *n) {
    auto val = gen(n->expr);
    return load(val);
}

EnumDecl *findEnum(Type *type, Resolver *resolv) {
    auto rt = resolv->resolve(type);
    return dynamic_cast<EnumDecl *>(rt.targetDecl);
}

std::any Compiler::visitObjExpr(ObjExpr *n) {
    loc(n);
    auto tt = resolv->resolve(n);
    llvm::Value *ptr;
    if (n->isPointer) {
        auto ty = mapType(tt.type);
        ptr = callMalloc(makeInt(getSize(tt.targetDecl) / 8, 64), this);
        ptr = Builder->CreateBitCast(ptr, ty);
    } else {
        ptr = getAlloc(n);
    }
    object(n, ptr, tt, nullptr);
    return ptr;
}

int Compiler::getOffset(EnumVariant *variant, int index) {
    int offset = 0;
    for (int i = 0; i < index; i++) {
        offset += getSize(variant->fields[i].type) / 8;
    }
    return offset;
}

void Compiler::object(ObjExpr *n, llvm::Value *ptr, const RType &tt, std::string *derived) {
    auto ty = mapType(tt.type);
    if (tt.targetDecl->isEnum()) {
        //enum
        auto decl = dynamic_cast<EnumDecl *>(tt.targetDecl);
        auto variant_index = Resolver::findVariant(decl, n->type->name);
        setOrdinal(variant_index, ptr);
        auto dataPtr = Builder->CreateStructGEP(ptr->getType()->getPointerElementType(), ptr, 1);
        auto &variant = decl->variants[variant_index];
        for (int i = 0; i < n->entries.size(); i++) {
            auto &e = n->entries[i];
            int index;
            if (e.key) {
                index = fieldIndex(variant.fields, e.key.value(), new Type(decl->type, variant.name));
            } else {
                index = i;
            }
            auto &field = variant.fields[index];
            auto entPtr = gep(dataPtr, 0, getOffset(&variant, index));
            setField(e.value, field.type, true, entPtr);
        }
    } else {
        //class
        auto decl = dynamic_cast<StructDecl *>(tt.targetDecl);
        if (!getVirtual(decl, unit.get()).empty()) {
            //set vtable
            auto vt = vtables[decl->type->print()];
            //use modified vtable of derived
            if (derived) {
                auto it = vtables.find(*derived + "." + decl->type->print());
                if (it != vtables.end()) {
                    vt = it->second;
                }
            }
            int vt_index = decl->fields.size() + (decl->base ? 1 : 0);
            auto vt_target = Builder->CreateStructGEP(ptr->getType()->getPointerElementType(), ptr, vt_index, "vtptr");
            auto casted = Builder->CreateBitCast(vt, getInt(8)->getPointerTo()->getPointerTo());
            Builder->CreateStore(casted, vt_target);
        }
        int field_idx = 0;
        for (int i = 0; i < n->entries.size(); i++) {
            auto &e = n->entries[i];
            if (e.isBase) {
                auto eptr = Builder->CreateStructGEP(ptr->getType()->getPointerElementType(), ptr, 0, "base");
                auto val = dynamic_cast<ObjExpr *>(e.value);
                auto key = decl->type->print();
                object(val, eptr, resolv->resolve(val), derived ? derived : &key);
                continue;
            }
            FieldDecl *field;
            int real_idx;
            if (e.key) {
                auto index = fieldIndex(decl->fields, e.key.value(), decl->type);
                field = &decl->fields[index];
                real_idx = index;
            } else {
                real_idx = field_idx;
                field = &decl->fields[field_idx++];
            }
            if (decl->base) real_idx++;
            auto eptr = Builder->CreateStructGEP(ptr->getType()->getPointerElementType(), ptr, real_idx, "field_" + field->name);
            setField(e.value, field->type, true, eptr);
        }
    }
}

std::any Compiler::visitType(Type *n) {
    if (!n->scope) {
        throw std::runtime_error("type has no scope");
    }
    //enum variant without struct
    if (Config::optimize_enum) {
        auto bd = resolv->resolve(n->scope.get()).targetDecl;
        auto decl = dynamic_cast<EnumDecl *>(bd);
        if (Resolver::is_simple_enum(decl)) {
            int index = Resolver::findVariant(decl, n->name);
            return (llvm::Value *) makeInt(index, ENUM_INDEX_SIZE);
        }
    }
    auto ptr = getAlloc(n);
    simpleVariant(n, ptr);
    return ptr;
}

std::any Compiler::visitFieldAccess(FieldAccess *n) {
    auto rt = resolv->resolve(n->scope);
    if (rt.type->isSlice()) {
        auto scopeVar = gen(n->scope);
        return Builder->CreateStructGEP(scopeVar->getType()->getPointerElementType(), scopeVar, SLICE_LEN_INDEX);
        //todo load since cant mutate
    }
    if (rt.type->isString()) {
        //rt = resolv->resolve(rt.type);
    }
    auto decl = rt.targetDecl;
    int index;
    if (decl->isEnum()) {
        index = 0;
    } else {
        auto td = dynamic_cast<StructDecl *>(decl);
        index = fieldIndex(td->fields, n->name, td->type);
        if (td->base) index++;
    }
    auto scope = gen(n->scope);
    if (rt.type->isPointer() && isAlloc(n->scope, this)) {
        //auto deref
        scope = load(scope);
    }
    return (llvm::Value *) Builder->CreateStructGEP(scope->getType()->getPointerElementType(), scope, index);
}

std::any Compiler::visitIfStmt(IfStmt *b) {
    auto cond = branch(loadPtr(b->expr));
    auto then = llvm::BasicBlock::Create(ctx(), "body", func);
    llvm::BasicBlock *elsebb = nullptr;
    auto next = llvm::BasicBlock::Create(ctx(), "next");
    if (b->elseStmt) {
        elsebb = llvm::BasicBlock::Create(ctx(), "else");
        Builder->CreateCondBr(cond, then, elsebb);
    } else {
        Builder->CreateCondBr(cond, then, next);
    }
    Builder->SetInsertPoint(then);
    b->thenStmt->accept(this);
    if (!isReturnLast(b->thenStmt.get())) {
        Builder->CreateBr(next);
    }
    if (b->elseStmt) {
        Builder->SetInsertPoint(elsebb);
        func->getBasicBlockList().push_back(elsebb);
        b->elseStmt->accept(this);
        if (!isReturnLast(b->elseStmt.get())) {
            Builder->CreateBr(next);
        }
    }
    Builder->SetInsertPoint(next);
    func->getBasicBlockList().push_back(next);
    return nullptr;
}

std::any Compiler::visitIfLetStmt(IfLetStmt *b) {
    auto decl = findEnum(b->type.get(), resolv.get());
    auto rhs = gen(b->rhs);
    llvm::Value *tag;
    if (Resolver::is_simple_enum(decl)) {
        tag = rhs;
        if (tag->getType()->isPointerTy()) tag = load(tag);
    } else {
        auto tagptr = gep2(rhs, 0);
        tag = Builder->CreateLoad(getInt(ENUM_INDEX_SIZE), tagptr);
    }

    auto index = Resolver::findVariant(decl, b->type->name);
    auto cmp = Builder->CreateCmp(llvm::CmpInst::ICMP_EQ, tag, makeInt(index, ENUM_INDEX_SIZE));

    auto then = llvm::BasicBlock::Create(ctx(), "", func);
    llvm::BasicBlock *elsebb;
    auto next = llvm::BasicBlock::Create(ctx(), "");
    if (b->elseStmt) {
        elsebb = llvm::BasicBlock::Create(ctx(), "");
        Builder->CreateCondBr(branch(cmp), then, elsebb);
    } else {
        Builder->CreateCondBr(branch(cmp), then, next);
    }
    Builder->SetInsertPoint(then);

    auto &variant = decl->variants[index];
    if (!variant.fields.empty()) {
        //declare vars
        auto &params = variant.fields;
        auto dataPtr = gep2(rhs, 1);
        int offset = 0;
        for (int i = 0; i < params.size(); i++) {
            //regular var decl
            auto &prm = params[i];
            auto argName = b->args[i];
            auto ptr = gep(dataPtr, 0, offset);
            //bitcast to real type
            auto targetTy = mapType(prm.type)->getPointerTo();
            auto ptrReal = Builder->CreateBitCast(ptr, targetTy);
            NamedValues[argName] = ptrReal;
            offset += getSize(prm.type) / 8;
        }
    }
    b->thenStmt->accept(this);
    //clear params
    for (auto &p : b->args) {
        NamedValues.erase(p);
    }
    if (!isReturnLast(b->thenStmt.get())) {
        Builder->CreateBr(next);
    }
    if (b->elseStmt) {
        Builder->SetInsertPoint(elsebb);
        func->getBasicBlockList().push_back(elsebb);
        b->elseStmt->accept(this);
        if (!isReturnLast(b->elseStmt.get())) {
            Builder->CreateBr(next);
        }
    }
    Builder->SetInsertPoint(next);
    func->getBasicBlockList().push_back(next);
    return nullptr;
}

llvm::Value *Compiler::getTag(Expression *expr) {
    auto tag = gen(expr);
    auto lt = resolv->getType(expr);
    if (Config::optimize_enum && is_simple_enum(lt)) {
        if (isPtr(tag)) {
            return load(tag);
        }
        return tag;
    } else {
        return Builder->CreateLoad(getInt(32), gep2(tag, ENUM_TAG_INDEX));
    }
}

std::any Compiler::visitIsExpr(IsExpr *ie) {
    llvm::Value *tag1 = getTag(ie->expr);
    llvm::Value *tag2;
    auto rt = dynamic_cast<Type *>(ie->rhs);
    if (!rt) {
        tag2 = getTag(ie->rhs);
    } else {
        auto decl = (EnumDecl *) resolv->resolve(rt).targetDecl;
        auto index = Resolver::findVariant(decl, rt->name);
        tag2 = makeInt(index);
    }
    return (llvm::Value *) Builder->CreateCmp(llvm::CmpInst::ICMP_EQ, tag1, tag2);
}

std::any Compiler::visitAsExpr(AsExpr *e) {
    auto ty = resolv->getType(e->type);
    if (ty->isPrim()) {
        auto val = loadPtr(e->expr);
        return extend(val, ty, this);
    }
    //derived to base
    auto val = gen(e->expr);
    if (resolv->getType(e->expr)->isPointer()) {
        val = load(val);
    }
    return Builder->CreateBitCast(val, mapType(ty));
}

std::any Compiler::slice(ArrayAccess *node, llvm::Value *sp, Type *arrty) {
    auto val_start = cast(node->index, new Type("i32"));
    //set array ptr
    llvm::Value *src;
    if (doesAlloc(node->array)) {
        child(node->array, sp);
        src = sp;
    } else {
        src = gen(node->array);
    }
    Type *elemty;
    if (arrty->isSlice()) {
        //deref inner pointer
        src = Builder->CreateBitCast(src, src->getType()->getPointerTo());
        src = load(src);
        elemty = dynamic_cast<SliceType *>(arrty)->type;
    } else if (arrty->isArray()) {
        elemty = dynamic_cast<ArrayType *>(arrty)->type;
    } else {
        elemty = dynamic_cast<PointerType *>(arrty)->type;
        src = load(src);
    }
    src = Builder->CreateBitCast(src, mapType(elemty)->getPointerTo());
    //shift by start
    std::vector<llvm::Value *> shift_idx = {val_start};
    src = Builder->CreateGEP(src->getType()->getPointerElementType(), src, shift_idx, "shifted");
    //i8*
    src = Builder->CreateBitCast(src, getInt(8)->getPointerTo());
    auto ptr_target = Builder->CreateStructGEP(sp->getType()->getPointerElementType(), sp, 0);
    Builder->CreateStore(src, ptr_target);
    //set len
    auto len_target = Builder->CreateStructGEP(sp->getType()->getPointerElementType(), sp, SLICE_LEN_INDEX);
    auto val_end = cast(node->index2.get(), new Type("i32"));
    auto len = Builder->CreateSub(val_end, val_start);
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
    auto src = gen(node->array);
    if (type->isPointer()) {
        auto pt = dynamic_cast<PointerType *>(type);
        if (isAlloc(node->array, src) && (pt->type->isArray() || pt->type->isSlice())) {
            src = load(src);
            type = pt->type;
        }
    }
    if (type->isArray()) {
        //regular array access
        return gep(src, 0, node->index);
    } else if (type->isSlice()) {
        //slice access
        auto elem = dynamic_cast<SliceType *>(type)->type;
        auto elemty = mapType(elem);
        //read array ptr
        auto arr = Builder->CreateStructGEP(src->getType()->getPointerElementType(), src, 0, "arr1");
        arr = Builder->CreateBitCast(arr, arr->getType()->getPointerTo());
        arr = Builder->CreateLoad(arr->getType()->getPointerElementType(), arr);
        arr = Builder->CreateBitCast(arr, elemty->getPointerTo());
        return gep(arr, node->index);
    } else {
        //pointer access
        if (isAlloc(node->array, src))
            src = load(src);
        return gep(src, node->index);
    }
}

std::any Compiler::visitWhileStmt(WhileStmt *node) {
    auto then = llvm::BasicBlock::Create(ctx(), "body");
    auto condbb = llvm::BasicBlock::Create(ctx(), "cont_test", func);
    auto next = llvm::BasicBlock::Create(ctx(), "next");
    Builder->CreateBr(condbb);
    Builder->SetInsertPoint(condbb);
    auto c = loadPtr(node->expr.get());
    Builder->CreateCondBr(branch(c), then, next);
    Builder->SetInsertPoint(then);
    func->getBasicBlockList().push_back(then);
    loops.push_back(condbb);
    loopNext.push_back(next);
    node->body->accept(this);
    loops.pop_back();
    loopNext.pop_back();
    Builder->CreateBr(condbb);
    Builder->SetInsertPoint(next);
    func->getBasicBlockList().push_back(next);
    return nullptr;
}

std::any Compiler::visitForStmt(ForStmt *node) {
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
    Builder->SetInsertPoint(then);
    func->getBasicBlockList().push_back(then);
    loops.push_back(updatebb);
    loopNext.push_back(next);
    node->body->accept(this);
    Builder->CreateBr(updatebb);
    Builder->SetInsertPoint(updatebb);
    for (auto &u : node->updaters) {
        u->accept(this);
    }
    loops.pop_back();
    loopNext.pop_back();
    Builder->CreateBr(condbb);
    Builder->SetInsertPoint(next);
    func->getBasicBlockList().push_back(next);
    return {};
}

std::any Compiler::visitContinueStmt(ContinueStmt *node) {
    Builder->CreateBr(loops.back());
    return nullptr;
}

std::any Compiler::visitBreakStmt(BreakStmt *node) {
    Builder->CreateBr(loopNext.back());
    return nullptr;
}

std::any Compiler::visitArrayExpr(ArrayExpr *node) {
    auto ptr = getAlloc(node);
    array(node, ptr);
    return ptr;
}

void Compiler::child(Expression *e, llvm::Value *ptr) {
    ptr = Builder->CreateBitCast(ptr, mapType(resolv->getType(e))->getPointerTo());
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
    if (obj && !obj->isPointer) {
        object(obj, ptr, resolv->resolve(obj), nullptr);
        return;
    }
    auto t = dynamic_cast<Type *>(e);
    if (t) {
        simpleVariant(t, ptr);
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
    if (!node->isSized()) {
        int i = 0;
        for (auto e : node->list) {
            auto elem_target = gep(ptr, 0, i++);
            if (doesAlloc(e)) {
                child(e, elem_target);
            } else if (isStruct(type)) {
                auto val = gen(e);
                auto rt = resolv->getType(e);
                copy(elem_target, val, rt);
            } else {
                Builder->CreateStore(cast(e, type), elem_target);
            }
        }
        return ptr;
    }
    auto bb = Builder->GetInsertBlock();
    auto cur = gep(ptr, 0, 0);
    auto end = gep(ptr, 0, node->size.value());
    //create cons and memcpy
    auto condbb = llvm::BasicBlock::Create(ctx(), "cond");
    auto setbb = llvm::BasicBlock::Create(ctx(), "set");
    auto nextbb = llvm::BasicBlock::Create(ctx(), "next");
    Builder->CreateBr(condbb);
    func->getBasicBlockList().push_back(condbb);
    Builder->SetInsertPoint(condbb);
    auto phi = Builder->CreatePHI(mapType(type)->getPointerTo(), 2);
    phi->addIncoming(cur, bb);
    auto ne = Builder->CreateCmp(llvm::CmpInst::ICMP_NE, phi, end);
    Builder->CreateCondBr(branch(ne), setbb, nextbb);
    Builder->SetInsertPoint(setbb);
    func->getBasicBlockList().push_back(setbb);
    if (doesAlloc(node->list[0])) {
        child(node->list[0], phi);
    } else {
        auto val = cast(node->list[0], type);
        Builder->CreateStore(val, phi);
    }
    auto step = gep(phi, 1);
    phi->addIncoming(step, setbb);
    Builder->CreateBr(condbb);
    func->getBasicBlockList().push_back(nextbb);
    Builder->SetInsertPoint(nextbb);
    return ptr;
}