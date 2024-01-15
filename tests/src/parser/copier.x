import parser/ast
import std/map

struct AstCopier{
    map: Map<String, Type>*;
}

impl AstCopier{
    func new(map: Map<String, Type>*): AstCopier{
        return AstCopier{map: map};
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
        let res = Simple::new(smp.name);
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
        return Param{name: p.name.clone(),
            type: self.visit(&p.type),
            is_self: p.is_self};
    }

    func visit(self, p: Parent*): Parent{
        if let Parent::Impl(info*) = (p){
            return Parent::Impl{ImplInfo{type_params: self.visit_list(&info.type_params),
                trait_name: self.visit_opt(&info.trait_name),
                type: self.visit(&info.type)}};
        }
        return *p;
    }

    func visit(self, m: Method*): Method{
        let type_args = List<Type>::new();
        for(let i = 0;i < m.type_args.size();++i){
            let ta = m.type_args.get_ptr(i);
            type_args.add(self.visit(ta));
        }
        let selff = Option<Param>::new();
        if(m.self.is_some()){
            selff = Option::new(self.visit(m.self.get()));
        }
        let params = self.visit_list(&m.params);
        return Method{line: m.line,
            unit: m.unit,
            type_args: type_args,
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

    func visit(self, node: Stmt*): Stmt{
        if let Stmt::Block(b*)=(node){
            return Stmt::Block{self.visit(b)};
        }
        if let Stmt::Expr(e*)=(node){
            return Stmt::Expr{self.visit(e)};
        }
        if let Stmt::Ret(opt*)=(node){
            return Stmt::Ret{self.visit_opt(opt)};
        }
        panic("stmt %s", node.print().cstr());
    }

    func visit(self, node: Expr*): Expr{
        if let Expr::Name(name*)=(node){
            return Expr::Name{name.clone()};
        }
        if let Expr::Infix(op*, l*, r*)=(node){
            return Expr::Infix{op.clone(), self.visit_box(l), self.visit_box(r)};
        }
        panic("Expr %s", node.print().cstr());
    }
}