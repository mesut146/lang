#include "Converter.h"
#include "Resolver.h"
#include "parser/Ast.h"
#include "parser/Parser.h"
#include <filesystem>
#include <iostream>
#include <unordered_map>
//#include <llvm/IR/Value.h>

namespace fs = std::filesystem;

static std::string getName(const std::string &path) {
    auto i = path.rfind('/');
    return path.substr(i + 1);
}

std::string makeType(Type *type) {
    auto ptr = dynamic_cast<PointerType *>(type);
    if (ptr) {
        return makeType(ptr->type) + "*";
    }
    if (type->isVoid()) return "void";
    if (type->isPrim()) {
        auto s = type->print();
        std::unordered_map<std::string, std::string> map{{"i8", "char"},
                                                         {"i16", "short"},
                                                         {"i32", "int"},
                                                         {"i64", "int64_t"},
                                                         {"byte", "char"},
                                                         {"int", "int"},
                                                         {"char", "int"},
                                                         {"long", "int64_t"},
                                                         {"float", "float"},
                                                         {"double", "double"}};
        return map.at(s);
    }
    if (type->isArray()) {
        throw std::runtime_error("array type");
    }
    if (type->scope == nullptr) {
        return type->name;
    }
    throw std::runtime_error("scoped type");
}

int size(Type *type) {
    auto s = type->print();
    if (s == "byte") return 1;
    if (s == "int") return 4;
    if (s == "long") return 8;
    throw std::runtime_error("size(" + s + ")");
}

int size(EnumDecl *e) {
    int res = 0;
    for (auto ee : e->cons) {
        if (ee->params.empty()) continue;
        int cur = 0;
        for (auto ep : ee->params) {
            cur += size(ep->type);
        }
        res = cur > res ? cur : res;
    }
    return res;
}

void Converter::header(const std::string &name) {
    auto cpp = outDir + "/" + name + ".h";
    hs.open(cpp.c_str(), hs.out);
    hs << "#pragma once\n\n";

    for (auto bd : unit->types) {
        hs << "struct " << bd->name << "{\n";
        if (bd->isEnum) {
            auto e = (EnumDecl *) bd;
            int cnt = e->cons.size();
            hs << "  int ord;\n";
            int sz = size(e);
            hs << "  char data[" << sz << "];\n";
        } else {
            auto td = (TypeDecl *) bd;
            for (auto fd : td->fields) {
                hs << "  ";
                hs << makeType(fd->type);
                hs << " " << fd->name << ";\n";
            }
        }
        hs << "};\n";
    }

    for (auto m : unit->methods) {
        hs << makeType(m->type);
        hs << " ";
        hs << m->name;
        hs << "(";
        int i = 0;
        for (auto &p : m->params) {
            if (i > 0) hs << ", ";
            hs << makeType(p->type);
            hs << " ";
            hs << p->name;
            i++;
        }
        hs << ");\n";
    }
    hs.close();
}

void Converter::source( const std::string &name) {
    auto cpp = outDir + "/" + name + ".cpp";
    ss.open(cpp.c_str(), ss.out);
    ss << "#include \"" << name << ".h\"\n";
    ss << "#include \"util.h\"\n";
    ss << "\n";
    for (auto &m : unit->methods) {
        ss << makeType(m->type);
        ss << " ";
        ss << m->name;
        ss << "(";
        int i = 0;
        for (auto &p : m->params) {
            if (i > 0) ss << ", ";
            ss << makeType(p->type);
            ss << " ";
            ss << p->name;
            i++;
        }
        ss << ")";
        m->body->accept(this, nullptr);
        ss << "\n\n";
    }
    ss.close();
}

void Converter::convert(const std::string &path) {
    auto name = getName(path);
    if (path.rfind(".x") == std::string::npos) {
        //copy res
        std::ifstream src;
        src.open(path, src.binary);
        std::ofstream trg;
        trg.open(outDir + "/" + name, trg.binary);
        trg << src.rdbuf();
        return;
    }
    std::cout << "converting " << path << std::endl;
    Lexer lexer(path);
    Parser parser(lexer);
    unit = parser.parseUnit();
    header( name);
    source( name);
}

void Converter::convertAll() {
    for (const auto &e : fs::recursive_directory_iterator(srcDir)) {
        if (e.is_directory()) continue;
        convert(e.path().string());
    }
}

void *Converter::visitBlock(Block *b, void *arg) {
    ss << "{\n";
    for (auto &s : b->list) {
        ss << "  ";
        s->accept(this, arg);
        ss << "\n";
    }
    ss << "}";
    return nullptr;
}

void *Converter::visitReturnStmt(ReturnStmt *r, void *arg) {
    ss << "return ";
    if (r->expr) r->expr->accept(this, arg);
    ss << ";";
    return nullptr;
}

void *Converter::visitExprStmt(ExprStmt *r, void *arg) {
    r->expr->accept(this, arg);
    ss << ";";
    return nullptr;
}

void *Converter::visitInfix(Infix *b, void *arg) {
    b->left->accept(this, arg);
    ss << b->op;
    b->right->accept(this, arg);
    return nullptr;
}

void *Converter::visitSimpleName(SimpleName *r, void *arg) {
    ss << r->name;
    return nullptr;
}

void *Converter::visitLiteral(Literal *r, void *arg) {
    ss << r->print();
    return nullptr;
}

Method *resolve(MethodCall *mc, Unit *unit) {
    for (auto &m : unit->methods) {
        if (m->name != mc->name) continue;
        //todo optional
        if (m->params.size() != mc->args.size()) continue;
        return m;
    }
    throw std::runtime_error("no such method: " + mc->name);
}

void handlePrint(MethodCall *m, Converter *c) {
    auto &ss = c->ss;
    ss << m->name;
    ss << "(";
    int i = 0;
    for (auto &a : m->args) {
        if (i > 0) ss << ",";
        auto lit = dynamic_cast<Literal *>(a);
        if (lit) {
            auto str = lit->print();
            if (lit->isStr) {
                ss << str;
            } else if (lit->isInt) {
                ss << "std::to_string(" << str << ").c_str()";
            } else if (lit->isBool) {
                ss << str;
            }
        } else {
            auto mc = dynamic_cast<MethodCall *>(a);
            if (mc) {
                auto m = resolve(mc, c->unit);
                auto ts = m->type->print();
                if (ts == "int") {
                    ss << "std::to_string(";
                    mc->accept(c, nullptr);
                    ss << ").c_str()";
                }
            }
        }
        i++;
    }
    ss << ")";
}

void *Converter::visitMethodCall(MethodCall *m, void *arg) {
    if (m->scope) {
        m->scope->accept(this, arg);
        ss << ".";
    } else {
        if (m->name == "print") {
            handlePrint(m, this);
            return nullptr;
        }
    }
    ss << m->name;
    ss << "(";
    int i = 0;
    for (auto &a : m->args) {
        if (i > 0) ss << ",";
        a->accept(this, arg);
        i++;
    }
    ss << ")";
    return nullptr;
}

void *Converter::visitAssertStmt(AssertStmt *r, void *arg) {
    ss << "assert(";
    r->expr->accept(this, arg);
    ss << ");";
    return nullptr;
}

void *Converter::visitVarDecl(VarDecl *v, void *arg) {
    for (auto &f : v->decl->list) {
        ss << makeType(f->type);
        ss << " " << f->name;
        ss << " = ";
        f->rhs->accept(this, arg);
        ss << ";";
    }
    return nullptr;
}

void *Converter::visitRefExpr(RefExpr *v, void *arg) {
    ss << "&";
    //todo rvalue...
    if (dynamic_cast<Name *>(v->expr)) {
        v->expr->accept(this, arg);
        return nullptr;
    }
    Resolver r(unit);
    auto type = (RType *) v->expr->accept(&r, nullptr);
    std::cout << type->type->print();
    v->expr->accept(this, arg);
    return nullptr;
}

void *Converter::visitDerefExpr(DerefExpr *v, void *arg) {
    ss << "*";
    //todo rvalue...
    v->expr->accept(this, arg);
    return nullptr;
}

void *Converter::visitParExpr(ParExpr *v, void *arg) {
    ss << "(";
    v->expr->accept(this, arg);
    ss << ")";
    return nullptr;
}

void *Converter::visitObjExpr(ObjExpr *v, void *arg) {
    if (v->isPointer) {
        ss << "new ";
    }
    ss << makeType(v->type);
    ss << "{";
    int i = 0;
    for (auto &e : v->entries) {
        if (i > 0) ss << " ,";
        ss << "." << e.key;
        ss << " = ";
        e.value->accept(this, arg);
        i++;
    }
    ss << "}";
    return nullptr;
}