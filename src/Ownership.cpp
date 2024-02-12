#include "Ownership.h"
#include "Resolver.h"

bool isDrop(BaseDecl *decl, Resolver *r) {
    if (decl->isDrop()) return true;
    auto sd = dynamic_cast<StructDecl *>(decl);
    if (sd) {
        for (auto &fd : sd->fields) {
            if (!isStruct(fd.type)) continue;
            auto rt = r->resolve(fd.type);
            if (isDrop(rt.targetDecl, r)) return true;
        }
    } else {
        auto ed = dynamic_cast<EnumDecl *>(decl);
        //iter variants
        for (auto &v : ed->variants) {
            //iter fields
            for (auto &fd : v.fields) {
                if (!isStruct(fd.type)) continue;
                auto rt = r->resolve(fd.type);
                if (isDrop(rt.targetDecl, r)) return true;
            }
        }
    }
    return false;
}