#include "MethodResolver.h"

void Resolver::findMethod(MethodCall *mc, std::vector<Method *> &list, std::vector<Method *> &generics) {
    // for (auto m : generatedMethods) {
    //     if (m->name == mc->name) {
    //         if (m->isGeneric) {
    //             generics.push_back(m);
    //         } else {
    //             list.push_back(m);
    //         }
    //     }
    // }
    for (auto &item : unit->items) {
        if (item->isMethod()) {
            auto m = dynamic_cast<Method *>(item.get());
            if (m->name != mc->name) {
                continue;
            }
            if (m->isGeneric) {
                generics.push_back(m);
            } else {
                list.push_back(m);
            }
        }
    }
    if (curImpl) {
        //static sibling
        for (auto &m : curImpl->methods) {
            if (!m->self && m->name == mc->name) {
                if (m->isGeneric) {
                    generics.push_back(m.get());
                } else {
                    list.push_back(m.get());
                }
            }
        }
    }
}