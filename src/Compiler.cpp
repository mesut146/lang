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

void dumpv(llvm::Value *val) {
    val->dump();
    val->getType()->dump();
}

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


void Compiler::emit_object(std::string &Filename) {
    if (Config::debug) DBuilder->finalize();

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

void Compiler::initModule(const std::string &path) {
    auto name = getName(path);
    if (ctxp) {
        throw std::runtime_error("ctx already set");
    }
    if (mod) {
        throw std::runtime_error("mod already set");
    }
    if (Builder) {
        throw std::runtime_error("Builder already set");
    }
    ctxp = std::make_unique<llvm::LLVMContext>();
    mod = std::make_unique<llvm::Module>(name, ctx());
    mod->setTargetTriple(TargetTriple);
    mod->setDataLayout(TargetMachine->createDataLayout());
    Builder = std::make_unique<llvm::IRBuilder<>>(ctx());
    init_dbg(path);
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
        auto res = c->resolv->context->getResolver(is);
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
    //init rhs of globals
    auto staticf = make_init_proto(c->unit->path, c);
    std::string mangled = staticf->getName().str();
    DirCompiler::global_protos.push_back(c->unit->path);
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

        c->loc(c->unit->lastLine, 0);
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

std::optional<std::string> Compiler::compile(const std::string &path, DirCompiler &dc) {
    init_llvm();
    fs::path p(path);
    auto outFile = dc.out_dir + "/" + get_out_file(path);
    if (!dc.cache.need_compile(path, outFile)) {
        dc.compiled.push_back(outFile);
        return outFile;
    }
    auto ext = p.extension().string();
    if (ext != ".x") {
        error("invalid extension " + path);
    }
    if (Config::verbose) {
        std::cout << "compiling " << path << std::endl;
    }
    resolv = context.getResolver(path);
    context.init_prelude();
    curOwner.init(this);
    unit = resolv->unit;
    if (has_main(unit.get())) {
        dc.main_file = path;
        if (dc.skip_main) {//compile last
            return outFile;
        }
    }
    resolv->resolveAll();

    initModule(path);

    createProtos();
    init_globals(this);

    for (auto &m : getMethods(unit.get())) {
        genCode(m);
    }
    for (int i = 0; i < resolv->generatedMethods.size(); i++) {
        auto m = resolv->generatedMethods.at(i);
        genCode(m);
    }

    //emit llvm
    auto name = getName(path);
    auto noext = trimExtenstion(name);
    auto llvm_file = dc.out_dir + "/" + noext + ".ll";
    std::error_code ec;
    llvm::raw_fd_ostream fd(llvm_file, ec);
    mod->print(fd, nullptr);
    if (Config::verbose) {
        print("writing " + llvm_file);
    }

    llvm::verifyModule(*mod, &llvm::outs());

    //todo fullpath

    emit_object(outFile);
    cleanup();
    dc.compiled.push_back(outFile);
    dc.cache.update(p);
    dc.cache.write_cache();
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
    globals.clear();
    //delete staticf;
}

void Compiler::setField(Expression *expr, const Type &type, llvm::Value *ptr, Expression *lhs) {
    // auto de = dynamic_cast<DerefExpr *>(expr);
    // if (de /*&& isStruct(type)*/) {
    //     if (isStruct(type)) {
    //         auto val = get_obj_ptr(de->expr.get());
    //         curOwner.beginAssign(lhs, ptr);
    //         copy(ptr, val, type);
    //     } else {
    //         //prim, ptr
    //         curOwner.beginAssign(lhs, ptr);
    //         auto val = cast(expr, type);
    //         Builder->CreateStore(val, ptr);
    //     }

    //     return;
    // }
    /*auto mc = dynamic_cast<MethodCall *>(expr);
    if (mc && is_ptr_deref(mc)) {
        auto val = get_obj_ptr(de->expr.get());
        curOwner.beginAssign(lhs, ptr);
        copy(ptr, val, type);
        return;
    }*/
    if (isRvo(expr)) {
        auto val = gen(expr);
        //curOwner.drop(expr, ptr);
        curOwner.beginAssign(lhs, ptr);
        copy(ptr, val, type);
        return;
    }
    //
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
    return f;
}

llvm::Type *get_variant_type(const Type &type, Compiler *c) {
    auto id = type.print();
    if (c->classMap.contains(id)) {
        return c->classMap.at(id);
    }
    throw std::runtime_error("get_variant_type " + type.print());
}

void Compiler::createProtos() {
    if (!sliceType) {
        sliceType = make_slice_type();
    }
    if (!stringType) {
        stringType = make_string_type();
    }
    make_decl_protos();
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
    stdout_ptr = new llvm::GlobalVariable(*mod, getPtr(), false, llvm::GlobalValue::ExternalLinkage, nullptr, "stdout");
    stdout_ptr->addAttribute("global");
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
    /*if (m->name == "drop" && m->parent.type && m->parent.type->print() == "Unit") {
        print(m->print());
    }*/
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
        for (auto &init_proto_path : DirCompiler::global_protos) {
            loc(m->line, 0);
            auto init_proto = mod->getFunction(mangle_static(init_proto_path));
            if (!init_proto) {
                init_proto = make_init_proto(init_proto_path, this);
            }
            std::vector<llvm::Value *> args2;
            Builder->CreateCall(init_proto, args2);
        }
    }
    resolv->newScope();
    m->body->accept(this);
    auto exit = Exit::get_exit_type(m->body.get());
    if (!exit.is_return()) {
        //return already drops all
        curOwner.endScope(*curOwner.main_scope);
    }
    //exit code 0
    if (is_main(m) && m->type.print() == "void") {
        if (!exit.is_exit()) {
            Builder->CreateRet(makeInt(0, 32));
        }
    } else if (!exit.is_exit() && m->type.print() == "void") {
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
    if (expr->print() == "*ptr::get(arr, i) == 0") {
        int aa = 55;
    }
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
    if (node->print() == "inElse == false") {
        int aa = 555;
    }
    //auto t3 = t1 == "bool" ? Type("i1") : binCast(t1, t2).type;
    auto t3 = t1 == "bool" ? Type("bool") : binCast(t1, t2).type;
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
            auto str = c->Builder->CreateGlobalStringPtr(l->val);
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

void print_simple(const std::string &str, Compiler *c) {
    std::vector<llvm::Value *> args;
    auto str_ptr = c->Builder->CreateGlobalStringPtr(str);
    args.push_back(str_ptr);
    c->Builder->CreateCall(c->printf_proto, args);
    //flush
    std::vector<llvm::Value *> args2;
    args2.push_back(c->load(c->stdout_ptr));
    c->Builder->CreateCall(c->fflush_proto, args2);
}
std::string panic_message(Compiler *c, int line, std::optional<std::string> msg) {
    std::string message = "panic ";
    message += c->curMethod->path + ":" + std::to_string(line);
    message += " " + printMethod(c->curMethod);
    if (msg.has_value()) {
        message += "\n";
        message += msg.value();
    }
    message.append("\n");
    return message;
}
void call_exit(int code, Compiler *c) {
    std::vector<llvm::Value *> exit_args = {c->makeInt(code)};
    c->Builder->CreateCall(c->exit_proto, exit_args);
    c->Builder->CreateUnreachable();
}
void panic_simple(MethodCall *mc, Compiler *c) {
    auto lit = dynamic_cast<Literal *>(mc->args.at(0));
    auto msg = panic_message(c, mc->line, lit->val);
    print_simple(msg, c);
    //exit
    call_exit(-1, c);
}

void callPrintf(MethodCall *mc, Compiler *c) {
    std::vector<llvm::Value *> args;
    for (auto a : mc->args) {
        if (isStrLit(a)) {
            auto l = dynamic_cast<Literal *>(a);
            auto str = c->Builder->CreateGlobalStringPtr(l->val);
            args.push_back(str);
            continue;
        }
        auto arg_type = c->resolv->getType(a);
        if (arg_type.print() == "i8*" || arg_type.print() == "u8*") {
            auto src = c->get_obj_ptr(a);
            args.push_back(src);
            continue;
        }
        if (arg_type.isPrim()) {
            auto src = c->loadPtr(a);
            args.push_back(src);
        } else {
            c->resolv->err(mc, "internal error");
        }
    }
    c->Builder->CreateCall(c->printf_proto, args);
    //flush
    std::vector<llvm::Value *> args2;
    args2.push_back(c->load(c->stdout_ptr));
    c->Builder->CreateCall(c->fflush_proto, args2);
}

std::any Compiler::visitMethodCall(MethodCall *mc) {
    loc(mc);
    if (is_std_parent_name(mc)) {
        auto ptr = getAlloc(mc);
        if (curMethod->parent.is_impl()) {
            auto parent_type = curMethod->parent.type.value().print();
            strLit(ptr, parent_type);
        } else {
            strLit(ptr, "");
        }
        return ptr;
    }
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
        return add_comment(gep(src, idx, mapType(elem_type)), "ptr::get");
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
        auto arg_ptr = get_obj_ptr(mc->args[0]);
        auto rt = resolv->getType(mc);
        if (!isStruct(rt)) {
            return load(arg_ptr, mapType(rt));
        }
        return arg_ptr;
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
    if (is_printf(mc)) {
        callPrintf(mc, this);
        return (llvm::Value *) Builder->getVoidTy();
    }
    if (mc->name == "malloc" && !mc->scope) {
        auto size = cast(mc->args[0], Type("i64"));
        if (!mc->typeArgs.empty()) {
            int typeSize = getSize2(mc->typeArgs[0]) / 8;
            size = Builder->CreateNSWMul(size, makeInt(typeSize, 64));
        }
        return callMalloc(size, this);
    }
    if (is_format(mc)) {
        auto &info = resolv->format_map.at(mc->id);
        visitBlock(&info.block);
        auto ptr = getAlloc(mc);
        call(&info.unwrap_mc, ptr);
        return ptr;
    }
    if (is_print(mc)) {
        if (mc->args.size() == 1) {
            //simple print, use printf
            auto lit = dynamic_cast<Literal *>(mc->args[0]);
            print_simple(lit->val, this);
            return (llvm::Value *) Builder->getVoidTy();
        }
        auto &info = resolv->format_map.at(mc->id);
        visitBlock(&info.block);
        //call(&info.print_mc, nullptr);
        return (llvm::Value *) Builder->getVoidTy();
    }
    if (is_panic(mc)) {
        if (mc->args.size() == 1) {
            //simple panic, use printf
            panic_simple(mc, this);
            return (llvm::Value *) Builder->getVoidTy();
        }
        auto &info = resolv->format_map.at(mc->id);
        visitBlock(&info.block);
        //call(&info.print_mc, nullptr);
        call_exit(1, this);
        return (llvm::Value *) Builder->getVoidTy();
    }
    if (is_drop_call(mc)) {
        auto argt = resolv->resolve(mc->args.at(0));
        if (argt.type.isPointer()) {
            //dont drop
            return (llvm::Value *) Builder->getVoidTy();
        }
        DropHelper helper(resolv.get());
        if (!helper.isDropType(argt)) {
            return (llvm::Value *) Builder->getVoidTy();
        }
        /*auto arg = mc->args.at(0);
        auto ptr = gen(arg);
        curOwner.call_drop_force(argt.type, ptr);
        //todo bc of partial drop we have to comment below
        if (dynamic_cast<SimpleName *>(arg)) {
            //todo f.access
            curOwner.doMoveCall(arg);
        } else {
            curOwner.doMoveCall(arg);
        }*/
    }
    auto rt = resolv->resolve(mc);
    auto target = rt.targetMethod;
    if (target == nullptr) {
        resolv->err(mc, "internal error, method not resolved");
    }
    if (isRvo(target)) {
        auto ptr = getAlloc(mc);
        curOwner.addPtr(mc, ptr);
        return call(mc, ptr);
    } else {
        return call(mc, nullptr);
    }
}

llvm::Value *Compiler::call(MethodCall *mc, llvm::Value *sret) {
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
    if (sret) {
        args.push_back(sret);
    }
    int paramIdx = 0;
    int argIdx = 0;
    llvm::Value *obj = nullptr;
    if (target->self) {
        auto rval = RvalueHelper::need_alloc(mc, target, resolv.get());
        //add this object
        auto val = get_obj_ptr(rval.scope);
        if (rval.rvalue) {
            obj = getAlloc(rval.scope);
            Builder->CreateStore(val, obj);
        } else {
            obj = val;
        }
        args.push_back(obj);
        if (mc->is_static) {
            argIdx++;
        }
        //paramIdx++;
        if (target->self->is_deref) {
            curOwner.doMoveCall(mc->scope.get());
        }
    }
    std::vector<Param *> params;
    /*if (target->self) {
        params.push_back(&target->self.value());
    }*/
    for (auto &p : target->params) {
        params.push_back(&p);
    }
    //print(mc->print());
    for (; argIdx < mc->args.size(); argIdx++) {
        auto a = mc->args[argIdx];
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
    auto res = (llvm::Value *) Builder->CreateCall(f, args);
    if (sret) {
        return args[0];
    }
    return res;
}

void Compiler::strLit(llvm::Value *ptr, const std::string &str) {
    auto src = Builder->CreateGlobalStringPtr(str);
    auto slice_ptr = gep2(ptr, 0, stringType);
    auto data_target = gep2(slice_ptr, SLICE_PTR_INDEX, sliceType);
    auto len_target = gep2(slice_ptr, SLICE_LEN_INDEX, sliceType);
    //set ptr
    Builder->CreateStore(src, data_target);
    //set len
    auto len = makeInt(str.size(), SLICE_LEN_BITS);
    Builder->CreateStore(len, len_target);
}

std::any Compiler::visitLiteral(Literal *node) {
    loc(node);
    if (node->type == Literal::STR) {
        auto ptr = getAlloc(node);
        strLit(ptr, node->val);
        return (llvm::Value *) ptr;
    } else if (node->type == Literal::CHAR) {
        auto chr = node->val[0];
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
        auto ptr = getAlloc(&f);
        NamedValues[f.name] = ptr;
        loc(&f);
        curOwner.check(rhs);
        if (type.isPointer()) {
            auto val = get_obj_ptr(rhs);
            Builder->CreateStore(val, ptr);
        } else if (!isStruct(type)) {
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
    if (RvalueHelper::is_rvalue(node->expr.get())) {
        auto allc = getAlloc(node);
        auto val = loadPtr(node->expr.get());
        Builder->CreateStore(val, allc);
        return allc;
    }
    auto inner = gen(node->expr);
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
            auto base_index = Layout::get_base_index(tt.targetDecl);
            auto base_ptr = gep2(ptr, base_index, ty);
            auto val = dynamic_cast<ObjExpr *>(arg.value);
            auto base_rt = resolv->resolve(arg.value);
            if (val) {
                auto key = tt.targetDecl->type.print();
                object(val, base_ptr, base_rt, derived ? derived : &key);
            } else {
                auto val_ptr = gen(arg.value);
                copy(base_ptr, val_ptr, base_rt.type);
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
        if (decl->base) real_idx++;
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

std::any Compiler::visitFieldAccess(FieldAccess *node) {
    auto rt = resolv->resolve(node->scope);
    auto scope = get_obj_ptr(node->scope);
    auto decl = rt.targetDecl;
    auto [sd, index] = resolv->findField(node->name, decl);
    if (index == -1) {
        resolv->err(node, "internal error");
    }
    auto sd_ty = mapType(sd->type);
    if (decl->isEnum()) {
        //base field, skip tag
        scope = gep2(scope, Layout::get_base_index(decl), decl->type);
        //index++;
    } else {
    }
    if (sd->base) index++;
    return add_comment(gep2(scope, index, sd_ty), node->print());
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
    auto lhs = resolv->resolve(node->expr);
    auto rhs = resolv->resolve(&node->type);
    //ptr to int
    if (lhs.type.isPointer() && rhs.type.print() == "u64") {
        auto val = get_obj_ptr(node->expr);
        return Builder->CreatePtrToInt(val, mapType(rhs.type));
    }
    //prim to prim
    if (rhs.type.isPrim()) {
        return cast(node->expr, rhs.type);
        /*auto val = loadPtr(node->expr);
        return extend(val, lhs.type, rhs.type, this);*/
    }
    auto val = get_obj_ptr(node->expr);
    //struct to base
    if (lhs.targetDecl && lhs.targetDecl->isEnum() && rhs.targetDecl) {
        auto index = Layout::get_base_index(lhs.targetDecl);
        val = gep2(val, index, lhs.type.unwrap());
        return val;
    }
    return val;
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
    if (dynamic_cast<FieldAccess *>(node->array)) {
        //src = add_comment(load(src), "deref_extra");
    }
    type = type.unwrap();
    if (type.isArray()) {
        //regular array access
        auto i1 = makeInt(0, 64);
        auto i2 = cast(node->index, Type("i64"));
        auto res = gep(src, i1, i2, mapType(type));
        add_comment(res, "arr_shift");
        return res;
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
        strLit(ptr, lit->val);
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
    auto then = llvm::BasicBlock::Create(ctx(), "assert_body_" + std::to_string(node->line));
    auto next = llvm::BasicBlock::Create(ctx(), "assert_next_" + std::to_string(node->line));
    Builder->CreateCondBr(branch(node->expr.get()), next, then);
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
    auto cond = branch(node->expr.get());
    auto then = llvm::BasicBlock::Create(ctx(), "if_then_" + std::to_string(node->line));
    auto elsebb = llvm::BasicBlock::Create(ctx(), "if_else_" + std::to_string(node->line));
    auto next = llvm::BasicBlock::Create(ctx(), "if_next_" + std::to_string(node->line));
    Builder->CreateCondBr(cond, then, elsebb);
    set_and_insert(then);
    resolv->newScope();
    int cur_scope = curOwner.last_scope->id;
    auto then_returns = Exit::get_exit_type(node->thenStmt.get());
    auto then_scope = curOwner.newScope(ScopeId::IF, then_returns, cur_scope, node->thenStmt->line);
    node->thenStmt->accept(this);
    if (!then_scope->exit.is_exit()) {
        auto &last_ins = Builder->GetInsertBlock()->back();
        if (!last_ins.isTerminator()) {
            curOwner.endScope(*then_scope);
        }
    }
    if (!then_returns.is_jump()) {
        Builder->CreateBr(next);
    }
    set_and_insert(elsebb);
    curOwner.setScope(cur_scope);//else inserted into main scope, not then scope
    auto else_scope = curOwner.newScope(ScopeId::ELSE, Exit(ExitType::NONE), cur_scope, node->thenStmt->line);
    else_scope->sibling = then_scope->id;
    then_scope->sibling = else_scope->id;
    if (node->elseStmt) {
        resolv->newScope();
        else_scope->exit = Exit::get_exit_type(node->elseStmt.get());
        else_scope->line = node->elseStmt->line;
        node->elseStmt->accept(this);
        if (!else_scope->exit.is_return()) {
            curOwner.endScope(*else_scope);
            curOwner.end_branch(*else_scope);
        }
        if (!else_scope->exit.is_jump()) {
            Builder->CreateBr(next);
        } else {
            //return cleans all
        }
    } else {
        curOwner.endScope(*else_scope);
        curOwner.end_branch(*else_scope);
        Builder->CreateBr(next);
    }
    if (!(then_returns.is_jump() && else_scope->exit.is_jump())) {
        set_and_insert(next);
        auto then_clean = llvm::BasicBlock::Create(ctx(), "then_clean_" + std::to_string(node->line));
        auto next2 = llvm::BasicBlock::Create(ctx(), "next2_" + std::to_string(node->line));
        Builder->CreateCondBr(cond, then_clean, next2);
        set_and_insert(then_clean);
        curOwner.end_branch(*then_scope);
        Builder->CreateBr(next2);
        set_and_insert(next2);
    }
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
    auto then_scope = curOwner.newScope(ScopeId::IF, Exit::get_exit_type(node->thenStmt.get()), cur_scope, node->thenStmt->line);
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
            auto &arg = node->args[i];
            int real_idx = i + (decl->base ? 1 : 0);
            auto field_ptr = gep2(dataPtr, real_idx, var_ty);
            auto alloc_ptr = getAlloc(&arg);
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
    if (!then_scope->exit.is_exit()) {
        curOwner.endScope(*then_scope);
        Builder->CreateBr(next);
    }
    set_and_insert(elsebb);
    curOwner.setScope(cur_scope);//else inserted into main scope, not then scope
    auto else_scope = curOwner.newScope(ScopeId::ELSE, Exit(ExitType::NONE), cur_scope, node->thenStmt->line);
    else_scope->sibling = then_scope->id;
    then_scope->sibling = else_scope->id;
    if (node->elseStmt) {
        resolv->newScope();
        else_scope->exit = Exit::get_exit_type(node->elseStmt.get());
        else_scope->line = node->elseStmt->line;
        node->elseStmt->accept(this);
        if (!else_scope->exit.is_return()) {
            curOwner.endScope(*else_scope);
            curOwner.end_branch(*else_scope);
        }
        if (!else_scope->exit.is_exit()) {
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
    auto then_scope = curOwner.newScope(ScopeId::WHILE, Exit::get_exit_type(node->body.get()), cur_scope, node->body->line);
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
    auto then_scope = curOwner.newScope(ScopeId::FOR, Exit::get_exit_type(node->body.get()), cur_scope, node->body->line);
    resolv->newScope();
    if (node->decl) {
        node->decl->accept(this);
    }
    auto then = llvm::BasicBlock::Create(ctx(), "for_body_" + std::to_string(node->line));
    auto condbb = llvm::BasicBlock::Create(ctx(), "for_cond_" + std::to_string(node->line), func);
    auto updatebb = llvm::BasicBlock::Create(ctx(), "for_update_" + std::to_string(node->line), func);
    auto next = llvm::BasicBlock::Create(ctx(), "for_next_" + std::to_string(node->line));
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
    node->body->accept(this);
    curOwner.endScope(*then_scope);
    curOwner.setScope(cur_scope);
    Builder->CreateBr(updatebb);
    Builder->SetInsertPoint(updatebb);
    for (auto &u : node->updaters) {
        u->accept(this);
    }
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