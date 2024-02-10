#include "Compiler.h"
#include "TypeUtils.h"

void Compiler::init_dbg(const std::string &path) {
    if (!Config::debug) return;
    DBuilder = std::make_unique<llvm::DIBuilder>(*mod);
    auto dfile = DBuilder->createFile(path, ".");
    di.cu = DBuilder->createCompileUnit(llvm::dwarf::DW_LANG_C, dfile, "lang dbg", false, "", 0, "", llvm::DICompileUnit::DebugEmissionKind::FullDebug, 0, true, false, llvm::DICompileUnit::DebugNameTableKind::None);
    /*mod->addModuleFlag(llvm::Module::Max, "Dwarf Version", 3);
    mod->addModuleFlag(llvm::Module::Warning, "Debug Info Version", 3);
    mod->addModuleFlag(llvm::Module::Min, "PIC Level", 2);
    mod->addModuleFlag(llvm::Module::Max, "PIE Level", 2);*/
}

void Compiler::loc(Node *e) {
    if (!Config::debug) return;
    if (!e) {
        Builder->SetCurrentDebugLocation(nullptr);
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
    if (!Config::debug) return;
    llvm::DIScope *scope;
    if (di.sp) {
        scope = di.sp;
    } else {
        scope = di.cu;
    }
    Builder->SetCurrentDebugLocation(llvm::DILocation::get(scope->getContext(), line, pos, scope));
}

void Compiler::dbg_prm(Param &p, const Type &type, int idx) {
    if (!Config::debug) return;
    auto sp = di.sp;
    auto dt = map_di(type);
    auto v = DBuilder->createParameterVariable(sp, p.name, idx, di.file, p.line, dt, true);
    auto val = NamedValues[p.name];
    auto lc = llvm::DILocation::get(sp->getContext(), p.line, p.pos, sp);
    DBuilder->insertDeclare(val, v, DBuilder->createExpression(), lc, Builder->GetInsertBlock());
}

void Compiler::dbg_var(const std::string &name, int line, int pos, const Type &type) {
    if (!Config::debug) return;
    auto sp = di.sp;
    auto v = DBuilder->createAutoVariable(sp, name, di.file, line, map_di(type), true);
    auto val = NamedValues[name];
    auto lc = llvm::DILocation::get(sp->getContext(), line, pos, sp);
    auto e = DBuilder->createExpression();
    DBuilder->insertDeclare(val, v, e, lc, Builder->GetInsertBlock());
}

std::string Compiler::dbg_name(Method *m) {
    if (!m->parent) return m->name;
    if (m->parent->isImpl()) {
        auto impl = dynamic_cast<Impl *>(m->parent);
        return impl->type.name + "::" + m->name;
    } else if (m->parent->isTrait()) {
        auto t = dynamic_cast<Trait *>(m->parent);
        return t->type.name + "::" + m->name;
    }
    return m->name;
}

void Compiler::dbg_func(Method *m, llvm::Function *f) {
    if (!Config::debug) return;
    //llvm::SmallVector<llvm::Metadata *, 8> tys;
    std::vector<llvm::Metadata*> tys;
    tys.push_back(map_di(m->type));
    if (m->self) {
        auto elem = map_di(m->self->type->unwrap());
        auto ty = llvm::DIBuilder::createObjectPointerType(elem);
        tys.push_back(ty);
    }
    for (auto &p : m->params) {
        tys.push_back(map_di(*p.type));
    }
    auto ft = DBuilder->createSubroutineType(DBuilder->getOrCreateTypeArray(tys));
    auto file = DBuilder->createFile(m->unit->path, ".");
    di.file = file;
    std::string linkage_name;
    auto spflags = llvm::DISubprogram::SPFlagDefinition;
    if (is_main(m)) {
        spflags |= llvm::DISubprogram::SPFlagMainSubprogram;
    } else {
        linkage_name = mangle(m);
    }
    llvm::DIScope *scope = file;
    if (m->parent) {
        auto p = methodParent2(m);
        scope = map_di(p.value());
    }
    //auto name = dbg_name(m);
    auto &name = m->name;

    di.sp = DBuilder->createFunction(scope, name, linkage_name, file, m->line, ft, m->line, llvm::DINode::FlagPrototyped, spflags);
    f->setSubprogram(di.sp);
    loc(nullptr);
}

llvm::DIDerivedType *make_variant_type(EnumDecl *ed, EnumVariant &evar, Compiler *c, llvm::DICompositeType *var_part, llvm::DIFile *file, int size, int idx, llvm::DICompositeType *scope, int var_off) {
    auto name = ed->type.print() + "::" + evar.name;
    auto var_type = (llvm::StructType *) c->classMap[name];
    std::vector<llvm::Metadata *> elems;
    auto arr = llvm::DINodeArray(llvm::MDTuple::get(c->ctx(), elems));
    //auto var_size = c->mod->getDataLayout().getStructLayout(var_type)->getSizeInBits();
    auto st = c->DBuilder->createStructType(scope, name, file, ed->line, size, 0, llvm::DINode::FlagZero, nullptr, arr);
    auto sl = c->mod->getDataLayout().getStructLayout(var_type);
    int i = 0;
    for (auto &fd : evar.fields) {
        auto fdd = c->map_di(fd.type);
        auto off = sl->getElementOffsetInBits(i);
        auto member = c->DBuilder->createMemberType(st, fd.name, file, ed->line, c->getSize2(fd.type), 0, off, llvm::DINode::FlagZero, fdd);
        elems.push_back(member);
        ++i;
    }
    st->replaceElements(llvm::DINodeArray(llvm::MDTuple::get(c->ctx(), elems)));
    int align = 0;
    return c->DBuilder->createVariantMemberType(var_part, evar.name, file, ed->line, size, align, var_off, c->makeInt(idx), llvm::DINode::FlagZero, st);
}

llvm::DIType *Compiler::map_di_proto(BaseDecl *decl) {
    std::vector<llvm::Metadata *> elems;
    auto arr = llvm::DINodeArray(llvm::MDTuple::get(ctx(), elems));
    auto st_size = getSize2(decl);
    auto file = DBuilder->createFile(decl->unit->path, di.cu->getDirectory());
    auto name = decl->type.print();
    auto st = DBuilder->createStructType(di.cu, name, file, decl->line, st_size, 0, llvm::DINode::FlagZero, nullptr, arr);
    di.incomplete_types[name] = st;
    return st;
}

llvm::DIType *Compiler::map_di_fill(BaseDecl *decl) {
    auto st = di.incomplete_types.at(decl->type.print());
    di.types[decl->type.print()] = st;
    auto file = st->getFile();
    std::vector<llvm::Metadata *> elems;

    llvm::DIType *base_ty = nullptr;

    if (decl->base.has_value()) {
        base_ty = map_di(decl->base.value());
        //auto in = DBuilder->createInheritance(st, base_ty, 0, 0, llvm::DINode::FlagZero);
        auto mt = DBuilder->createMemberType(st, "super", file, decl->line, base_ty->getSizeInBits(), 0, 0, llvm::DINode::FlagZero, base_ty);
        elems.push_back(mt);
    }

    auto st1 = (llvm::StructType *) mapType(decl->type);
    auto sl = mod->getDataLayout().getStructLayout(st1);

    if (decl->isEnum()) {
        //todo order
        auto ed = (EnumDecl *) decl;
        auto enum_size = getSize2(ed);
        if (base_ty) {
            enum_size -= base_ty->getSizeInBits();
        }
        int var_idx = decl->base.has_value() ? 2 : 1;
        int tag_off = 0;
        int var_off = sl->getElementOffsetInBits(var_idx);
        if (decl->base.has_value()) {
            tag_off = sl->getElementOffsetInBits(1);
        }
        std::vector<llvm::Metadata *> elems2;
        auto tag = DBuilder->createBasicType("tag", ENUM_TAG_BITS, llvm::dwarf::DW_ATE_signed);
        auto disc = DBuilder->createMemberType(nullptr, "", file, ed->line, ENUM_TAG_BITS, 0, tag_off, llvm::DINode::FlagArtificial, tag);
        auto arr = llvm::DINodeArray(llvm::MDTuple::get(ctx(), elems2));
        auto var_part = DBuilder->createVariantPart(st, "", file, decl->line, enum_size, 0, llvm::DINode::FlagZero, disc, arr);
        int idx = 0;
        for (auto &evar : ed->variants) {
            auto var_type = make_variant_type(ed, evar, this, var_part, file, enum_size, idx, st, var_off);
            elems2.push_back(var_type);
            ++idx;
        }
        var_part->replaceElements(llvm::DINodeArray(llvm::MDTuple::get(ctx(), elems2)));
        elems.push_back(var_part);
    } else {
        auto sd = (StructDecl *) decl;
        int idx = 0;
        if (decl->base.has_value()) {
            idx++;
        }
        for (auto &fd : sd->fields) {
            auto off = sl->getElementOffsetInBits(idx);
            auto di_type = map_di(fd.type);
            auto mt = DBuilder->createMemberType(st, fd.name, file, fd.line, di_type->getSizeInBits(), 0, off, llvm::DINode::FlagZero, di_type);
            elems.push_back(mt);
            idx++;
        }
    }
    auto arr = llvm::DINodeArray(llvm::MDTuple::get(ctx(), elems));
    st->replaceElements(arr);
    return st;
}

llvm::DIType *Compiler::map_di0(const Type *t) {
    auto rt = resolv->resolve(*t);
    t = &rt.type;
    auto s = t->print();
    if (di.types.contains(s)) {
        return di.types.at(s);
    }
    if (s == "void") return nullptr;
    if (s == "bool") return DBuilder->createBasicType(s, 8, llvm::dwarf::DW_ATE_boolean);
    if (s == "i8") return DBuilder->createBasicType(s, 8, llvm::dwarf::DW_ATE_signed);
    if (s == "i16") return DBuilder->createBasicType(s, 16, llvm::dwarf::DW_ATE_signed);
    if (s == "i32") return DBuilder->createBasicType(s, 32, llvm::dwarf::DW_ATE_signed);
    if (s == "i64") return DBuilder->createBasicType(s, 64, llvm::dwarf::DW_ATE_signed);
    if (s == "f32") return DBuilder->createBasicType(s, 32, llvm::dwarf::DW_ATE_float);
    if (s == "f64") return DBuilder->createBasicType(s, 64, llvm::dwarf::DW_ATE_float);
    if (s == "u8") return DBuilder->createBasicType(s, 8, llvm::dwarf::DW_ATE_unsigned);
    if (s == "u16") return DBuilder->createBasicType(s, 16, llvm::dwarf::DW_ATE_unsigned);
    if (s == "u32") return DBuilder->createBasicType(s, 32, llvm::dwarf::DW_ATE_unsigned);
    if (s == "u64") return DBuilder->createBasicType(s, 64, llvm::dwarf::DW_ATE_unsigned);
    if (t->isPointer()) {
        auto elem = t->unwrap();
        if (di.incomplete_types.contains(elem.print())) {
            auto st = di.incomplete_types.at(elem.print());
            return DBuilder->createPointerType(st, 64);
        } else {
            return DBuilder->createPointerType(map_di(&elem), 64);
        }
        /*if (di.types.contains(elem.print()) || rt.targetDecl == nullptr) {
            return DBuilder->createPointerType(map_di(&elem), 64);
        } else {
            //make incomplete type to fill later
            auto file = DBuilder->createFile(rt.targetDecl->unit->path, di.cu->getDirectory());
            auto st_size = getSize2(elem);
            std::vector<llvm::Metadata *> elems;
            auto et = llvm::DINodeArray(llvm::MDTuple::get(ctx(), elems));
            auto st = DBuilder->createStructType(di.cu, elem.print(), file, 0, st_size, 0, llvm::DINode::FlagZero, nullptr, et);
            di.incomplete_types[elem.print()] = st;
            return DBuilder->createPointerType(st, 64);
        }*/
    }
    if (t->isArray()) {
        std::vector<llvm::Metadata *> elems;
        elems.push_back(DBuilder->getOrCreateSubrange(0, t->size));
        llvm::DINodeArray sub(llvm::MDTuple::get(ctx(), elems));
        auto elem = map_di(t->scope.get());
        auto size = getSize2(t);
        return DBuilder->createArrayType(size, 0, elem, sub);
    }
    if (t->isSlice()) {
        auto sz = getSize2(t);
        auto file = DBuilder->createFile(di.cu->getFilename(), di.cu->getDirectory());
        std::vector<llvm::Metadata *> elems;
        auto ptr_ty = DBuilder->createPointerType(map_di(t->scope.get()), 64);
        auto ptr_mem = DBuilder->createMemberType(nullptr, "ptr", file, 0, 64, 0, 0, llvm::DINode::FlagZero, ptr_ty);
        elems.push_back(ptr_mem);
        auto len_ty = map_di(getType(SLICE_LEN_BITS));
        auto len_mem = DBuilder->createMemberType(nullptr, "len", file, 0, SLICE_LEN_BITS, 0, 64, llvm::DINode::FlagZero, len_ty);
        elems.push_back(len_mem);
        auto et = llvm::DINodeArray(llvm::MDTuple::get(ctx(), elems));
        return DBuilder->createStructType(di.cu, s, file, 0, sz, 0, llvm::DINode::FlagZero, nullptr, et);
    }
    throw std::runtime_error("di type: " + t->print());
}