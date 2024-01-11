#include "Compiler.h"

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
    llvm::SmallVector<llvm::Metadata *, 8> tys;
    tys.push_back(map_di(m->type));
    if (m->self) {
        tys.push_back(map_di(*m->self->type));
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
    llvm::DIScope *scope = nullptr;
    if (m->parent) {
        auto p = methodParent2(m);
        scope = map_di(p.value());
    }
    auto name = dbg_name(m);
    auto sp = DBuilder->createFunction(scope, name, linkage_name, file, m->line, ft, m->line, llvm::DINode::FlagPrototyped, spflags);
    di.sp = sp;
    f->setSubprogram(sp);
    loc(nullptr);
}

llvm::DIDerivedType *make_variant_type(EnumDecl *ed, EnumVariant &evar, Compiler *c, llvm::DICompositeType *var_part, llvm::DIFile *file, int size, int idx, llvm::DICompositeType *scope) {
    auto name = ed->type.print() + "::" + evar.name;
    auto var_type = (llvm::StructType *) c->classMap[name];
    std::vector<llvm::Metadata *> elems;
    auto arr = llvm::DINodeArray(llvm::MDTuple::get(c->ctx(), elems));
    auto var_size = c->mod->getDataLayout().getStructLayout(var_type)->getSizeInBits();
    auto st = c->DBuilder->createStructType(scope, evar.name, file, ed->line, size, 0, llvm::DINode::FlagZero, nullptr, arr);
    auto sl = c->mod->getDataLayout().getStructLayout(var_type);
    int i = 0;
    for (auto &fd : evar.fields) {
        auto fdd = c->map_di(fd.type);
        auto off = sl->getElementOffsetInBits(i) + ENUM_TAG_BITS;
        auto member = c->DBuilder->createMemberType(st, fd.name, file, ed->line, c->getSize2(fd.type), 0, off, llvm::DINode::FlagZero, fdd);
        elems.push_back(member);
        ++i;
    }
    st->replaceElements(llvm::DINodeArray(llvm::MDTuple::get(c->ctx(), elems)));
    int align = 0;
    return c->DBuilder->createVariantMemberType(var_part, evar.name, file, ed->line, size, align, 0, c->makeInt(idx), llvm::DINode::FlagZero, st);
}


llvm::DIType *Compiler::map_di0(const Type *t) {
    auto rt = resolv->resolve(*t);
    t = &rt.type;
    auto s = t->print();
    auto it = di.types.find(s);
    if (it != di.types.end()) return it->second;
    if (t->isPointer()) {
        auto elem = t->unwrap();
        if (di.types.contains(elem.print())) {
            return DBuilder->createPointerType(map_di(&elem), 64);
        } else {
            if (!rt.targetDecl) {
                return DBuilder->createPointerType(map_di(&elem), 64);
            }
            auto file = DBuilder->createFile(rt.targetDecl->unit->path, di.cu->getDirectory());
            auto st_size = getSize2(t);
            std::vector<llvm::Metadata *> elems;
            auto et = llvm::DINodeArray(llvm::MDTuple::get(ctx(), elems));
            auto st = DBuilder->createStructType(di.cu, s, file, 0, st_size, 0, llvm::DINode::FlagZero, nullptr, et);
            di.incomplete_types[elem.print()] = st;
            return DBuilder->createPointerType(st, 64);
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
        auto len_ty = map_di(new Type("i32"));
        auto len_mem = DBuilder->createMemberType(nullptr, "len", file, 0, SLICE_LEN_BITS, 0, 64, llvm::DINode::FlagZero, len_ty);
        elems.push_back(len_mem);
        auto et = llvm::DINodeArray(llvm::MDTuple::get(ctx(), elems));
        return DBuilder->createStructType(di.cu, s, file, 0, sz, 0, llvm::DINode::FlagZero, nullptr, et);
    }
    if (s == "bool") return DBuilder->createBasicType(s, 8, llvm::dwarf::DW_ATE_boolean);
    if (s == "i8") return DBuilder->createBasicType(s, 8, llvm::dwarf::DW_ATE_signed);
    if (s == "i16") return DBuilder->createBasicType(s, 16, llvm::dwarf::DW_ATE_signed);
    if (s == "i32") return DBuilder->createBasicType(s, 32, llvm::dwarf::DW_ATE_signed);
    if (s == "i64") return DBuilder->createBasicType(s, 64, llvm::dwarf::DW_ATE_signed);
    if (s == "f32") return DBuilder->createBasicType(s, 32, llvm::dwarf::DW_ATE_float);
    if (s == "i64") return DBuilder->createBasicType(s, 64, llvm::dwarf::DW_ATE_float);
    if (s == "void") return nullptr;
    if (s == "u8") return DBuilder->createBasicType(s, 8, llvm::dwarf::DW_ATE_unsigned);
    if (s == "u16") return DBuilder->createBasicType(s, 16, llvm::dwarf::DW_ATE_unsigned);
    if (s == "u32") return DBuilder->createBasicType(s, 32, llvm::dwarf::DW_ATE_unsigned);
    if (s == "u64") return DBuilder->createBasicType(s, 64, llvm::dwarf::DW_ATE_unsigned);
    if (!rt.targetDecl) {
        throw std::runtime_error("di type: " + t->print());
    }
    auto file = DBuilder->createFile(rt.targetDecl->unit->path, di.cu->getDirectory());
    std::vector<llvm::Metadata *> elems;
    llvm::DICompositeType *st;

    if (di.incomplete_types.contains(s)) {
        st = di.incomplete_types[s];
    } else {
        //empty type
        auto st_size = getSize2(t);
        auto arr = llvm::DINodeArray(llvm::MDTuple::get(ctx(), elems));
        st = DBuilder->createStructType(di.cu, s, file, rt.targetDecl->line, st_size, 0, llvm::DINode::FlagZero, nullptr, arr);
    }

    if (rt.targetDecl->isEnum()) {
        //todo order
        auto ed = (EnumDecl *) rt.targetDecl;
        auto tag = DBuilder->createBasicType("tag", ENUM_TAG_BITS, llvm::dwarf::DW_ATE_signed);
        /*auto tagm = DBuilder->createMemberType(nullptr, "tag", file, ed->line, ENUM_TAG_BITS, 0, 0, llvm::DINode::FlagZero, tag);
        elems.push_back(tagm);*/
        auto enum_size = getSize2(ed);
        auto data_size = enum_size - ENUM_TAG_BITS;
        //auto chr = DBuilder->createBasicType("i8", 8, llvm::dwarf::DW_ATE_signed);
        /*llvm::DINodeArray sub;
        auto at = DBuilder->createArrayType(data_size, 0, chr, sub);*/
        /*auto arrm = DBuilder->createMemberType(nullptr, "data", file, ed->line, data_size, 0, ENUM_TAG_BITS, llvm::DINode::FlagZero, at);
        elems.push_back(arrm);*/
        std::vector<llvm::Metadata *> elems2;
        auto disc = DBuilder->createMemberType(nullptr, "", file, ed->line, ENUM_TAG_BITS, 0, 0, llvm::DINode::FlagArtificial, tag);
        auto arr = llvm::DINodeArray(llvm::MDTuple::get(ctx(), elems2));
        auto var_part = DBuilder->createVariantPart(st, "", file, rt.targetDecl->line, enum_size, 0, llvm::DINode::FlagZero, disc, arr);
        int idx = 0;
        for (auto &evar : ed->variants) {
            auto var_type = make_variant_type(ed, evar, this, var_part, file, enum_size, idx, st);
            elems2.push_back(var_type);
            ++idx;
        }
        var_part->replaceElements(llvm::DINodeArray(llvm::MDTuple::get(ctx(), elems2)));
        elems.push_back(var_part);
    } else {
        auto sd = (StructDecl *) rt.targetDecl;
        int idx = 0;
        auto st1 = (llvm::StructType *) mapType(sd->type);
        auto sl = mod->getDataLayout().getStructLayout(st1);
        for (auto &fd : sd->fields) {
            auto off = sl->getElementOffsetInBits(idx);
            auto di_type = map_di(fd.type);
            auto mt = DBuilder->createMemberType(nullptr, fd.name, file, fd.line, di_type->getSizeInBits(), 0, off, llvm::DINode::FlagZero, di_type);
            elems.push_back(mt);
            idx++;
        }
    }
    auto arr = llvm::DINodeArray(llvm::MDTuple::get(ctx(), elems));
    st->replaceElements(arr);
    return st;
}