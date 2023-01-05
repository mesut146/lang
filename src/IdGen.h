#pragma once

#include "Visitor.h"

class IdGen : public Visitor {
public:
    Unit *unit;

    

    // void *visitBaseDecl(BaseDecl *bd, void *arg) override;
    // void *visitFieldDecl(FieldDecl *fd, void *arg) override;
    // void *visitMethod(Method *m, void *arg) override;
    // void *visitParam(Param *p, void *arg) override;
};