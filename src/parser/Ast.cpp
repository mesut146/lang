#include "parser/Ast.h"
#include "Visitor.h"
#include "parser/Util.h"

std::string RefExpr::print() {
    return "&" + expr->print();
}
std::string DerefExpr::print() {
    return "*" + expr->print();
}
std::string UnwrapExpr::print() {
    return expr->print() + "!";
}

std::string FieldDecl::print() const {
    return name + ": " + type->print();
}

std::string Unit::print() {
    std::string s;
    s.append(join(imports, "\n"));
    if (!types.empty()) {
        if (!imports.empty()) s.append("\n\n");
        s.append(joinPtr(types, "\n\n"));
    }

    s.append("\n");
    if (!methods.empty()) {
        if (!types.empty()) s.append("\n");
        s.append(joinPtr(methods, "\n\n"));
    }
    if (!stmts.empty()) {
        s.append("\n\n");
        s.append(joinPtr(stmts, "\n"));
    }
    return s;
}

std::string ImportStmt::print() {
    std::string s;
    s.append("import ");
    s.append(join(list, "/"));
    s.append(";");
    return s;
}

std::string& BaseDecl::getName(){ return type->name; }

std::string EnumDecl::print() {
    std::string s;
    s.append("enum ");
    s.append(type->print());
    s.append("{\n");
    s.append(join(variants, ",\n", "  "));
    s.append(";\n");
    //body
    if (!methods.empty()) {
        s.append("\n");
    }
    s.append(joinPtr(methods, "\n\n", "  "));
    s.append("\n}");
    return s;
}

std::string EnumVariant::print() {
    std::string s;
    s.append(name);
    if (isStruct()) {
        s.append("(");
        s.append(join(fields, ", "));
        s.append(")");
    }
    return s;
}

std::string EnumField::print() {
    return name + ": " + type->print();
}

std::string TypeDecl::print() {
    std::string s;
    s.append("class ");
    s.append(type->print());
    s.append("{\n");
    for (int i = 0; i < fields.size(); i++) {
        s.append("  ").append(fields[i]->print());
        if (i < fields.size() - 1) s.append("\n");
    }
    if (!methods.empty()) {
        if (!fields.empty()) s.append("\n");
        s.append(joinPtr(methods, "\n\n", "  "));
    }
    s.append("\n}");
    return s;
}

std::string Trait::print() {
    std::string s;
    s.append("trait ").append(type->print()).append("{\n");
    s.append(joinPtr(methods, "\n"));
    s.append("}\n");
    return s;
}

std::string Impl::print() {
    std::string s;
    s.append("impl ");
    if (trait_name) {
        s.append(trait_name.value()).append(" for ");
    }
    s.append(type->print());
    s.append("{\n");
    s.append(joinPtr(methods, "\n"));
    s.append("}\n");
    return s;
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
    if(self){
    	s.append(self->name);
        if(!params.empty()) s.append(", ");
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
    return "[" + type->print() + "; " + std::to_string(size) + "]";
}
std::string SliceType::print() {
    return "[" + type->print() + "]";
}

std::string Type::print() {
    std::string s;
    if (scope) {
        s.append(scope->print()).append(".");
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

std::string UnsafeBlock::print() {
    return "unsafe " + body->print();
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
    if (hasKey()) {
        return key + ": " + value->print();
    }
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
        s.append(".");
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

void *AssertStmt::accept(Visitor *v) {
    return v->visitAssertStmt(this);
}
void *BreakStmt::accept(Visitor *v) {
    return v->visitBreakStmt(this);
}
void *ArrayExpr::accept(Visitor *v) {
    return v->visitArrayExpr(this);
}
void *ReturnStmt::accept(Visitor *v) {
    return v->visitReturnStmt(this);
}

void *ContinueStmt::accept(Visitor *v) {
    return v->visitContinueStmt(this);
}
void *DoWhile::accept(Visitor *v) {
    return v->visitDoWhile(this);
}

void *UnsafeBlock::accept(Visitor *v) {
    return v->visitUnsafe(this);
}

void *RefExpr::accept(Visitor *v) {
    return v->visitRefExpr(this);
}

void *DerefExpr::accept(Visitor *v) {
    return v->visitDerefExpr(this);
}
void *BaseDecl::accept(Visitor *v) {
    return v->visitBaseDecl(this);
}

void *UnwrapExpr::accept(Visitor *v) {
    //return v->visitUnwrapExpr(this);
    throw std::runtime_error("UnwrapExpr::accept");
}

void *FieldDecl::accept(Visitor *v) {
    return v->visitFieldDecl(this);
}
void *VarDeclExpr::accept(Visitor *v) {
    return v->visitVarDeclExpr(this);
}
void *VarDecl::accept(Visitor *v) {
    return v->visitVarDecl(this);
}
void *Literal::accept(Visitor *v) {
    return v->visitLiteral(this);
}
void *SimpleName::accept(Visitor *v) {
    return v->visitSimpleName(this);
}
void *Method::accept(Visitor *v) {
    return v->visitMethod(this);
}
void *TypeDecl::accept(Visitor *v) {
    return v->visitTypeDecl(this);
}
void *EnumDecl::accept(Visitor *v) {
    return v->visitEnumDecl(this);
}
void *ExprStmt::accept(Visitor *v) {
    return v->visitExprStmt(this);
}

void *Block::accept(Visitor *v) {
    return v->visitBlock(this);
}

void *Type::accept(Visitor *v) {
    return v->visitType(this);
}
void *ObjExpr::accept(Visitor *v) {
    return v->visitObjExpr(this);
}
void *Param::accept(Visitor *v) {
    return v->visitParam(this);
}

void *ParExpr::accept(Visitor *v) {
    return v->visitParExpr(this);
}
void *Fragment::accept(Visitor *v) {
    return v->visitFragment(this);
}
void *ForStmt::accept(Visitor *v) {
    return v->visitForStmt(this);
}
void *IfLetStmt::accept(Visitor *v) {
    return v->visitIfLetStmt(this);
}
void *IfStmt::accept(Visitor *v) {
    return v->visitIfStmt(this);
}

void *Infix::accept(Visitor *v) {
    return v->visitInfix(this);
}
void *AsExpr::accept(Visitor *v) {
    return v->visitAsExpr(this);
}
void *IsExpr::accept(Visitor *v) {
    return v->visitIsExpr(this);
}
void *Assign::accept(Visitor *v) {
    return v->visitAssign(this);
}
void *ArrayAccess::accept(Visitor *v) {
    return v->visitArrayAccess(this);
}
void *MethodCall::accept(Visitor *v) {
    return v->visitMethodCall(this);
}
void *Unary::accept(Visitor *v) {
    return v->visitUnary(this);
}

void *Postfix::accept(Visitor *v) {
    return v->visitPostfix(this);
}

void *FieldAccess::accept(Visitor *v) {
    return v->visitFieldAccess(this);
}
void *Ternary::accept(Visitor *v) {
    return v->visitTernary(this);
}

void *WhileStmt::accept(Visitor *v) {
    return v->visitWhileStmt(this);
}

void *Trait::accept(Visitor *v) {
    return v->visitTrait(this);
}

void *Impl::accept(Visitor *v) {
    return v->visitImpl(this);
}

// void *PointerType::accept(Visitor *v) {
//     return v->
// }
// void *OptionType::accept(Visitor *v) {
//     throw std::runtime_error("todo");
// }