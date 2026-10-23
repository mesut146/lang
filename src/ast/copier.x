import std/libc
import std/hashmap

import ast/ast
import ast/printer
import ast/token

struct AstCopier{
    type_map: HashMap<String, Type>*;
    unit: Option<Unit*>;
    //macro expansion: bare names listed here are replaced by a copy of the
    //bound argument expression (`Expr` parameters). Empty otherwise.
    expr_map: HashMap<String, Expr*>;
    //macro expansion: value parameters are bound under a fresh name (x has no
    //shadowing, so the parameter name itself would collide with any live
    //variable at the call site); references to them in the body are renamed.
    rename_map: HashMap<String, String>;
    //while copying a substituted argument: its names belong to the caller, so
    //they must not be substituted/renamed again (params are often named like
    //the arguments)
    in_arg: bool;
    //macro expansion (hygienic: true): names the *body* declares -- let/for
    //variables, for-each and lambda parameters, match/if-let bindings -- are
    //alpha-renamed per call site, so a body local can neither collide with nor
    //capture a name at the call site. The map grows as declarations are copied:
    //x has no shadowing, so anything copied before a declaration is a name from
    //the call site and is left alone. Entries are never restored when a nested
    //scope ends (the name keeps the last fresh spelling).
    local_renames: HashMap<String, String>;
    hygienic: bool;
    //suffix for fresh names: the macro call's node id, unique per call, plus a
    //per-declaration counter so one body may declare the same spelling twice
    rename_id: i32;
    rename_seq: i32;
    //macro expansion: bare names that are neither body-declared nor a
    //parameter. The resolver checks them against the call site: such a name
    //would otherwise capture a caller local (definition-site guard in
    //expand_user_macro).
    free_names: List<String>;
    //macro expansion, `$( ... )*`: the list parameter's name (`xs` in
    //`macro m(xs: Expr...)`) and the argument expression for each element.
    //While expanding, `$xs` looks up `$xs` in expr_map; the bare spelling is
    //an error.
    repeat_param: Option<String>;
    repeat_elems: List<Expr*>;
    in_repeat: bool;
    //problems found while copying that need the resolver's diagnostics (the
    //copier has no unit): bad `$name`, nested repetitions, ...
    errors: List<String>;
    //last_id: i32*;
}

impl AstCopier{
    func new(type_map: HashMap<String, Type>*, unit: Unit*): AstCopier{
        return AstCopier{type_map: type_map, unit: Option::new(unit), expr_map: HashMap<String, Expr*>::new(), rename_map: HashMap<String, String>::new(), in_arg: false, local_renames: HashMap<String, String>::new(), hygienic: false, rename_id: 0, rename_seq: 0, free_names: List<String>::new(), repeat_param: Option<String>::new(), repeat_elems: List<Expr*>::new(), in_repeat: false, errors: List<String>::new()};
    }
    func new(type_map: HashMap<String, Type>*): AstCopier{
        return AstCopier{type_map: type_map, unit: Option<Unit*>::new(), expr_map: HashMap<String, Expr*>::new(), rename_map: HashMap<String, String>::new(), in_arg: false, local_renames: HashMap<String, String>::new(), hygienic: false, rename_id: 0, rename_seq: 0, free_names: List<String>::new(), repeat_param: Option<String>::new(), repeat_elems: List<Expr*>::new(), in_repeat: false, errors: List<String>::new()};
    }
    //macro expansion: same as new(), but `expr_map` names are substituted with
    //their argument and `rename_map` names are renamed.
    func new(type_map: HashMap<String, Type>*, unit: Unit*, expr_map: HashMap<String, Expr*>, rename_map: HashMap<String, String>): AstCopier{
        return AstCopier{type_map: type_map, unit: Option::new(unit), expr_map: expr_map, rename_map: rename_map, in_arg: false, local_renames: HashMap<String, String>::new(), hygienic: false, rename_id: 0, rename_seq: 0, free_names: List<String>::new(), repeat_param: Option<String>::new(), repeat_elems: List<Expr*>::new(), in_repeat: false, errors: List<String>::new()};
    }

    //hygienic rename of one name a macro body declares: the fresh spelling is
    //returned and recorded, so references copied from here on follow it
    func hygienic_name(self, name: String*): String{
        let fresh = format!("{}_{}_{}", name, self.rename_id, self.rename_seq);
        self.rename_seq += 1;
        self.local_renames.add(name.clone(), fresh.clone());
        return fresh;
    }

    func clone<T>(node: T*, unit: Unit*): T{
        let type_map = HashMap<String, Type>::new();
        let copier = AstCopier::new(&type_map, unit);
        let res = copier.visit(node);
        return res;
    }
    func clone<T>(node: T*): T{
        let type_map = HashMap<String, Type>::new();
        let copier = AstCopier::new(&type_map);
        let res = copier.visit(node);
        return res;
    }

    func visit_list<E>(self, list: List<E>*): List<E>{
        let res = List<E>::new();
        for(let i = 0;i < list.size();++i){
            let arg = list.get(i);
            res.add(self.visit(arg));
        }
        return res;
    }

    func visit_list<E>(self, list1: List<E>*, list2: List<E>*){
        for(let i = 0;i < list1.size();++i){
            let arg = list1.get(i);
            list2.add(self.visit(arg));
        }
    }

    func visit_opt<E>(self, opt: Option<E>*): Option<E>{
        if(opt.is_some()){
            return Option<E>::new(self.visit(opt.get()));
        }
        return Option<E>::new();
    }

    func visit_box<E>(self, box: Box<E>*): Box<E>{
        return Box::new(self.visit(box.get()));
    }

    func visit_ptr<E>(self, opt: Ptr<E>*): Ptr<E>{
        if(opt.is_some()){
            return Ptr<E>::new(self.visit(opt.get()));
        }
        return Ptr<E>::new();
    }
    
    func visit<E>(self, box: Box<E>*): Box<E>{
        return Box::new(self.visit(box.get()));
    }

    func visit(self, s: String*): String{
        return s.clone();
    }

    func visit(self, val: i32*): i32{
        return *val;
    }

    func node(self, old: Node*): Node{
        let unit = self.unit.unwrap();
        let id = ++unit.last_id;
        return Node::new(id, old.line);
    }

    func visit(self, node: Attributes*): Attributes{
      return Attributes{list: self.visit_list(&node.list)};
    }    

    func visit(self, node: Attribute*): Attribute{
        return Attribute{
            name: node.name.clone(),
            args: self.visit_list(&node.args), 
            is_call: node.is_call
        };
    }

    func visit(self, node: Decl*): Decl{
        let type = self.visit(&node.type);
        let base = BaseDecl{
            line: node.line,
            path: node.path.clone(),
            type: type,
            name: node.name.clone(),
            is_generic: false,
            base: self.visit_opt(&node.base), 
            attr: self.visit(&node.attr),
            parent: node.parent.clone(),
        };
        match node{
            Decl::Struct(fields)=>{
                let res = self.visit_list(fields);
                return Decl::Struct{.base, res};
            },
            Decl::TupleStruct(fields)=>{
                let res = self.visit_list(fields);
                return Decl::TupleStruct{.base, res};
            },
            Decl::Enum(variants)=>{
                let res = self.visit_list(variants);
                return Decl::Enum{.base, res};
            }
        }
    }

    func visit(self, node: FieldDecl*): FieldDecl{
        return FieldDecl{name: node.name.clone(), type: self.visit(&node.type)};
    }

    func visit(self, node: Variant*): Variant{
        return Variant{
          name: node.name.clone(),
          fields: self.visit_list(&node.fields),
          is_tuple: node.is_tuple, 
          disc: self.visit_opt(&node.disc),
          line: node.line
        };
    }

    func visit(self, type: Type*): Type{
        let id = Node::new(-1, type.line);
        match type{
            Type::Pointer(bx) => {
                let scope = self.visit(bx.get());
                let res = Type::Pointer{.id, Box::new(scope)};
                return res;
            },
            Type::Array(bx, size) => {
                let scope = self.visit(bx.get());
                let res = Type::Array{.id, Box::new(scope), *size};
                return res;
            },
            Type::Slice(bx) => {
                let scope = self.visit(bx.get());
                let res = Type::Slice{.id, Box::new(scope)};
                return res;
            },
            Type::Function(bx) => {
                let ft = FunctionType{
                    return_type: self.visit(&bx.get().return_type),
                    params: self.visit_list(&bx.get().params)
                };
                return Type::Function{.id, type: Box::new(ft)};
            },
            Type::Lambda(bx) => {
                let lt = LambdaType{
                    return_type: self.visit_opt(&bx.get().return_type),
                    params: self.visit_list(&bx.get().params),
                    captured: self.visit_list(&bx.get().captured),
                };
                return Type::Lambda{.id, Box::new(lt)};
            },
            Type::Simple(smp) => {
                let hit = self.type_map.get_str(smp.name);
                if(hit.is_some()){
                    return hit.unwrap().clone();
                }
                let res = Simple::new(smp.name);
                if (smp.scope.is_some()) {
                    res.scope = Ptr::new(self.visit(smp.scope.get()));
                }
                for (let i = 0; i < smp.args.size(); ++i) {
                    let ta = smp.args.get(i);
                    res.args.add(self.visit(ta));
                }
                return res.into(type.line);
            },
            Type::Tuple(tt) => {
                return Type::Tuple{.id, TupleType{types: self.visit_list(&tt.types)}};
            }
        }
    }
    
    /*func visit(self, node: CapturedInfo*): CapturedInfo{
        return CapturedInfo{self.visit(&node.type), node.name.clone()};
    }*/

    func visit(self, p: Param*): Param{
        let id = self.node(p as Node*);
        return Param{.id, 
            name: p.name.clone(),
            type: self.visit(&p.type),
            is_self: p.is_self,
            is_deref: p.is_deref,
            is_captured: p.is_captured};
    }

    func visit(self, p: Parent*): Parent{
        match p{
            Parent::Impl(info) => {
                return Parent::Impl{
                    ImplInfo{
                      type_params: self.visit_list(&info.type_params),
                      trait_name: self.visit_opt(&info.trait_name),
                      type: self.visit(&info.type),
                      parent: info.parent.clone(),
                  }
                };
            },
            Parent::Trait(ty) => return Parent::Trait{self.visit(ty)},
            Parent::None => return Parent::None,
            Parent::Extern => return Parent::Extern,
            Parent::Module(name) => return Parent::Module{name.clone()},
        }
    }

    func visit(self, m: Method*): Method{
        let type_params = List<Type>::new();
        for(let i = 0;i < m.type_params.size();++i){
            let ta = m.type_params.get(i);
            type_params.add(self.visit(ta));
        }
        let selff = Option<Param>::new();
        if(m.self.is_some()){
            selff = Option::new(self.visit(m.self.get()));
        }
        let params = self.visit_list(&m.params);
        let id = self.node(m as Node*);
        return Method{.id,
            type_params: type_params,
            name: m.name.clone(),
            self: selff,
            params: params,
            type: self.visit(&m.type),
            body: self.visit_opt(&m.body),
            is_generic: m.is_generic,
            parent: self.visit(&m.parent),
            path: m.path.clone(),
            is_vararg: m.is_vararg,
            attr: self.visit(&m.attr),
        };
    }

    func visit(self, node: Block*): Block{
        let res = Block::new(node.line, node.end_line);
        self.visit_stmts(&node.list, &res.list);
        res.return_expr = self.visit_opt(&node.return_expr);
        return res;
    }
    //statements, splicing `$( ... )*` into one copy of its body per element
    func visit_stmts(self, src: List<Stmt>*, dst: List<Stmt>*){
        for(let i = 0;i < src.size();++i){
            let st = src.get(i);
            if let Stmt::Repeat(r) = st{
                self.expand_repeat(r, dst);
            }else{
                dst.add(self.visit(st));
            }
        }
    }
    //expression lists (arguments, array/tuple elements), splicing
    //`$( <exprs> )<sep>*` into one copy of its elements per list element
    func visit_expr_list(self, src: List<Expr>*): List<Expr>{
        let res = List<Expr>::new();
        self.visit_exprs(src, &res);
        return res;
    }
    func visit_exprs(self, src: List<Expr>*, dst: List<Expr>*){
        for(let i = 0;i < src.size();++i){
            let e = src.get(i);
            if let Expr::Repeat(r) = e{
                self.expand_repeat_expr(r, dst);
            }else{
                dst.add(self.visit(e));
            }
        }
    }
    func expand_repeat_expr(self, r: RepeatExpr*, dst: List<Expr>*){
        if(self.repeat_param.is_none()){
            self.errors.add("$( ... )* is only valid inside a macro with a list parameter".str());
            return;
        }
        if(self.in_repeat){
            self.errors.add("nested $( ... )* is not supported".str());
            return;
        }
        self.in_repeat = true;
        let key = format!("${}", self.repeat_param.get());
        for(let i = 0;i < self.repeat_elems.size();++i){
            let elem = self.repeat_elems.get(i);
            self.expr_map.add(key.clone(), *elem);
            self.visit_exprs(&r.body, dst);
        }
        self.in_repeat = false;
    }
    func expand_repeat(self, r: Repeat*, dst: List<Stmt>*){
        if(self.repeat_param.is_none()){
            self.errors.add("$( ... )* is only valid inside a macro with a list parameter".str());
            return;
        }
        if(self.in_repeat){
            self.errors.add("nested $( ... )* is not supported".str());
            return;
        }
        //one copy of the body per element. Copying the body again per iteration
        //is what makes the iteration hygienic: a declaration inside it is
        //alpha-renamed again, so `let t` in two iterations is two bindings.
        self.in_repeat = true;
        let key = format!("${}", self.repeat_param.get());
        for(let i = 0;i < self.repeat_elems.size();++i){
            let elem = self.repeat_elems.get(i);
            self.expr_map.add(key.clone(), *elem);
            //visit_stmts, not visit: a nested repetition must reach the
            //in_repeat check above instead of surviving as a statement
            self.visit_stmts(&r.body.list, dst);
        }
        self.in_repeat = false;
    }
    
    func visit(self, node: Fragment*): Fragment{
      let id = self.node(node as Node*);
      //the initializer belongs to the enclosing scope, so it is copied before
      //the name becomes the fresh one
      let ty = self.visit_opt(&node.type);
      let rhs = self.visit(&node.rhs);
      if(self.hygienic && !self.in_arg){
        return Fragment{.id, self.hygienic_name(&node.name), ty, rhs};
      }
      return Fragment{.id, node.name.clone(), ty, rhs};
    }

    func visit(self, node: VarExpr*): VarExpr{
        return VarExpr{list: self.visit_list(&node.list)};
    }

    func visit(self, node: ArgBind*): ArgBind{
        let id = self.node(node as Node*);
        //match/if-let bindings are binders, like Fragment
        if(self.hygienic && !self.in_arg){
            return ArgBind{.id, self.hygienic_name(&node.name)};
        }
        return ArgBind{.id, node.name.clone()};
    }
    func visit(self, node: Body*): Body{
        let id = self.node(node as Node*);
        match node{
            Body::Block(b) => return Body::Block{.id, self.visit(b)},
            Body::Stmt(b) => return Body::Stmt{.id, self.visit(b)},
            Body::If(b) => return Body::If{.id, self.visit(b)},
            Body::IfLet(b) => return Body::IfLet{.id, self.visit(b)},
        }     
    }

    func visit(self, node: Stmt*): Stmt{
        let id = self.node(node as Node*);
        match node{
            Stmt::Repeat(r) => return Stmt::Repeat{.id, Repeat{body: self.visit(&r.body)}},
            Stmt::Break => return Stmt::Break{.id},
            Stmt::Continue => return Stmt::Continue{.id},
            Stmt::Var(ve) => return Stmt::Var{.id, self.visit(ve)},
            Stmt::Expr(e) => return Stmt::Expr{.id, self.visit(e)},
            Stmt::Ret(opt) => return Stmt::Ret{.id, self.visit_opt(opt)},
            Stmt::While(e, body) => return Stmt::While{.id, cond: self.visit(e), then: self.visit(body)},
            Stmt::For(fs) => {
                return Stmt::For{.id, ForStmt{
                    var_decl: self.visit_opt(&fs.var_decl),
                    cond: self.visit_opt(&fs.cond),
                    updaters: self.visit_list(&fs.updaters),
                    body: self.visit_box(&fs.body),
                }};
            },
            Stmt::ForEach(fe) => {
                //the iterated expression is copied first: the loop variable
                //comes into scope only for the body
                let rhs = self.visit(&fe.rhs);
                let vname = if(self.hygienic && !self.in_arg){ self.hygienic_name(&fe.var_name) } else { fe.var_name.clone() };
                let body = self.visit(&fe.body);
                return Stmt::ForEach{.id, ForEach{
                    var_name: vname,
                    rhs: rhs,
                    body: body
                }};
            },
        }
    }

    func visit(self, is: IfStmt*): IfStmt{
        return IfStmt{
            cond: self.visit(&is.cond),
            then: self.visit_box(&is.then),
            else_stmt: self.visit_ptr(&is.else_stmt)
        };
    }

    func visit(self, is: IfLet*): IfLet{
        return IfLet{
            type: self.visit(&is.type),
            args: self.visit_list(&is.args),
            rhs: self.visit(&is.rhs),
            then: self.visit_box(&is.then),
            else_stmt: self.visit_ptr(&is.else_stmt)
        };
    }

    func visit(self, node: Expr*): Expr{
        //macro expansion: a bare name bound to an argument is replaced by a
        //copy of that argument (each reference copies: a twice-used argument
        //is evaluated twice, and the ownership pass diagnoses that if it moves)
        let id = self.node(node as Node*);
        if(!self.in_arg){
            if let Expr::Name(name) = node{
                //a name the body itself declared (hygienic alpha-rename) wins
                //over the parameter maps: it is the innermost binding
                let local = self.local_renames.get(name);
                if(local.is_some()){
                    return Expr::Name{.id, local.unwrap().clone()};
                }
                let rep = self.expr_map.get(name);
                if(rep.is_some()){
                    self.in_arg = true;
                    let res = self.visit(*rep.unwrap());
                    self.in_arg = false;
                    return res;
                }
                //value parameter: bound under a fresh name (see rename_map), so
                //every reference in the body becomes that name
                let renamed = self.rename_map.get(name);
                if(renamed.is_some()){
                    return Expr::Name{.id, renamed.unwrap().clone()};
                }
                //`$xs`: the current element of the repetition being expanded
                if(name.str().starts_with("$")){
                    let elem = self.expr_map.get(name);
                    if(elem.is_some()){
                        self.in_arg = true;
                        let res = self.visit(*elem.unwrap());
                        self.in_arg = false;
                        return res;
                    }
                    if(self.repeat_param.is_none()){
                        self.errors.add(format("'{}' is only valid inside $( ... )*", name));
                    }else{
                        self.errors.add(format("'{}' is not a list parameter", name));
                    }
                    return Expr::Name{.id, name.clone()};
                }
                //a list parameter is only usable as `$name` inside the repetition
                if(self.repeat_param.is_some() && name.eq(self.repeat_param.get())){
                    self.errors.add(format("list parameter '{}' must be used as '${}' inside $( ... )*", name, name));
                }
                //neither declared in the body nor a parameter: a free name,
                //resolved at the call site (see expand_user_macro's guard)
                self.free_names.add(name.clone());
            }
        }
        match node{
            Expr::Name(name) => return Expr::Name{.id, name.clone()},
            Expr::Call(mc) => return Expr::Call{.id, self.visit(mc)},
            Expr::MacroCall(mc) => return Expr::MacroCall{.id, self.visit(mc)},
            Expr::If(is) => return Expr::If{.id, Box::new(self.visit(is.get()))},
            Expr::IfLet(is) => return Expr::IfLet{.id, Box::new(self.visit(is.get()))},
            Expr::Block(b) => return Expr::Block{.id, Box::new(self.visit(b.get()))},
            Expr::Lit(lit) => return Expr::Lit{.id, Literal{lit.kind, lit.val.clone(), self.visit_opt(&lit.suffix)}},
            Expr::Par(e) => return Expr::Par{.id, self.visit_box(e)},
            Expr::Type(type) => return Expr::Type{.id, self.visit(type)},
            Expr::Unary(op, e) => return Expr::Unary{.id, op.clone(), self.visit_box(e)},
            Expr::Infix(op, l, r) => return Expr::Infix{.id, op.clone(), self.visit_box(l), self.visit_box(r)},
            Expr::Access(scope, name) => return Expr::Access{.id, self.visit_box(scope), name.clone()},
            Expr::Obj(type, args) => return Expr::Obj{.id, self.visit(type), self.visit_list(args)},
            Expr::As(e, type) => return Expr::As{.id,  self.visit_box(e), self.visit(type)},
            Expr::Is(e, rhs) => return Expr::Is{.id, self.visit_box(e), self.visit_box(rhs)},
            Expr::Array(list, size) => return Expr::Array{.id, self.visit_expr_list(list), self.visit_opt(size)},
            Expr::ArrAccess(aa) => return Expr::ArrAccess{.id, ArrAccess{
                arr: self.visit_box(&aa.arr),
                idx: self.visit_box(&aa.idx),
                idx2: self.visit_ptr(&aa.idx2)
            }},
            Expr::Lambda(lm) => return Expr::Lambda{.id, Lambda{
                params: self.visit_list(&lm.params),
                return_type: self.visit_opt(&lm.return_type),
                body: self.visit_box(&lm.body)
            }},
            Expr::Match(m) => return Expr::Match{.id, Box::new(Match{
                expr: self.visit(&m.get().expr),
                cases: self.visit_list(&m.get().cases)
            })},
            Expr::Ques(bx) => return Expr::Ques{.id, self.visit_box(bx)},
            Expr::Tuple(elems) => return Expr::Tuple{.id, self.visit_expr_list(elems)},
            Expr::Repeat(r) => {
                //the list visitors splice these; one reaching a single value
                //expression has nowhere to expand into
                self.errors.add("$( ... )* is only valid as an element of a list (arguments, array/tuple elements)".str());
                return Expr::Repeat{.id, RepeatExpr{body: self.visit_expr_list(&r.body), sep: r.sep.clone()}};
            },
        }
    }
    func visit(self, node: LambdaParam*): LambdaParam{
        let id = self.node(node as Node*);
        let ty = self.visit_opt(&node.type);
        if(self.hygienic && !self.in_arg){
          return LambdaParam{.id, type: ty, name: self.hygienic_name(&node.name)};
        }
        return LambdaParam{.id, type: ty, name: node.name.clone()};
        
    }
    func visit(self, node: LambdaBody*): LambdaBody{
        match node{
            LambdaBody::Expr(e) => return LambdaBody::Expr{self.visit(e)},
            LambdaBody::Stmt(st) => return LambdaBody::Stmt{self.visit(st)},
        }
    }

    func visit(self, node: Entry*): Entry{
        return Entry{
            name: self.visit_opt(&node.name), 
            expr: self.visit(&node.expr), 
            isBase: node.isBase
        };
    }

    func visit(self, node: MatchCase*): MatchCase{
        let lhs = match &node.lhs{
            MatchLhs::NONE => MatchLhs::NONE,
            MatchLhs::ENUM(type, args) => MatchLhs::ENUM{self.visit(type), self.visit_list(args)},
            MatchLhs::UNION(types) => MatchLhs::UNION{self.visit_list(types)},
        };
        let rhs = match &node.rhs{
            MatchRhs::EXPR(expr) => MatchRhs::EXPR{self.visit(expr)},
            MatchRhs::STMT(stmt) => MatchRhs::STMT{self.visit(stmt)},
        };
        return MatchCase{lhs: lhs, rhs: rhs, line: node.line};
    }
    
    func visit(self, node: Call*): Call{
        let scope = self.visit_ptr(&node.scope);
        let name = node.name.clone();
        //an unqualified callee that the body declared is a local (a lambda):
        //its name was alpha-renamed, so the call has to follow. A scoped call
        //is a method lookup and a name that is not a body local is a function.
        if(self.hygienic && !self.in_arg && scope.is_none()){
            let local = self.local_renames.get(&node.name);
            if(local.is_some()){
                name = local.unwrap().clone();
            }
        }
        return Call{
            scope: scope, 
            name: name,
            type_args: self.visit_list(&node.type_args), 
            args: self.visit_expr_list(&node.args), 
            is_static: node.is_static
        };
    }

    func visit(self, node: MacroCall*): MacroCall{
      return MacroCall{
        scope: self.visit_opt(&node.scope),
        name: node.name.clone(),
        args: self.visit_expr_list(&node.args)
      };
    }
}