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

    func clone<T>(node: T*, unit: Unit*): T{
        let map = Map<String, Type>::new();
        let copier = AstCopier::new(&map, unit);
        let res = copier.visit(node);
        Drop::drop(map);
        return res;
    }
    func clone<T>(node: T*): T{
        let map = Map<String, Type>::new();
        let copier = AstCopier::new(&map);
        let res = copier.visit(node);
        Drop::drop(map);
        return res;
    }

    func visit_list<E>(self, list: List<E>*): List<E>{
        let res = List<E>::new();
        for(let i = 0;i < list.size();++i){
            let arg = list.get_ptr(i);
            res.add(self.visit(arg));
        }
        return res;
    }

    func visit_list<E>(self, list1: List<E>*, list2: List<E>*){
        for(let i = 0;i < list1.size();++i){
            let arg = list1.get_ptr(i);
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
        Drop::drop(base);
        let msg = format("visit decl {}\n", node);
        panic("{}", msg.str());
    }

    func visit(self, node: FieldDecl*): FieldDecl{
        return FieldDecl{name: node.name.clone(), type: self.visit(&node.type)};
    }

    func visit(self, node: Variant*): Variant{
        return Variant{name: node.name.clone(), fields: self.visit_list(&node.fields)};
    }

    func visit(self, type: Type*): Type{
        let id = Node::new(-1, type.line);
        if let Type::Pointer(bx*) = (type){
            let scope = self.visit(bx.get());
            let res = Type::Pointer{.id, Box::new(scope)};
            return res;
        }
        if let Type::Array(bx*, size) = (type){
            let scope = self.visit(bx.get());
            let res = Type::Array{.id, Box::new(scope), size};
            return res;
        }
        if let Type::Slice(bx*) = (type){
            let scope = self.visit(bx.get());
            let res = Type::Slice{.id, Box::new(scope)};
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
        return res.into(type.line);
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
        let res = Block::new(node.line, node.end_line);
        self.visit_list(&node.list, &res.list);
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

    func visit(self, node: Stmt*): Stmt{
        let id = self.node(node as Node*);
        if let Stmt::Block(b*)=(node){
            return Stmt::Block{.id, self.visit(b)};
        }
        if let Stmt::Var(ve*)=(node){
            return Stmt::Var{.id, self.visit(ve)};
        }
        if let Stmt::Expr(e*)=(node){
            return Stmt::Expr{.id, self.visit(e)};
        }
        if let Stmt::Ret(opt*)=(node){
            return Stmt::Ret{.id, self.visit_opt(opt)};
        }
        if let Stmt::While(e*, body*)=(node){
            return Stmt::While{.id, cond: self.visit(e), then: self.visit(body)};
        }
        if let Stmt::If(is*)=(node){
            return Stmt::If{.id, IfStmt{cond: self.visit(&is.cond), then: self.visit_box(&is.then), else_stmt: self.visit_ptr(&is.else_stmt)}};
        }
        if let Stmt::IfLet(is*)=(node){
            return Stmt::IfLet{.id, IfLet{type: self.visit(&is.type), args: self.visit_list(&is.args), rhs: self.visit(&is.rhs), then: self.visit_box(&is.then), else_stmt: self.visit_ptr(&is.else_stmt)}};
        }
        if let Stmt::For(fs*)=(node){
            return Stmt::For{.id, ForStmt{var_decl: self.visit_opt(&fs.var_decl), cond: self.visit_opt(&fs.cond), updaters: self.visit_list(&fs.updaters), body: self.visit_box(&fs.body)}};
        }
        if let Stmt::Continue = (node){
            return Stmt::Continue{.id};
        }
        if let Stmt::Break = (node){
            return Stmt::Break{.id};
        }
        let msg = format("stmt {}", node);
        panic("{}", msg.str());
    }

    func visit(self, node: Expr*): Expr{
        let id = self.node(node as Node*);
        if let Expr::Lit(lit*)=(node){
            return Expr::Lit{.id, Literal{lit.kind, lit.val.clone(), self.visit_opt(&lit.suffix)}};
        }
        if let Expr::Name(name*)=(node){
            return Expr::Name{.id, name.clone()};
        }
        if let Expr::Call(mc*)=(node){
            return Expr::Call{.id, self.visit(mc)};
        }
        if let Expr::Par(e*)=(node){
            return Expr::Par{.id, self.visit_box(e)};
        }
        if let Expr::Type(type*)=(node){
            return Expr::Type{.id, self.visit(type)};
        }
        if let Expr::Unary(op*, e*)=(node){
            return Expr::Unary{.id, op.clone(), self.visit_box(e)};
        }
        if let Expr::Infix(op*, l*, r*)=(node){
            return Expr::Infix{.id, op.clone(), self.visit_box(l), self.visit_box(r)};
        }
        if let Expr::Access(scope*, name*)=(node){
            return Expr::Access{.id, self.visit_box(scope), name.clone()};
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
            return Expr::ArrAccess{.id,ArrAccess{arr: self.visit_box(&aa.arr), idx: self.visit_box(&aa.idx), idx2: self.visit_ptr(&aa.idx2)}};
        }
        let msg = format("Expr {}", node);
        panic("{}", msg.str());
    }

    func visit(self, node: Entry*): Entry{
        return Entry{name: self.visit_opt(&node.name), expr: self.visit(&node.expr), isBase: node.isBase};
    }
    
    func visit(self, node: Call*): Call{
      return Call{scope: self.visit_ptr(&node.scope), name: node.name.clone(),
        type_args: self.visit_list(&node.type_args), args: self.visit_list(&node.args), is_static: node.is_static};
    }
}