#include "Parser.h"
#include "Util.h"
#include "TypeUtils.h"

std::string Parser::strLit() {
    auto t = consume(STRING_LIT);
    return std::string(t->value.begin() + 1, t->value.end() - 1);
}

ImportStmt *Parser::parseImport() {
    auto res = new ImportStmt;
    consume(IMPORT);
    res->list.push_back(pop()->value);
    while (is(DIV)) {
        pop();
        res->list.push_back(pop()->value);
    }
    return res;
}

std::unique_ptr<FieldDecl> parseField(Parser *p) {
    auto name = p->name();
    p->consume(COLON);
    auto type = p->parseType();
    p->consume(SEMI);
    return std::make_unique<FieldDecl>(name, type);
}

// ("class") name typeArgs? "{" member* "}"
std::unique_ptr<StructDecl> Parser::parseTypeDecl() {
    auto res = std::make_unique<StructDecl>();
    res->unit = unit;
    consume(CLASS);
    res->type = parseType();
    if (!res->type->typeArgs.empty()) {
        res->isGeneric = true;
    }
    consume(LBRACE);
    //members
    while (first() != nullptr && !is(RBRACE)) {
        if (is(IDENT)) {
            res->fields.push_back(parseField(this));
        } else {
            throw std::runtime_error("invalid class member: " + first()->print());
        }
    }
    consume(RBRACE);
    return res;
}

std::unique_ptr<FieldDecl> parseEnumParam(Parser *p) {
    auto name = p->name();
    p->consume(COLON);
    auto type = p->parseType();
    return std::make_unique<FieldDecl>(name, type);
}

EnumVariant *parseEnumEntry(Parser *p) {
    auto res = new EnumVariant;
    res->name = p->name();
    if (p->is(LPAREN)) {
        p->consume(LPAREN);
        res->fields.push_back(parseEnumParam(p));
        while (p->is(COMMA)) {
            p->consume(COMMA);
            res->fields.push_back(parseEnumParam(p));
        }
        p->consume(RPAREN);
    }
    return res;
}
std::unique_ptr<EnumDecl> Parser::parseEnumDecl() {
    auto res = std::make_unique<EnumDecl>();
    res->unit = unit;
    consume(ENUM);
    res->type = parseType();
    if (!res->type->typeArgs.empty()) {
        res->isGeneric = true;
    }
    consume(LBRACE);
    if (!is(RBRACE)) {
        res->variants.push_back(parseEnumEntry(this));
        while (is(COMMA)) {
            consume(COMMA);
            res->variants.push_back(parseEnumEntry(this));
        }
    }
    consume(SEMI);
    consume(RBRACE);
    return res;
}

std::unique_ptr<Trait> parseTrait(Parser *p) {
    auto res = std::make_unique<Trait>();
    res->unit = p->unit;
    p->consume(TRAIT);
    res->type = p->parseType();
    p->consume(LBRACE);
    while (!p->is(RBRACE)) {
        res->methods.push_back(p->parseMethod());
        res->methods.back()->parent = res.get();
    }
    p->consume(RBRACE);
    return res;
}

std::unique_ptr<Impl> parseImpl(Parser *p) {
    p->consume(IMPL);
    auto type = p->parseType();
    auto res = std::make_unique<Impl>(type);
    res->unit = p->unit;
    if (!type->typeArgs.empty()) {
        res->isGeneric = true;
    }
    if (p->is(FOR)) {
        res->trait_name = type->name;
        p->consume(FOR);
        res->type = (p->parseType());
    } else {
        res->type = type;
    }
    p->consume(LBRACE);
    while (!p->is(RBRACE)) {
        auto m = p->parseMethod();
        m->parent = res.get();
        if (m->self) {
            m->self->type.reset(clone(res->type));
        }
        res->methods.push_back(std::move(m));
    }
    p->consume(RBRACE);
    return res;
}

bool Parser::isVarDecl() {
    if (is({STATIC}, {LET, CONST_KW})) return true;
    return is({LET, CONST_KW});
}

bool Parser::isMethod() {
    return is(FUNC);
}

std::shared_ptr<Unit> Parser::parseUnit() {
    auto res = std::make_shared<Unit>();
    unit = res.get();
    unit->path = lexer.path;

    while (first() != nullptr && is(IMPORT)) {
        res->imports.push_back(parseImport());
    }

    while (first() != nullptr) {
        //top level decl
        if (is({CLASS})) {
            res->items.push_back(parseTypeDecl());
        } else if (is(ENUM)) {
            res->items.push_back(parseEnumDecl());
        } else if (is(TRAIT)) {
            res->items.push_back(parseTrait(this));
        } else if (is(IMPL)) {
            res->items.push_back(parseImpl(this));
        } else if (isMethod()) {
            res->items.push_back(parseMethod());
        } else {
            throw std::runtime_error("invalid top level decl: " + first()->print());
        }
    }
    return res;
}

//name ":" type ("=" expr)?
std::unique_ptr<Param> Parser::parseParam(Method *m) {
    auto res = new Param;
    res->method = m;
    res->name = name();
    consume(COLON);
    res->type.reset(parseType());
    return std::unique_ptr<Param>(res);
}

std::unique_ptr<Method> Parser::parseMethod() {
    auto res = std::make_unique<Method>(unit);
    consume(FUNC);
    if (is(NEW)) {
        res->name = "new";
        pop();
    } else {
        res->name = name();
    }
    if (is(LT)) {
        res->typeArgs = generics();
        res->isGeneric = true;
    }
    consume(LPAREN);
    if (!is(RPAREN)) {
        if (is({IDENT}, {COLON})) {
            res->params.push_back(parseParam(res.get()));
        } else {
            auto self = new Param;
            self->name = name();
            self->method = res.get();
            res->self.reset(self);
        }
        while (is(COMMA)) {
            consume(COMMA);
            res->params.push_back(parseParam(res.get()));
        }
    }
    consume(RPAREN);
    if (is(COLON)) {
        consume(COLON);
        res->type.reset(parseType());
    } else {
        //default is void
        res->type.reset(new Type);
        res->type->name = "void";
    }
    if (is(SEMI)) {
        //interface
        consume(SEMI);
    } else {
        res->body.reset(parseBlock());
    }
    return res;
}

//name (":" type)? ("=" expr)?;
Fragment *frag(Parser *p) {
    auto res = new Fragment;
    res->name = p->name();
    if (p->is(COLON)) {
        p->consume(COLON);
        res->type.reset(p->parseType());
    }
    if (!p->is(EQ)) {
        throw std::runtime_error("variable " + res->name + " must have initializer");
    }
    p->consume(EQ);
    res->rhs.reset(p->parseExpr());
    return res;
}

//"let" varDeclFrag ("," varDeclFrag)*;
VarDecl *Parser::parseVarDecl() {
    auto res = new VarDecl;
    res->decl = parseVarDeclExpr();
    consume(SEMI);
    return res;
}

//varType varDeclFrag ("," varDeclFrag)*;
VarDeclExpr *Parser::parseVarDeclExpr() {
    auto res = new VarDeclExpr;
    if (is(STATIC)) {
        consume(STATIC);
        res->isStatic = true;
    }
    if (is(CONST_KW)) {
        consume(CONST_KW);
        res->isConst = true;
    } else {
        consume(LET);
    }
    res->list.push_back(frag(this));
    //rest if any
    while (is(COMMA)) {
        consume(COMMA);
        res->list.push_back(frag(this));
    }
    return res;
}