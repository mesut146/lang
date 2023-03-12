#include "parser/Ast.h"
#include "Visitor.h"
#include "parser/Util.h"

std::string &BaseDecl::getName() {
    return type->name;
}

std::string RefExpr::print() {
    return "&" + expr->print();
}
std::string DerefExpr::print() {
    return "*" + expr->print();
}

std::string FieldDecl::print() const {
    return name + ": " + type->print();
}

std::string Unit::print() {
    std::string s;
    s.append(join(imports, "\n"));
    if (!imports.empty()) s.append("\n\n");
    s.append(joinPtr(items, "\n\n"));
    s.append("\n");
    return s;
}

std::string ImportStmt::print() {
    std::string s;
    s.append("import ");
    s.append(join(list, "/"));
    s.append(";");
    return s;
}

std::string EnumDecl::print() {
    std::string s;
    s.append("enum ");
    s.append(type->print());
    s.append("{\n");
    s.append(join(variants, ",\n", "  "));
    s.append(";\n}");
    return s;
}

std::string EnumVariant::print() {
    std::string s;
    s.append(name);
    if (isStruct()) {
        s.append("(");
        s.append(joinPtr(fields, ", "));
        s.append(")");
    }
    return s;
}

std::string StructDecl::print() {
    std::string s;
    s.append("struct ");
    s.append(type->print());
    s.append("{\n");
    for (int i = 0; i < fields.size(); i++) {
        s.append("  ").append(fields[i]->print()).append(";");
        if (i < fields.size() - 1) s.append("\n");
    }
    s.append("\n}");
    return s;
}

std::string Trait::print() {
    std::string s;
    s.append("trait ").append(type->print()).append("{\n");
    s.append(join(methods, "\n"));
    s.append("}\n");
    return s;
}

std::string Impl::print() {
    std::string s;
    s.append("impl ");
    if (trait_name) {
        s.append(trait_name->print()).append(" for ");
    }
    s.append(type->print());
    s.append("{\n");
    s.append(join(methods, "\n"));
    s.append("}\n");
    return s;
}
std::string Extern::print() {
    return "extern {" +join(methods, "\n")+"\n}";
}

std::string Method::print() {
    std::string s;
    s.append("func ");
    s.append(name);
    if (!typeArgs.empty()) {
        s.append("<");
        s.append(join(typeArgs, ","));
        s.append(">");
    }
    s.append("(");
    if (self) {
        s.append(self->name);
        if (self->type) {
            s.append(": ");
            s.append(self->type->print());
        }
        if (!params.empty()) s.append(", ");
    }
    s.append(join(params, ", "));
    s.append(")");
    if (type) {
        s.append(": ");
        s.append(type->print());
    }
    if (body) {
        s.append(body->print());
    } else {
        s.append(";");
    }
    return s;
}

std::string SimpleName::print() {
    return name;
}

std::string Literal::print() {
    std::string s;
    s.append(val);
    if (suffix) {
        s.append(suffix->print());
    }
    return s;
}


std::string VarDecl::print() {
    return decl->print() + ";";
}


std::string VarDeclExpr::print() {
    std::string s;
    if (isStatic) s.append("static ");
    s.append(!isConst ? "let" : "const");
    s.append(" ");
    s.append(join(list, ", "));
    return s;
}


std::string Fragment::print() {
    std::string s;
    s.append(name);
    if (type) {
        s.append(": ").append(type->print());
    }
    s.append(" = ").append(rhs->print());
    return s;
}

std::string ExprStmt::print() {
    return expr->print() + ";";
}

std::string Block::print() {
    std::string s;
    s.append("{\n");
    for (int i = 0; i < list.size(); ++i) {
        printIdent(list[i]->print(), s);
    }
    s.append("\n}");
    return s;
}

std::string printDims(std::vector<Expression *> &dims) {
    std::string s;
    for (Expression *e : dims) {
        s.append("[");
        if (e != nullptr) {
            s.append(e->print());
        }
        s.append("]");
    }
    return s;
}

std::string PointerType::print() {
    return type->print() + "*";
}
std::string OptionType::print() {
    return type->print() + "?";
}
std::string ArrayType::print() {
    auto sz = std::to_string(size);
    return "[" + type->print() + "; " + sz + "]";
}
std::string SliceType::print() {
    return "[" + type->print() + "]";
}

std::string Type::print() {
    std::string s;
    if (scope) {
        s.append(scope->print()).append("::");
    }
    s.append(name);
    if (!typeArgs.empty()) {
        s.append("<");
        s.append(join(typeArgs, ", "));
        s.append(">");
    }
    return s;
}

std::string Param::print() {
    std::string s;
    s.append(name);
    s.append(": ");
    s.append(type->print());
    return s;
}

std::string ParExpr::print() {
    return std::string("(" + expr->print() + ")");
}

std::string ObjExpr::print() {
    std::string s;
    if (isPointer) {
        s.append("new ");
    }
    s.append(type->print());
    s.append("{");
    s.append(join(entries, ", "));
    s.append("}");
    return s;
}

std::string Entry::print() {
    if (key) {
        return key.value() + ": " + value->print();
    }
    if(isBase) return "." + value->print();
    return value->print();
}

std::string IfLetStmt::print() {
    std::string s;
    s.append("if let ");
    s.append(type->print());
    if (!args.empty()) {
        s.append("(");
        s.append(join(args, ", "));
        s.append(")");
    }
    s.append(" = ");
    s.append(rhs->print());
    s.append(thenStmt->print());
    if (elseStmt) {
        s.append("else ").append(elseStmt->print());
    }
    return s;
}

std::string IfStmt::print() {
    std::string s;
    s.append("if(").append(expr->print()).append(")").append(thenStmt->print());
    if (elseStmt) {
        s.append("else ").append(elseStmt->print());
    }
    return s;
}

std::string ForStmt::print() {
    std::string s;
    s.append("for(");
    if (decl != nullptr) {
        s.append(decl->print());
    }
    s.append(";");
    if (cond) {
        s.append(cond->print());
    }
    s.append(";");
    if (!updaters.empty()) {
        s.append(joinPtr(updaters, ", "));
    }
    s.append(")");
    printBody(s, body.get());
    return s;
}
std::string Infix::print() {
    return left->print() + " " + op + " " + right->print();
}

std::string AsExpr::print() {
    return expr->print() + " as " + type->print();
}

std::string IsExpr::print() {
    return expr->print() + " is " + type->print();
}

std::string Assign::print() {
    return left->print() + " " + op + " " + right->print();
}

std::string Unary::print() {
    return op + expr->print();
}

std::string Postfix::print() {
    return expr->print() + op;
}

std::string FieldAccess::print() {
    if (isOptional) {
        return scope->print() + "?." + name;
    }
    return scope->print() + "." + name;
}

std::string MethodCall::print() {
    std::string s;
    if (scope) {
        s.append(scope->print());
        if (isOptional) {
            s.append("?");
        }
        if (dynamic_cast<Type *>(scope.get())) {
            s.append("::");
        } else {
            s.append(".");
        }
    }
    s.append(name);
    if (!typeArgs.empty()) s.append("<" + join(typeArgs, ", ") + ">");
    s.append("(" + join(args, ", ") + ")");
    return s;
}

std::string ArrayAccess::print() {
    std::string s = array->print();
    if (isOptional) {
        s.append("?");
    }
    s.append("[");
    s.append(index->print());
    if (index2) {
        s.append("..");
        s.append(index2->print());
    }
    s.append("]");
    return s;
}

std::string ArrayExpr::print() {
    if (isSized()) {
        return "[" + list[0]->print() + "; " + std::to_string(size.value()) + "]";
    } else {
        return "[" + join(list, ", ") + "]";
    }
}

std::string Ternary::print() {
    return cond->print() + "?" + thenExpr->print() + ":" + elseExpr->print();
}

std::string WhileStmt::print() {
    std::string s;
    s.append("while(").append(expr->print()).append(")");
    printBody(s, body.get());
    return s;
}

std::string ReturnStmt::print() {
    if (!expr) return "return";
    return "return " + expr->print() + ";";
}

std::string ContinueStmt::print() {
    if (!label.has_value()) return "continue";
    return "continue " + label.value();
}

std::string BreakStmt::print() {
    if (!label.has_value()) return "break";
    return "break " + label.value();
}

std::string DoWhile::print() {
    return "do" + body->print() + "\nwhile(" + expr->print() + ");";
}

std::string AssertStmt::print() {
    return "assert " + expr->print() + ";";
}

//accept------------------------------------

std::any AssertStmt::accept(Visitor *v) {
    return v->visitAssertStmt(this);
}
std::any BreakStmt::accept(Visitor *v) {
    return v->visitBreakStmt(this);
}
std::any ArrayExpr::accept(Visitor *v) {
    return v->visitArrayExpr(this);
}
std::any ReturnStmt::accept(Visitor *v) {
    return v->visitReturnStmt(this);
}

std::any ContinueStmt::accept(Visitor *v) {
    return v->visitContinueStmt(this);
}
std::any DoWhile::accept(Visitor *v) {
    return v->visitDoWhile(this);
}

std::any RefExpr::accept(Visitor *v) {
    return v->visitRefExpr(this);
}

std::any DerefExpr::accept(Visitor *v) {
    return v->visitDerefExpr(this);
}

std::any FieldDecl::accept(Visitor *v) {
    return v->visitFieldDecl(this);
}
std::any VarDeclExpr::accept(Visitor *v) {
    return v->visitVarDeclExpr(this);
}
std::any VarDecl::accept(Visitor *v) {
    return v->visitVarDecl(this);
}
std::any Literal::accept(Visitor *v) {
    return v->visitLiteral(this);
}
std::any SimpleName::accept(Visitor *v) {
    return v->visitSimpleName(this);
}
std::any Method::accept(Visitor *v) {
    return v->visitMethod(this);
}
std::any StructDecl::accept(Visitor *v) {
    return v->visitStructDecl(this);
}
std::any EnumDecl::accept(Visitor *v) {
    return v->visitEnumDecl(this);
}
std::any ExprStmt::accept(Visitor *v) {
    return v->visitExprStmt(this);
}

std::any Block::accept(Visitor *v) {
    return v->visitBlock(this);
}

std::any Type::accept(Visitor *v) {
    return v->visitType(this);
}
std::any ObjExpr::accept(Visitor *v) {
    return v->visitObjExpr(this);
}
std::any Param::accept(Visitor *v) {
    return v->visitParam(this);
}

std::any ParExpr::accept(Visitor *v) {
    return v->visitParExpr(this);
}
std::any Fragment::accept(Visitor *v) {
    return v->visitFragment(this);
}
std::any ForStmt::accept(Visitor *v) {
    return v->visitForStmt(this);
}
std::any IfLetStmt::accept(Visitor *v) {
    return v->visitIfLetStmt(this);
}
std::any IfStmt::accept(Visitor *v) {
    return v->visitIfStmt(this);
}

std::any Infix::accept(Visitor *v) {
    return v->visitInfix(this);
}
std::any AsExpr::accept(Visitor *v) {
    return v->visitAsExpr(this);
}
std::any IsExpr::accept(Visitor *v) {
    return v->visitIsExpr(this);
}
std::any Assign::accept(Visitor *v) {
    return v->visitAssign(this);
}
std::any ArrayAccess::accept(Visitor *v) {
    return v->visitArrayAccess(this);
}
std::any MethodCall::accept(Visitor *v) {
    return v->visitMethodCall(this);
}
std::any Unary::accept(Visitor *v) {
    return v->visitUnary(this);
}

std::any Postfix::accept(Visitor *v) {
    return v->visitPostfix(this);
}

std::any FieldAccess::accept(Visitor *v) {
    return v->visitFieldAccess(this);
}
std::any Ternary::accept(Visitor *v) {
    return v->visitTernary(this);
}

std::any WhileStmt::accept(Visitor *v) {
    return v->visitWhileStmt(this);
}

std::any Trait::accept(Visitor *v) {
    return v->visitTrait(this);
}

std::any Impl::accept(Visitor *v) {
    return v->visitImpl(this);
}
std::any Extern::accept(Visitor *v) {
    return v->visitExtern(this);
}

// std::any PointerType::accept(Visitor *v) {
//     return v->
// }
// std::any OptionType::accept(Visitor *v) {
//     throw std::runtime_error("todo");
// }