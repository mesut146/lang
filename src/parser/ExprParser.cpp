#pragma clang diagnostic push
#pragma ide diagnostic ignored "misc-no-recursion"
#include "Lexer.h"
#include "Parser.h"
#include "Util.h"


std::vector<Expression *> Parser::exprList() {
    std::vector<Expression *> res;
    res.push_back(parseExpr());
    while (is(COMMA)) {
        consume(COMMA);
        res.push_back(parseExpr());
    }
    return res;
}

bool isLit(Token *t) {
    return t->is({FLOAT_LIT, INTEGER_LIT, CHAR_LIT, STRING_LIT, TRUE, FALSE});
}

bool Parser::isPrim(Token &t) {
    return t.is({BOOLEAN, VOID, I8, I16, I32, I64, F32, F64, U8, U16, U32, U64});
}

Literal *parseLit(Parser *p) {
    auto &t = p->pop();
    Literal::LiteralType type;
    if (t.is(INTEGER_LIT)) {
        type = Literal::INT;
    } else if (t.is(FLOAT_LIT)) {
        type = Literal::FLOAT;
    } else if (t.is({TRUE, FALSE})) {
        type = Literal::BOOL;
    } else if (t.is(STRING_LIT)) {
        type = Literal::STR;
    } else if (t.is(CHAR_LIT)) {
        type = Literal::CHAR;
    } else {
        throw std::runtime_error("invalid literal: " + t.value);
    }
    auto res = new Literal(type, t.value);
    for (auto &s : Lexer::suffixes) {
        auto pos = t.value.rfind(s);
        bool support_suffix = type == Literal::INT || type == Literal::FLOAT || type == Literal::CHAR;
        if (pos != std::string::npos && support_suffix) {
            res->val = t.value.substr(0, t.value.size() - s.size());
            res->suffix = Type(s);
            break;
        }
    }
    return res;
}

int isTypeArg(Parser *p, int pos) {
    if (!p->tokens[pos].is(LT)) {
        return -1;
    }
    pos++;
    int open = 1;
    while (pos < p->tokens.size()) {
        if (p->tokens[pos].is(LT)) {
            pos++;
            open++;
        } else if (p->tokens[pos].is(GT)) {
            pos++;
            open--;
            if (open == 0) {
                return pos;
            }
        } else {
            auto valid_tokens = {IDENT, STAR, QUES, LBRACKET, RBRACKET, COMMA, COLON2};
            if (!p->tokens[pos].is(valid_tokens) && !p->isPrim(p->tokens[pos])) {
                return -1;
            }
            pos++;
        }
    }
    return -1;
}

Type Parser::parseType() {
    Type res;
    if (isPrim(*first())) {
        res = Type(pop().value);
    } else if (is(LBRACKET)) {
        consume(LBRACKET);
        auto type = parseType();
        if (is(SEMI)) {
            consume(SEMI);
            if (!is(INTEGER_LIT)) {
                throw std::runtime_error("invalid array size: " + this->first()->value);
            }
            auto size = std::stoi(pop().value);
            res = Type(type, size);
        } else {
            res = Type(Type::Slice, type);
        }
        consume(RBRACKET);
    } else {
        res = Type(name());
        while (is({COLON2, LT})) {
            if (is(LT)) {
                res.typeArgs = generics();
            } else {
                consume(COLON2);
                res = Type(res, name());
            }
        }
    }

    while (is(STAR) || is(QUES)) {
        if (is(STAR)) {
            consume(STAR);
            res = Type(Type::Pointer, res);
        } else if (is(QUES)) {
            consume(QUES);
            res = Type(Type::Option, res);
        }
    }
    return res;
}

std::vector<Type> Parser::generics() {
    std::vector<Type> list;
    consume(LT);
    list.push_back(parseType());
    while (is(COMMA)) {
        consume(COMMA);
        list.push_back(parseType());
    }
    consume(GT);
    return list;
}

Entry parseEntry(Parser *p) {
    Entry e{};
    if (p->isName() && p->peek(1)->is({COLON})) {
        e.key = p->name();
        p->consume(COLON);
        e.value = p->parseExpr();
    } else {
        //single expr or base
        if (p->is(DOT)) {
            p->pop();
            e.isBase = true;
        }
        e.value = p->parseExpr();
    }
    return e;
}

bool isObj(Parser *p) {
    if (!p->is(IDENT)) {
        return false;
    }
    int pos = p->pos + 1;
    int ta = isTypeArg(p, pos);
    if (ta != -1) {
        pos = ta;
    }
    if (p->tokens[pos].is(COLON2)) {
        pos++;
        if (!p->tokens[pos].is(IDENT)) {
            return false;
        }
        pos++;
    }

    if (p->tokens[pos].is(LBRACE)) {
        return true;
    }
    return false;
}

Expression *makeObj(Parser *p, bool isPointer, const Type &type) {
    auto res = new ObjExpr;
    res->isPointer = isPointer;
    res->type = type;
    p->consume(LBRACE);
    if (!p->is(RBRACE)) {
        res->entries.push_back(parseEntry(p));
        while (p->is(COMMA)) {
            p->consume(COMMA);
            res->entries.push_back(parseEntry(p));
        }
    }
    p->consume(RBRACE);
    return res;
}

Expression *makeObj(Parser *p, bool isPointer) {
    return makeObj(p, isPointer, p->parseType());
}

Expression *makeAlloc(Parser *p) {
    p->consume(NEW);
    auto type = p->parseType();
    return makeObj(p, true, type);
}

MethodCall *parseCall(Parser *p, const std::string &name) {
    auto res = Expression::make<MethodCall>();
    res->name = name;
    if (p->is(LT)) {
        res->typeArgs = p->generics();
    }
    p->consume(LPAREN);
    if (!p->is(RPAREN)) {
        res->args = p->exprList();
    }
    p->consume(RPAREN);
    return res;
}

template<class T>
T loc(T t, int line) {
    t->line = line;
    return t;
}

_GLIBCXX_NORETURN
void err(Parser *p, const std::string &msg) {
    std::cout << p->unit->path << ":" << p->first()->line << std::endl;
    throw std::runtime_error(msg);
}

//"(" expr ")" | literal | objCreation | arrayCreation | name | mc
Expression *PRIM(Parser *p) {
    int line = p->first()->line;
    if (p->is(LPAREN)) {
        //ParExpr
        auto res = new ParExpr;
        p->consume(LPAREN);
        res->expr = p->parseExpr();
        p->consume(RPAREN);
        return loc(res, line);
    } else if (isLit(p->first())) {
        return loc(parseLit(p), line);
    } else if (p->is(NEW)) {
        return loc(makeAlloc(p), line);
    }
    if (isObj(p)) {
        return loc(makeObj(p, false), line);
    } else if (p->isPrim(*p->first())) {
        auto type = new Type(p->pop().value);
        p->consume(COLON2);
        auto name = p->name();
        if (p->is(LPAREN) || p->is(LT)) {
            std::vector<Type> typeArgs;
            if (p->is(LT)) {
                typeArgs = p->generics();
            }
            auto mc = parseCall(p, name);
            mc->is_static = true;
            mc->scope.reset(type);
            mc->typeArgs = typeArgs;
            return loc(mc, line);
        }
        return new Type(*type, name);
    } else if (p->is({IDENT, IS, AS, TYPE})) {
        auto id = p->pop().value;
        if (p->is(LPAREN)) {
            auto res = parseCall(p, id);
            res->line = line;
            return res;
        } else if (isTypeArg(p, p->pos) != -1) {
            auto typeArgs = p->generics();
            //todo move isObj here
            if (p->is(LPAREN)) {//id<...>(args)
                auto res = parseCall(p, id);
                res->line = line;
                res->typeArgs = typeArgs;
                return res;
            } else {
                p->consume(COLON2);//id<...>::
                auto scope = new Type(id);
                scope->typeArgs = typeArgs;
                auto name = p->name();
                if (p->is(LPAREN)) {
                    auto res = parseCall(p, name);
                    res->is_static = true;
                    res->line = line;
                    res->scope.reset(scope);
                    return res;
                } else {
                    //id<...>::name
                    return new Type(*scope, name);
                }
            }
        } else if (p->is(COLON2)) {
            p->consume(COLON2);
            auto t = p->parseType();
            if (p->is(LPAREN)) {//id::name<...>(args)
                auto res = parseCall(p, t.name);
                res->line = line;
                res->is_static = true;
                if (!t.typeArgs.empty()) {
                    res->typeArgs = t.typeArgs;
                }
                res->scope.reset(new Type(id));
                return res;
            } else {
                //id::t
                //static field access, or enum variant
                return new Type(Type(id), t.name);
            }
        } else {
            return loc(new SimpleName(id), line);
        }
    } else if (p->is(LBRACKET)) {
        p->consume(LBRACKET);
        auto res = new ArrayExpr;
        res->list = p->exprList();
        if (p->is(SEMI)) {
            p->consume(SEMI);
            auto size = p->consume(INTEGER_LIT).value;
            res->size = std::stoi(size);
            if (res->list.size() != 1) {
                throw std::runtime_error("sized array expects 1 element but got " + std::to_string(res->list.size()) + " line: " + std::to_string(p->first()->line));
            }
        }
        p->consume(RBRACKET);
        return loc(res, line);
    } else {
        err(p, "invalid primary " + p->first()->value);
    }
}

//PRIM ('.' name ('(' args? ')')? | [ E ])*
Expression *PRIM2(Parser *p) {
    int line = p->first()->line;
    Expression *lhs = PRIM(p);
    while (p->is({DOT, LBRACKET}) || p->is({QUES}, {DOT, LBRACKET})) {
        bool isOptional = false;
        if (p->is({QUES}, {DOT, LBRACKET})) {
            p->consume(QUES);
            isOptional = true;
        }
        if (p->is(DOT)) {
            p->consume(DOT);
            int line = p->first()->line;
            auto name = p->name();
            if (p->is(LPAREN) || isTypeArg(p, p->pos) != -1) {
                auto res = Expression::make<MethodCall>();
                res->line = line;
                res->is_static = false;
                res->scope.reset(lhs);
                res->name = name;
                if (p->is(LT)) {
                    res->typeArgs = p->generics();
                }
                p->consume(LPAREN);
                if (!p->is(RPAREN)) {
                    res->args = p->exprList();
                }
                p->consume(RPAREN);
                lhs = res;
            } else {
                auto res = new FieldAccess;
                res->isOptional = isOptional;
                res->scope = lhs;
                res->name = name;
                res->line = lhs->line;
                lhs = res;
            }
        } else {
            auto res = new ArrayAccess;
            res->isOptional = isOptional;
            res->array = lhs;
            p->consume(LBRACKET);
            res->index = p->parseExpr();
            if (p->is(DOTDOT)) {
                p->consume(DOTDOT);
                res->index2.reset(p->parseExpr());
            }
            p->consume(RBRACKET);
            lhs = loc(res, line);
        }
    }
    return lhs;
}
Expression *parseLhs(Parser *p);

RefExpr *parseRef(Parser *p) {
    int line = p->first()->line;
    p->consume(AND);
    auto expr = parseLhs(p);
    if (dynamic_cast<SimpleName *>(expr) || dynamic_cast<FieldAccess *>(expr) || dynamic_cast<ArrayAccess *>(expr) || dynamic_cast<MethodCall *>(expr) || dynamic_cast<ObjExpr *>(expr)) {
        return loc(new RefExpr(std::unique_ptr<Expression>(expr)), line);
    }
    throw std::runtime_error("cannot take reference of " + expr->print());
}

DerefExpr *parseDeref(Parser *p) {
    int line = p->first()->line;
    p->consume(STAR);
    auto expr = parseLhs(p);
    return loc(new DerefExpr(std::unique_ptr<Expression>(expr)), line);
}

Expression *parseLhs(Parser *p) {
    if (p->is(AND)) {
        return parseRef(p);
    } else if (p->is(STAR)) {
        return parseDeref(p);
    }
    return PRIM2(p);
}

//expr ("as" type)?
Expression *asExpr(Parser *p) {
    int line = p->first()->line;
    auto lhs = parseLhs(p);
    if (p->is(AS)) {
        auto res = loc(new AsExpr, line);
        res->expr = lhs;
        p->consume(AS);
        res->type = p->parseType();
        lhs = res;
    }
    return lhs;
}

//("+" | "-" | "++" | "--" | "!" | "~") expr #unary
Expression *expr12(Parser *p) {
    int line = p->first()->line;
    if (p->is({PLUS, MINUS, PLUSPLUS, MINUSMINUS, BANG, TILDE})) {
        auto res = loc(new Unary, line);
        res->op = p->pop().value;
        res->expr = expr12(p);
        return res;
    } else {
        return asExpr(p);
    }
}

//expr12 ("*" | "/" | "%" expr12)*
Expression *expr11(Parser *p) {
    int line = p->first()->line;
    auto lhs = expr12(p);
    while (p->is({STAR, DIV, PERCENT})) {
        auto res = loc(new Infix, line);
        res->left = lhs;
        res->op = p->pop().value;
        res->right = expr12(p);
        lhs = res;
    }
    return lhs;
}

//expr11 ("+" | "-" expr11)*
Expression *expr10(Parser *p) {
    auto lhs = expr11(p);
    while (p->is({PLUS, MINUS})) {
        auto res = loc(new Infix, lhs->line);
        res->left = lhs;
        res->op = p->pop().value;
        res->right = expr11(p);
        lhs = res;
    }
    return lhs;
}

//expr10 ("<<" | ">" ">" | ">" ">" ">" expr10)*
Expression *expr9(Parser *p) {
    auto lhs = expr10(p);
    while (p->is({LTLT, GT})) {
        auto &op = p->pop().value;
        if (op == ">" && p->is(GT)) {
            op = ">>";
            p->consume(GT);
            if (p->is(GT)) {
                op = ">>>";
                p->consume(GT);
            }
        }
        auto res = loc(new Infix, lhs->line);
        res->left = lhs;
        res->op = op;
        res->right = expr10(p);
        lhs = res;
    }
    return lhs;
}

Expression *parseIsExpr(Parser *p) {
    auto lhs = expr9(p);
    if (p->is(IS)) {
        p->consume(IS);
        auto res = loc(new IsExpr, lhs->line);
        res->expr = lhs;
        res->rhs = expr9(p);
        return res;
    }
    return lhs;
}

//expr9 ("<" | ">" | "<=" | ">=" expr9)*
Expression *expr8(Parser *p) {
    auto lhs = parseIsExpr(p);
    while (p->is({LT, GT, LTEQ, GTEQ})) {
        auto res = loc(new Infix, lhs->line);
        res->left = lhs;
        res->op = p->pop().value;
        res->right = expr9(p);
        lhs = res;
    }
    return lhs;
}

//expr8 ("==" | "!=" expr8)*
Expression *expr7(Parser *p) {
    int line = p->first()->line;
    auto lhs = expr8(p);
    while (p->is({EQEQ, NOTEQ})) {
        auto res = new Infix;
        res->left = lhs;
        res->op = p->pop().value;
        res->right = expr8(p);
        res->line = line;
        lhs = res;
    }
    return lhs;
}

//expr7 ("&" expr7)*
Expression *expr6(Parser *p) {
    int line = p->first()->line;
    auto lhs = expr7(p);
    while (p->is(AND)) {
        auto res = new Infix;
        res->line = line;
        res->left = lhs;
        res->op = p->pop().value;
        res->right = expr7(p);
        lhs = res;
    }
    return lhs;
}

//expr6 ("^" expr6)*
Expression *expr5(Parser *p) {
    int line = p->first()->line;
    auto lhs = expr6(p);
    while (p->is(POW)) {
        auto res = new Infix;
        res->left = lhs;
        res->op = p->pop().value;
        res->right = expr6(p);
        lhs = res;
    }
    return lhs;
}

//expr5 ("|" expr5)*
Expression *expr4(Parser *p) {
    auto lhs = expr5(p);
    while (p->is(OR)) {
        auto res = new Infix;
        res->left = lhs;
        res->op = p->pop().value;
        res->right = expr5(p);
        lhs = res;
    }
    return lhs;
}

//expr4 ("&&" expr4)*
Expression *expr3(Parser *p) {
    auto lhs = expr4(p);
    while (p->is(ANDAND)) {
        auto res = loc(new Infix, lhs->line);
        res->left = lhs;
        res->op = p->pop().value;
        res->right = expr4(p);
        lhs = res;
    }
    return lhs;
}

//expr3 ("||" expr)*
Expression *expr2(Parser *p) {
    auto lhs = expr3(p);
    while (p->is(OROR)) {
        auto res = loc(new Infix, lhs->line);
        res->left = lhs;
        res->op = p->pop().value;
        res->right = expr3(p);
        lhs = res;
    }
    return lhs;
}


bool isAssign(std::string &s) {
    return s == "=" || s == "+=" || s == "-=" || s == "*=" || s == "/=" || s == "%=" || s == "&=" || s == "^=" || s == "|=" || s == "<<=" || s == ">>=" || s == ">>>=";
}

//expr1 (assignOp expr)?
Expression *Parser::parseExpr() {
    auto res = expr2(this);
    if (first() && isAssign(first()->value)) {
        auto assign = new Assign;
        assign->line = first()->line;
        assign->left = res;
        assign->op = pop().value;
        assign->right = parseExpr();
        res = assign;
    }
    return res;
}


#pragma clang diagnostic pop