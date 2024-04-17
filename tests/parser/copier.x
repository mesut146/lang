import parser/ast
import parser/printer
import std/map
import std/libc

struct AstCopier{
    map: Map<String, Type>*;
    unit: Option<Unit*>;
}

impl AstCopier{
    func new(map: Map<String, Type>*, unit: Unit*): AstCopier{
        return AstCopier{map: map, unit: Option::new(unit)};
    }
    func new(map: Map<String, Type>*): AstCopier{
        return AstCopier{map: map, unit: Option<Unit*>::None};
    }

    func visit_list<E>(self, list: List<E>*): List<E>{
        let res = List<E>::new();
        for(let i = 0;i < list.size();++i){
            let arg = list.get_ptr(i);
            res.add(self.visit(arg));
        }
        return res;
    }

    func visit_opt<E>(self, opt: Option<E>*): Option<E>{
        let res = Option<E>::new();
        if(opt.is_some()){
            res = Option<E>::new(self.visit(opt.get()));
        }
        return res;
    }

    func visit_box<E>(self, box: Box<E>*): Box<E>{
        return Box::new(self.visit(box.get()));
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
        //todo base type depends on map too
        let base = BaseDecl{line: node.line,path: node.path.clone(),type: type ,
            is_resolved: false, is_generic: false, base: self.visit_opt(&node.base), derives: node.derives.clone(), attr: node.attr.clone()};
        if let Decl::Struct(fields*)=(node){
            let res = self.visit_list(fields);
            return Decl::Struct{.base, res};
        }else if let Decl::Enum(variants*)=(node){
            //enum
            let res = self.visit_list(variants);
            return Decl::Enum{.base, res};
        }
        panic("visit decl %s*n", Fmt::str(node).cstr());
    }

    func visit(self, node: FieldDecl*): FieldDecl{
        return FieldDecl{name: node.name.clone(), type: self.visit(&node.type)};
    }

    func visit(self, node: Variant*): Variant{
        return Variant{name: node.name.clone(), fields: self.visit_list(&node.fields)};
    }

    func visit(self, type: Type*): Type{
        if let Type::Pointer(bx*) = (type){
            let scope = self.visit(bx.get());
            let res = Type::Pointer{Box::new(scope)};
            return res;
        }
        if let Type::Array(bx*, size) = (type){
            let scope = self.visit(bx.get());
            let res = Type::Array{Box::new(scope), size};
            return res;
        }
        if let Type::Slice(bx*) = (type){
            let scope = self.visit(bx.get());
            let res = Type::Slice{Box::new(scope)};
            return res;
        }
        let smp = type.as_simple();
        if(self.map.contains(&smp.name)){
            return self.map.get_ptr(&smp.name).unwrap().clone();
        }
        let res = Simple::new(smp.name.clone());
        if (smp.scope.is_some()) {
            res.scope = Ptr::new(self.visit(smp.scope.get()));
        }
        for (let i = 0; i < smp.args.size(); ++i) {
            let ta = smp.args.get_ptr(i);
            res.args.add(self.visit(ta));
        }
        return res.into();
    }

    func visit(self, p: Param*): Param{
        let id = self.node(p as Node*);
        return Param{.id, 
            name: p.name.clone(),
            type: self.visit(&p.type),
            is_self: p.is_self,
            is_deref: p.is_deref};
    }

    func visit(self, p: Parent*): Parent{
        if let Parent::Impl(info*) = (p){
            return Parent::Impl{ImplInfo{type_params: self.visit_list(&info.type_params),
                trait_name: self.visit_opt(&info.trait_name),
                type: self.visit(&info.type)}};
        }
        if let Parent::Trait(ty*) = (p){
          return Parent::Trait{self.visit(ty)};
        }
        if(p is Parent::None){
            return Parent::None;
        }
        if(p is Parent::Extern){
            return Parent::Extern;
        }
        panic("parent clone");
    }

    func visit(self, m: Method*): Method{
        let type_params = List<Type>::new();
        for(let i = 0;i < m.type_params.size();++i){
            let ta = m.type_params.get_ptr(i);
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
            path: m.path.clone()};
    }

    func visit(self, node: Block*): Block{
        return Block{list: self.visit_list(&node.list)};
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

    func visit(self, node: Stmt*): Stmt{
        if let Stmt::Block(b*)=(node){
            return Stmt::Block{self.visit(b)};
        }
        if let Stmt::Var(ve*)=(node){
            return Stmt::Var{self.visit(ve)};
        }
        if let Stmt::Expr(e*)=(node){
            return Stmt::Expr{self.visit(e)};
        }
        if let Stmt::Ret(opt*)=(node){
            return Stmt::Ret{self.visit_opt(opt)};
        }
        if let Stmt::While(e*, body*)=(node){
            return Stmt::While{e: self.visit(e), b: self.visit(body)};
        }
        if let Stmt::If(is*)=(node){
            return Stmt::If{IfStmt{e: self.visit(&is.e), then: self.visit_box(&is.then), els: self.visit_opt(&is.els)}};
        }
        if let Stmt::IfLet(is*)=(node){
            return Stmt::IfLet{IfLet{ty: self.visit(&is.ty), args: self.visit_list(&is.args), rhs: self.visit(&is.rhs), then: self.visit_box(&is.then), els: self.visit_opt(&is.els)}};
        }
        if let Stmt::For(fs*)=(node){
            return Stmt::For{ForStmt{v: self.visit_opt(&fs.v), e: self.visit_opt(&fs.e), u: self.visit_list(&fs.u), body: self.visit_box(&fs.body)}};
        }
        if let Stmt::Continue=(node){
            return Stmt::Continue;
        }
        if let Stmt::Break=(node){
            return Stmt::Break;
        }
        if let Stmt::Assert(e*)=(node){
            return Stmt::Assert{self.visit(e)};
        }
        panic("stmt %s", node.print().cstr());
    }

    func visit(self, node: Expr*): Expr{
        let id = self.node(node as Node*);
        if let Expr::Lit(lit*)=(node){
            return Expr::Lit{.id, Literal{lit.kind, lit.val.clone(), self.visit_opt(&lit.suffix)}};
        }
        if let Expr::Name(name*)=(node){
            return Expr::Name{.id,name.clone()};
        }
        if let Expr::Call(mc*)=(node){
            return Expr::Call{.id,self.visit(mc)};
        }
        if let Expr::Par(e*)=(node){
            return Expr::Par{.id,self.visit_box(e)};
        }
        if let Expr::Type(type*)=(node){
            return Expr::Type{.id,self.visit(type)};
        }
        if let Expr::Unary(op*, e*)=(node){
            return Expr::Unary{.id,op.clone(), self.visit_box(e)};
        }
        if let Expr::Infix(op*, l*, r*)=(node){
            return Expr::Infix{.id,op.clone(), self.visit_box(l), self.visit_box(r)};
        }
        if let Expr::Access(scope*, name*)=(node){
            return Expr::Access{.id,self.visit_box(scope), name.clone()};
        }
        if let Expr::Obj(type*, args*)=(node){
            return Expr::Obj{.id,self.visit(type), self.visit_list(args)};
        }
        if let Expr::As(e*, type*)=(node){
            return Expr::As{.id,self.visit_box(e), self.visit(type)};
        }
        if let Expr::Is(e*, rhs*)=(node){
            return Expr::Is{.id,self.visit_box(e), self.visit_box(rhs)};
        }
        if let Expr::Array(list*, size*)=(node){
            return Expr::Array{.id,self.visit_list(list), self.visit_opt(size)};
        }
        if let Expr::ArrAccess(aa*)=(node){
            return Expr::ArrAccess{.id,ArrAccess{arr: self.visit_box(&aa.arr), idx: self.visit_box(&aa.idx), idx2: self.visit_opt(&aa.idx2)}};
        }
        panic("Expr %s", node.print().cstr());
    }

    func visit(self, node: Entry*): Entry{
        return Entry{name: self.visit_opt(&node.name), expr: self.visit(&node.expr), isBase: node.isBase};
    }
    
    func visit(self, node: Call*): Call{
      return Call{scope: self.visit_opt(&node.scope), name: node.name.clone(),
        type_args: self.visit_list(&node.type_args), args: self.visit_list(&node.args), is_static: node.is_static};
    }
}