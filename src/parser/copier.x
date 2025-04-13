import std/libc
import std/hashmap

import parser/ast
import parser/printer
import parser/token

struct AstCopier{
    type_map: HashMap<String, Type>*;
    unit: Option<Unit*>;
}

impl Clone for Attributes{
    func clone(self): Attributes{
      return Attributes{list: self.list.clone()};
    }
}
impl Clone for Attribute{
    func clone(self): Attribute{
      return Attribute{name: self.name.clone(), args: self.args.clone(), is_call: self.is_call};
    }
}

impl AstCopier{
    func new(type_map: HashMap<String, Type>*, unit: Unit*): AstCopier{
        return AstCopier{type_map: type_map, unit: Option::new(unit)};
    }
    func new(type_map: HashMap<String, Type>*): AstCopier{
        return AstCopier{type_map: type_map, unit: Option<Unit*>::new()};
    }

    func clone<T>(node: T*, unit: Unit*): T{
        let type_map = HashMap<String, Type>::new();
        let copier = AstCopier::new(&type_map, unit);
        let res = copier.visit(node);
        type_map.drop();
        return res;
    }
    func clone<T>(node: T*): T{
        let type_map = HashMap<String, Type>::new();
        let copier = AstCopier::new(&type_map);
        let res = copier.visit(node);
        type_map.drop();
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

    func visit(self, node: Decl*): Decl{
        let type = self.visit(&node.type);
        let base = BaseDecl{
            line: node.line,
            path: node.path.clone(),
            type: type ,
            is_resolved: false,
            is_generic: false,
            base: self.visit_opt(&node.base), 
            attr: node.attr.clone()
        };
        match node{
            Decl::Struct(fields*)=>{
                let res = self.visit_list(fields);
                return Decl::Struct{.base, res};
            },
            Decl::Enum(variants*)=>{
                //enum
                let res = self.visit_list(variants);
                return Decl::Enum{.base, res};
            }
        }
    }

    func visit(self, node: FieldDecl*): FieldDecl{
        return FieldDecl{name: node.name.clone(), type: self.visit(&node.type)};
    }

    func visit(self, node: Variant*): Variant{
        return Variant{name: node.name.clone(), fields: self.visit_list(&node.fields)};
    }

    func visit(self, type: Type*): Type{
        let id = Node::new(-1, type.line);
        match type{
            Type::Pointer(bx*) => {
                let scope = self.visit(bx.get());
                let res = Type::Pointer{.id, Box::new(scope)};
                return res;
            },
            Type::Array(bx*, size) => {
                let scope = self.visit(bx.get());
                let res = Type::Array{.id, Box::new(scope), size};
                return res;
            },
            Type::Slice(bx*) => {
                let scope = self.visit(bx.get());
                let res = Type::Slice{.id, Box::new(scope)};
                return res;
            },
            Type::Function(bx*) => {
                let ft = FunctionType{
                    return_type: self.visit(&bx.get().return_type),
                    params: self.visit_list(&bx.get().params)
                };
                return Type::Function{.id, type: Box::new(ft)};
            },
            Type::Lambda(bx*) => {
                let lt = LambdaType{
                    return_type: self.visit_opt(&bx.get().return_type),
                    params: self.visit_list(&bx.get().params),
                    captured: self.visit_list(&bx.get().captured),
                };
                return Type::Lambda{.id, Box::new(lt)};
            },
            Type::Simple(smp*) => {
                if(self.type_map.contains(&smp.name)){
                    return self.type_map.get(&smp.name).unwrap().clone();
                }
                let res = Simple::new(smp.name.clone());
                if (smp.scope.is_some()) {
                    res.scope = Ptr::new(self.visit(smp.scope.get()));
                }
                for (let i = 0; i < smp.args.size(); ++i) {
                    let ta = smp.args.get(i);
                    res.args.add(self.visit(ta));
                }
                return res.into(type.line);
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
            is_deref: p.is_deref};
    }

    func visit(self, p: Parent*): Parent{
        match p{
            Parent::Impl(info*) => {
               return Parent::Impl{ImplInfo{type_params: self.visit_list(&info.type_params),
                trait_name: self.visit_opt(&info.trait_name),
                type: self.visit(&info.type)}};
            },
            Parent::Trait(ty*) => {
                return Parent::Trait{self.visit(ty)};
            },
            Parent::None=>{
                return Parent::None;
            },
            Parent::Extern=>{
                return Parent::Extern;
            }
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
            attr: m.attr.clone(),
        };
    }

    func visit(self, node: Block*): Block{
        let res = Block::new(node.line, node.end_line);
        self.visit_list(&node.list, &res.list);
        res.return_expr = self.visit_opt(&node.return_expr);
        return res;
    }
    
    func visit(self, node: Fragment*): Fragment{
      let id = self.node(node as Node*);
      return Fragment{.id, node.name.clone(), self.visit_opt(&node.type), self.visit(&node.rhs)};
    }

    func visit(self, node: VarExpr*): VarExpr{
        return VarExpr{list: self.visit_list(&node.list)};
    }

    func visit(self, node: ArgBind*): ArgBind{
        let id = self.node(node as Node*);
        return ArgBind{.id, node.name.clone(), node.is_ptr};
    }
    func visit(self, node: Body*): Body{
        let id = self.node(node as Node*);
        match node{
            Body::Block(b*) => return Body::Block{.id, self.visit(b)},
            Body::Stmt(b*) => return Body::Stmt{.id, self.visit(b)},
            Body::If(b*) => return Body::If{.id, self.visit(b)},
            Body::IfLet(b*) => return Body::IfLet{.id, self.visit(b)},
        }     
    }

    func visit(self, node: Stmt*): Stmt{
        let id = self.node(node as Node*);
        match node{
            Stmt::Break => return Stmt::Break{.id},
            Stmt::Continue => return Stmt::Continue{.id},
            Stmt::Var(ve*) => return Stmt::Var{.id, self.visit(ve)},
            Stmt::Expr(e*) => return Stmt::Expr{.id, self.visit(e)},
            Stmt::Ret(opt*) => return Stmt::Ret{.id, self.visit_opt(opt)},
            Stmt::While(e*, body*) => return Stmt::While{.id, cond: self.visit(e), then: self.visit(body)},
            Stmt::For(fs*) => {
                return Stmt::For{.id, ForStmt{
                    var_decl: self.visit_opt(&fs.var_decl),
                    cond: self.visit_opt(&fs.cond),
                    updaters: self.visit_list(&fs.updaters),
                    body: self.visit_box(&fs.body),
                }};
            },
            Stmt::ForEach(fe*) => return Stmt::ForEach{.id, ForEach{
                var_name: fe.var_name.clone(),
                rhs: self.visit(&fe.rhs),
                body: self.visit(&fe.body)
            }},
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
        let id = self.node(node as Node*);
        match node{
            Expr::Name(name*) => return Expr::Name{.id, name.clone()},
            Expr::Call(mc*) => return Expr::Call{.id, self.visit(mc)},
            Expr::MacroCall(mc*) => return Expr::MacroCall{.id, self.visit(mc)},
            Expr::If(is*) => return Expr::If{.id, Box::new(self.visit(is.get()))},
            Expr::IfLet(is*) => return Expr::IfLet{.id, Box::new(self.visit(is.get()))},
            Expr::Block(b*) => return Expr::Block{.id, Box::new(self.visit(b.get()))},
            Expr::Lit(lit*) => return Expr::Lit{.id, Literal{lit.kind, lit.val.clone(), self.visit_opt(&lit.suffix)}},
            Expr::Par(e*) => return Expr::Par{.id, self.visit_box(e)},
            Expr::Type(type*) => return Expr::Type{.id, self.visit(type)},
            Expr::Unary(op*, e*) => return Expr::Unary{.id, op.clone(), self.visit_box(e)},
            Expr::Infix(op*, l*, r*) => return Expr::Infix{.id, op.clone(), self.visit_box(l), self.visit_box(r)},
            Expr::Access(scope*, name*) => return Expr::Access{.id, self.visit_box(scope), name.clone()},
            Expr::Obj(type*, args*) => return Expr::Obj{.id, self.visit(type), self.visit_list(args)},
            Expr::As(e*, type*) => return Expr::As{.id,  self.visit_box(e), self.visit(type)},
            Expr::Is(e*, rhs*) => return Expr::Is{.id, self.visit_box(e), self.visit_box(rhs)},
            Expr::Array(list*, size*) => return Expr::Array{.id, self.visit_list(list), self.visit_opt(size)},
            Expr::ArrAccess(aa*) => return Expr::ArrAccess{.id, ArrAccess{
                arr: self.visit_box(&aa.arr),
                idx: self.visit_box(&aa.idx),
                idx2: self.visit_ptr(&aa.idx2)
            }},
            Expr::Lambda(lm*) => return Expr::Lambda{.id, Lambda{
                params: self.visit_list(&lm.params),
                return_type: self.visit_opt(&lm.return_type),
                body: self.visit_box(&lm.body)
            }},
            Expr::Match(m*) => return Expr::Match{.id, Box::new(Match{expr: self.visit(&m.get().expr), cases: self.visit_list(&m.get().cases)})}
        }
    }
    func visit(self, node: LambdaParam*): LambdaParam{
        let id = self.node(node as Node*);
        return LambdaParam{.id, type: self.visit_opt(&node.type), name: node.name.clone()};
        
    }
    func visit(self, node: LambdaBody*): LambdaBody{
        match node{
            LambdaBody::Expr(e*) => return LambdaBody::Expr{self.visit(e)},
            LambdaBody::Stmt(st*) => return LambdaBody::Stmt{self.visit(st)},
        }
    }

    func visit(self, node: Entry*): Entry{
        return Entry{name: self.visit_opt(&node.name), expr: self.visit(&node.expr), isBase: node.isBase};
    }

    func visit(self, node: MatchCase*): MatchCase{
        let lhs = match &node.lhs{
            MatchLhs::NONE => MatchLhs::NONE,
            MatchLhs::ENUM(type*, args*) => MatchLhs::ENUM{self.visit(type), self.visit_list(args)},
        };
        let rhs = match &node.rhs{
            MatchRhs::EXPR(expr*) => MatchRhs::EXPR{self.visit(expr)},
            MatchRhs::STMT(stmt*) => MatchRhs::STMT{self.visit(stmt)},
        };
        return MatchCase{lhs: lhs, rhs: rhs, line: node.line};
    }
    
    func visit(self, node: Call*): Call{
      return Call{scope: self.visit_ptr(&node.scope), name: node.name.clone(),
        type_args: self.visit_list(&node.type_args), args: self.visit_list(&node.args), is_static: node.is_static};
    }

    func visit(self, node: MacroCall*): MacroCall{
      return MacroCall{
        scope: self.visit_opt(&node.scope),
        name: node.name.clone(),
        args: self.visit_list(&node.args)
      };
    }
}