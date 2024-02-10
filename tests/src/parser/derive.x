import parser/ast

func make_info(decl: Decl*): ImplInfo{
    let info = ImplInfo::new(decl.type.clone());
    info.trait_name = Option::new(Type::new("Debug"));
    for(let i=0;i<decl.type.get_args().len();++i){
        let ta = decl.type.get_args().get_ptr(i);
        info.type_params.add(ta.clone());
    }
    return info;
}

func make_impl(decl: Decl*): Impl{
    let info = make_info(decl);
    return Impl{info: info, methods: List<Method>::new()};
}


func generate_derive(decl: Decl*, unit: Unit*): Impl{
    print("derive %s\n", decl.type.print().cstr());
    assert decl.derives.get_ptr(0).print().eq("Debug");
    let imp = make_impl(decl);
    let m = Method::new(Node::new(++unit.last_id, 0), unit, "debug".str(), Type::new("void"));
    m.self = Option::new(Param{.Node::new(++unit.last_id, 0), "self".str(), decl.type.clone().toPtr(), true});
    m.params.add(Param{.Node::new(++unit.last_id, 0), "f".str(), Type::new("Fmt").toPtr(), false});
    m.parent = Parent::Impl{make_info(decl)};
    m.path = unit.path.clone();
    let body = Block::new();
    if let Decl::Enum(variants*)=(decl){
        for(let i=0;i<variants.len();++i){
            let ev = variants.get_ptr(i);
            let vt = Simple::new(decl.type.clone(), ev.name.clone()).into();
            let then = Block::new();

            //f.print({decl.type}::{ev.name})
            then.list.add(newPrint(unit, "f", vt.print().str()));

            let id1 = Node::new(++unit.last_id, 0);
            let is = IfLet{vt, List<ArgBind>::new(), Expr::Name{.id1,"self".str()}, Box::new(Stmt::Block{then}), Option<Box<Stmt>>::new()};
            for(let j=0;j<ev.fields.len();++j){
                let fd = ev.fields.get_ptr(j);
                let id2 = Node::new(++unit.last_id, 0);
                is.args.add(ArgBind{.id2,fd.name.clone(), true});
            }
            body.list.add(Stmt::IfLet{is});
        }
    }else{
        panic("derive struct");
    }
    m.body = Option::new(body);
    imp.methods.add(m);
    return imp;
}

//scope.print("{lit}")
func newPrint(unit: Unit*, scope: str, lit: str): Stmt{
    let call = Call::new("print".str());
    let id = Node::new(++unit.last_id, 0);
    let id2 = Node::new(++unit.last_id, 0);
    let id3 = Node::new(++unit.last_id, 0);
    call.scope = Option::new(Box::new(Expr::Name{.id, scope.str()}));
    call.args.add(Expr::Lit{.id2, Literal{LitKind::STR, Fmt::format("\"{}\"", lit), Option<Type>::new()}});
    return Stmt::Expr{Expr::Call{.id3, call}};
}