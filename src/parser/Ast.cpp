#include "parser/Ast.h"
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
        s.append(join(types, "\n\n"));
    }

    s.append("\n");
    if (!methods.empty()) {
        if (!types.empty()) s.append("\n");
        s.append(join(methods, "\n\n"));
    }
    if (!stmts.empty()) {
        s.append("\n\n");
        s.append(join(stmts, "\n"));
    }
    return s;
}

std::string ImportAlias::print() {
    if (as) {
        return name + " as " + *as;
    } else {
        return name;
    }
}

std::string ImportStmt::print() {
    std::string s;
    s.append("import ");
    if (normal) {
        s.append(normal->path->print());
        if (normal->as) {
            s.append("as ").append(*normal->as);
        }
    } else {
        s.append(sym->path->print());
        s.append(".{");
        s.append(join(sym->entries, ", "));
        s.append("}");
    }
    return s;
}


std::string EnumDecl::print() {
    std::string s;
    s.append("enum ");
    s.append(name);
    if (!typeArgs.empty()) {
        s.append("<").append(join(typeArgs, ", ")).append(">");
    }
    s.append("{\n");
    s.append(join(cons, ",\n", "  "));
    s.append(";\n");
    //body
    if (!methods.empty()) {
        s.append("\n");
    }
    s.append(join(methods, "\n\n", "  "));
    s.append("\n}");
    return s;
}

std::string EnumEntry::print() {
    std::string s;
    s.append(name);
    if (isStruct()) {
        s.append("(");
        s.append(join(params, ", "));
        s.append(")");
    }
    return s;
}

std::string EnumParam::print() {
    return name + ": " + type->print();
}

std::string TypeDecl::print() {
    std::string s;
    s.append(isInterface ? "interface " : "class ");
    s.append(name);
    if (!typeArgs.empty()) {
        s.append("<").append(join(typeArgs, ", ")).append(">");
    }
    if (!baseTypes.empty()) {
        s.append(" : ").append(join(baseTypes, ", "));
    }
    s.append("{\n");
    for (int i = 0; i < fields.size(); i++) {
        s.append("  ").append(fields[i]->print());
        if (i < fields.size() - 1) s.append("\n");
    }
    if (!methods.empty()) {
        if (!fields.empty()) s.append("\n");
        s.append(join(methods, "\n\n", "  "));
    }
    if (!types.empty()) {
        if (!methods.empty()) s.append("\n");
        s.append(join(types, "\n\n", "  "));
    }
    s.append("\n}");
    return s;
}

std::string Method::print() {
    std::string s;
    if (isStatic) s.append("static ");
    s.append("func ");
    s.append(name);
    if (!typeArgs.empty()) {
        s.append("<");
        s.append(join(typeArgs, ","));
        s.append(">");
    }
    s.append("(");
    s.append(join(params, ", "));
    s.append(")");
    if (type) {
        s.append(": ");
        s.append(type->print());
    }
    if (body == nullptr) {
        s.append(";");
    } else {
        s.append(body->print());
    }
    return s;
}

std::string SimpleName::print() {
    return name;
}

std::string QName::print() {
    return scope->print() + "." + name;
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
    if (type != nullptr) {
        s.append(" : ").append(type->print());
    }
    if (rhs != nullptr) {
        s.append(" = ").append(rhs->print());
    }
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
    s.append(printDims(dims));
    return s;
}

std::string Param::print() {
    std::string s;
    s.append(name);
    s.append(": ");
    s.append(type->print());

    if (defVal != nullptr) {
        s.append(" = ");
        s.append(defVal->print());
    }
    return s;
}

std::string ParExpr::print() {
    return std::string("(" + expr->print() + ")");
}

std::string ObjExpr::print() {
    std::string s;
    if(isPointer){
        s.append("new ");
    }
    s.append(type->print());
    s.append("{");
    s.append(join(entries, ", "));
    s.append("}");
    return s;
}

std::string MapExpr::print() {
    std::string s;
    s.append("{");
    s.append(join(entries, ", "));
    s.append("}");
    return s;
}

std::string MapEntry::print() {
    return key->print() + ": " + value->print();
}

std::string Entry::print() {
    return key + ": " + value->print();
}

std::string IfLetStmt::print() {
    std::string s;
    s.append("if let ");
    s.append(type->print());
    if(!args.empty()){
        s.append("(");
        s.append(join(args, ", "));
        s.append(")");
    }
    s.append(" = ");
    s.append(rhs->print());
    s.append(thenStmt->print());
    if (elseStmt != nullptr) {
        s.append("else ").append(elseStmt->print());
    }
    return s;
}

std::string IfStmt::print() {
    std::string s;
    s.append("if(").append(expr->print()).append(")").append(thenStmt->print());
    if (elseStmt != nullptr) {
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
    if (cond != nullptr) {
        s.append(cond->print());
    }
    s.append(";");
    if (!updaters.empty()) {
        s.append(join(updaters, ", "));
    }
    s.append(")");
    printBody(s, body);
    return s;
}

std::string ForEach::print() {
    std::string s;
    s.append("for(");
    s.append(decl->print());
    s.append(" : ");
    s.append(expr->print());
    s.append(")\n");
    s.append(body->print());
    return s;
}
std::string Infix::print() {
    return left->print() + " " + op + " " + right->print();
}

std::string AsExpr::print() {
    return expr->print() + " as " + type->print();
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
    if (isOptional) {
        return array->print() + "?[" + index->print() + "]";
    }
    return array->print() + "[" + index->print() + "]";
}

std::string ArrayExpr::print() {
    return "[" + join(list, ", ") + "]";
}

std::string ArrayCreation::print() {
    std::string s;
    if(isPointer) s.append("new ");
    s.append(type->print() + printDims(dims));
    return s;
}


std::string Ternary::print() {
    return cond->print() + "?" + thenExpr->print() + ":" + elseExpr->print();
}

std::string WhileStmt::print() {
    std::string s;
    s.append("while(").append(expr->print()).append(")");
    printBody(s, body);
    return s;
}

std::string ReturnStmt::print() {
    if (expr == nullptr) return "return";
    return "return " + expr->print() + ";";
}

std::string ContinueStmt::print() {
    if (label == nullptr) return "continue";
    return "continue " + *label;
}

std::string BreakStmt::print() {
    if (label == nullptr) return "break";
    return "break " + *label;
}


std::string DoWhile::print() {
    return "do" + body->print() + "\nwhile(" + expr->print() + ");";
}

//accept------------------------------------
void *BreakStmt::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitBreakStmt(this, arg);
}
void *ArrayExpr::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitArrayExpr(this, arg);
}
void *ReturnStmt::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitReturnStmt(this, arg);
}

void *ContinueStmt::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitContinueStmt(this, arg);
}
void *DoWhile::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitDoWhile(this, arg);
}

void *RefExpr::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitRefExpr(this, arg);
}

void *DerefExpr::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitDerefExpr(this, arg);
}
void *BaseDecl::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitBaseDecl(this, arg);
}

void *UnwrapExpr::accept(Visitor<void *, void *> *v, void *arg) {
    //return v->visitUnwrapExpr(this, arg);
    throw std::runtime_error("UnwrapExpr::accept");
}

void *FieldDecl::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitFieldDecl(this, arg);
}
void *VarDeclExpr::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitVarDeclExpr(this, arg);
}
void *VarDecl::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitVarDecl(this, arg);
}
void *Literal::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitLiteral(this, arg);
}
void *QName::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitQName(this, arg);
}
void *SimpleName::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitSimpleName(this, arg);
}
void *Method::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitMethod(this, arg);
}
void *TypeDecl::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitTypeDecl(this, arg);
}
void *EnumDecl::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitEnumDecl(this, arg);
}
void *ExprStmt::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitExprStmt(this, arg);
}

void *Block::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitBlock(this, arg);
}

void *Type::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitType(this, arg);
}
void *MapExpr::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitAnonyObjExpr(this, arg);
}
void *ObjExpr::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitObjExpr(this, arg);
}
void *Param::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitParam(this, arg);
}

void *ParExpr::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitParExpr(this, arg);
}
void *Fragment::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitFragment(this, arg);
}
void *ForStmt::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitForStmt(this, arg);
}
void *IfLetStmt::accept(Visitor<void *, void *> *v, void *arg) {
    //return v->visitIfLetStmt(this, arg);
    return nullptr;
}
void *IfStmt::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitIfStmt(this, arg);
}
void *ForEach::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitForEach(this, arg);
}

void *Infix::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitInfix(this, arg);
}
void *AsExpr::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitAsExpr(this, arg);
}

void *Assign::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitAssign(this, arg);
}
void *ArrayCreation::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitArrayCreation(this, arg);
}
void *ArrayAccess::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitArrayAccess(this, arg);
}
void *MethodCall::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitMethodCall(this, arg);
}
void *Unary::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitUnary(this, arg);
}

void *Postfix::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitPostfix(this, arg);
}

void *FieldAccess::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitFieldAccess(this, arg);
}
void *Ternary::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitTernary(this, arg);
}

void *WhileStmt::accept(Visitor<void *, void *> *v, void *arg) {
    return v->visitWhileStmt(this, arg);
}

void *PointerType::accept(Visitor<void *, void *> *v, void *arg) {
    throw std::runtime_error("todo");
}
void *OptionType::accept(Visitor<void *, void *> *v, void *arg) {
    throw std::runtime_error("todo");
}