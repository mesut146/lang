#include "Compiler.h"
#include "TypeUtils.h"

void Compiler::init_dbg(const std::string &path) {
    if (!Config::debug) return;
    DBuilder = std::make_unique<llvm::DIBuilder>(*mod);
    auto dfile = DBuilder->createFile(path, ".");
    di.cu = DBuilder->createCompileUnit(llvm::dwarf::DW_LANG_Zig, dfile, "lang dbg", false, "", 0, "", llvm::DICompileUnit::DebugEmissionKind::FullDebug, 0, true, false, llvm::DICompileUnit::DebugNameTableKind::None);
    /*mod->addModuleFlag(llvm::Module::Max, "Dwarf Version", 3);
    mod->addModuleFlag(llvm::Module::Warning, "Debug Info Version", 3);
    mod->addModuleFlag(llvm::Module::Min, "PIC Level", 2);
    mod->addModuleFlag(llvm::Module::Max, "PIE Level", 2);*/
}

void Compiler::loc(Node *e) {
    if (!Config::debug) return;
    if (e == nullptr) {
        Builder->SetCurrentDebugLocation(nullptr);
        return;
    }
    if (e->line == 0) {
        error(std::string("loc line 0, ") + e->print());
    }
    loc(e->line, 0);
}

void Compiler::loc(int line, int pos) {
    if (!Config::debug) return;
    if (line == 0) {
        throw std::runtime_error("dbg loc line 0");
    }
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
    auto v = DBuilder->createParameterVariable(sp, p.name, idx, di.file, p.line, dt, false);
    auto val = NamedValues.at(p.name);
    auto lc = llvm::DILocation::get(sp->getContext(), p.line, p.pos, sp);
    DBuilder->insertDeclare(val, v, DBuilder->createExpression(), lc, Builder->GetInsertBlock());
}

void Compiler::dbg_var(const std::string &name, int line, int pos, const Type &type) {
    if (!Config::debug) return;
    auto sp = di.sp;
    auto v = DBuilder->createAutoVariable(sp, name, di.file, line, map_di(type), false);
    auto val = NamedValues.at(name);
    auto lc = llvm::DILocation::get(sp->getContext(), line, pos, sp);
    auto e = DBuilder->createExpression();
    DBuilder->insertDeclare(val, v, e, lc, Builder->GetInsertBlock());
}

std::string Compiler::dbg_name(Method *m) {
    if (m->parent.is_none()) return m->name;
    if (m->parent.is_impl()) {
        return m->parent.type->name + "::" + m->name;
    } else if (m->parent.is_trait()) {
        return m->parent.type->name + "::" + m->name;
    }
    return m->name;
}

void Compiler::dbg_func(Method *m, llvm::Function *f) {
    if (!Config::debug) return;
    //llvm::SmallVector<llvm::Metadata *, 8> tys;
    std::vector<llvm::Metadata *> tys;
    tys.push_back(map_di(m->type));
    if (m->self) {
        auto self_ty = map_di(m->self->type->unwrap());
        /*if (!m->self->is_deref) {
            self_ty = llvm::DIBuilder::createObjectPointerType(self_ty);
        }*/
        tys.push_back(self_ty);
    }
    for (auto &p : m->params) {
        tys.push_back(map_di(*p.type));
    }
    auto ft = DBuilder->createSubroutineType(DBuilder->getOrCreateTypeArray(tys));
    auto file = DBuilder->createFile(m->path, ".");
    di.file = file;
    std::string linkage_name;
    auto spflags = llvm::DISubprogram::SPFlagDefinition;
    if (is_main(m)) {
        spflags |= llvm::DISubprogram::SPFlagMainSubprogram;
    } else {
        linkage_name = mangle(m);
    }
    llvm::DIScope *scope = file;
    if (!m->parent.is_none()) {
        auto p = methodParent2(m);
        scope = map_di(p.value());
    }
    //auto name = dbg_name(m);
    auto &name = m->name;

    di.sp = DBuilder->createFunction(scope, name, linkage_name, file, m->line, ft, m->line, llvm::DINode::FlagPrototyped, spflags);
    f->setSubprogram(di.sp);
    loc(nullptr);
}

llvm::DIDerivedType *make_variant_type(EnumDecl *ed, EnumVariant &evar, Compiler *c, llvm::DICompositeType *var_part, llvm::DIFile *file, int idx, llvm::DICompositeType *scope, int var_off, llvm::DIType *base_ty) {
    auto name = ed->type.print() + "::" + evar.name;
    auto var_type = (llvm::StructType *) c->classMap[name];
    auto var_size = c->mod->getDataLayout().getStructLayout(var_type)->getSizeInBits();
    std::vector<llvm::Metadata *> elems;
    auto st = c->di.incomplete_types.at(name);
    auto sl = c->mod->getDataLayout().getStructLayout(var_type);
    int i = 0;
    if (ed->base.has_value()) {
        //auto in = DBuilder->createInheritance(st, base_ty, 0, 0, llvm::DINode::FlagZero);
        auto mt = c->DBuilder->createMemberType(st, "super", file, ed->line, base_ty->getSizeInBits(), 0, 0, llvm::DINode::FlagZero, base_ty);
        elems.push_back(mt);
        i++;
    }
    for (auto &fd : evar.fields) {
        auto fdd = c->map_di(fd.type);
        auto off = sl->getElementOffsetInBits(i);
        auto member = c->DBuilder->createMemberType(st, fd.name, file, ed->line, c->getSize2(fd.type), 0, off, llvm::DINode::FlagZero, fdd);
        elems.push_back(member);
        ++i;
    }
    st->replaceElements(llvm::DINodeArray(llvm::MDTuple::get(c->ctx(), elems)));
    int align = 0;
    return c->DBuilder->createVariantMemberType(var_part, evar.name, file, ed->line, var_size, align, var_off, c->makeInt(idx), llvm::DINode::FlagZero, st);
}

llvm::DIType *Compiler::map_di_proto(BaseDecl *decl) {
    auto name = decl->type.print();
    std::vector<llvm::Metadata *> elems;
    auto arr = llvm::DINodeArray(llvm::MDTuple::get(ctx(), elems));
    auto st_size = getSize2(decl);
    auto file = DBuilder->createFile(decl->path, di.cu->getDirectory());
    int align = 0;
    auto st = DBuilder->createStructType(di.cu, name, file, decl->line, st_size, align, llvm::DINode::FlagZero, nullptr, arr);
    di.incomplete_types[name] = st;
    //todo variants here
    if (decl->isEnum()) {
        auto ed = (EnumDecl *) decl;
        for (auto &ev : ed->variants) {
            auto var_name = decl->type.print() + "::" + ev.name;
            std::vector<llvm::Metadata *> elems2;
            auto var_arr = llvm::DINodeArray(llvm::MDTuple::get(ctx(), elems2));
            auto var_size = st_size - ENUM_TAG_BITS;
            auto file = DBuilder->createFile(decl->path, di.cu->getDirectory());
            int align = 0;
            auto var_st = DBuilder->createStructType(di.cu, var_name, file, decl->line, var_size, align, llvm::DINode::FlagZero, nullptr, var_arr);
            di.incomplete_types[var_name] = var_st;
        }
    }
    return st;
}

llvm::DIType *Compiler::map_di_fill(BaseDecl *decl) {
    auto name = decl->type.print();
    auto st = di.incomplete_types.at(name);
    di.types[name] = st;
    auto file = st->getFile();
    std::vector<llvm::Metadata *> elems;

    llvm::DIType *base_ty = nullptr;
    if (decl->base.has_value()) {
        base_ty = map_di(decl->base.value());
    }

    auto st1 = (llvm::StructType *) mapType(decl->type);
    auto sl = mod->getDataLayout().getStructLayout(st1);

    if (decl->isEnum()) {
        //tag, {base, ...fields}
        auto ed = (EnumDecl *) decl;
        //create variant part
        int tag_off = 0;
        auto tag = DBuilder->createBasicType("tag", ENUM_TAG_BITS, llvm::dwarf::DW_ATE_signed);
        auto disc = DBuilder->createMemberType(nullptr, "", file, ed->line, ENUM_TAG_BITS, 0, tag_off, llvm::DINode::FlagArtificial, tag);
        std::vector<llvm::Metadata *> var_elems;
        auto arr = llvm::DINodeArray(llvm::MDTuple::get(ctx(), var_elems));
        int data_size = getSize2(decl) - ENUM_TAG_BITS;
        auto var_part = DBuilder->createVariantPart(st, "", file, decl->line, data_size, 0, llvm::DINode::FlagZero, disc, arr);
        //fill variant part
        int idx = 0;
        int var_off = sl->getElementOffsetInBits(Layout::get_data_index(decl));
        for (auto &evar : ed->variants) {
            auto var_type_di = make_variant_type(ed, evar, this, var_part, file, idx, st, var_off, base_ty);
            var_elems.push_back(var_type_di);
            ++idx;
        }
        var_part->replaceElements(llvm::DINodeArray(llvm::MDTuple::get(ctx(), var_elems)));
        elems.push_back(var_part);
    } else {
        auto sd = (StructDecl *) decl;
        int idx = 0;
        if (decl->base.has_value()) {
            //auto in = DBuilder->createInheritance(st, base_ty, 0, 0, llvm::DINode::FlagZero);
            auto mt = DBuilder->createMemberType(st, "super", file, decl->line, base_ty->getSizeInBits(), 0, 0, llvm::DINode::FlagZero, base_ty);
            elems.push_back(mt);
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
    if (di.incomplete_types.contains(s)) {
        return di.incomplete_types.at(s);
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