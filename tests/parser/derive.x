import parser/ast
import parser/utils
import parser/printer
import parser/resolver
import parser/copier
import std/libc
import std/map

func make_info(decl: Decl*, trait_name: str): ImplInfo{
    let info = ImplInfo::new(decl.type.clone());
    info.trait_name = Option::new(Type::new(trait_name.str()));
    for(let i=0;i<decl.type.get_args().len();++i){
        let ta = decl.type.get_args().get_ptr(i);
        info.type_params.add(ta.clone());
    }
    return info;
}

func make_impl(decl: Decl*, trait_name: str): Impl{
    let info = make_info(decl, trait_name);
    return Impl{info: info, methods: List<Method>::new()};
}

//scope.name(arg)
func newCall(unit: Unit*, scope: str, name: str, arg: Option<Expr>): Stmt{
    let call = Call::new(name.str());
    let id = unit.node(0);
    let id2 = unit.node(0);
    call.scope = Ptr::new(Expr::Name{.id, scope.str()});
    if(arg.is_some()){
        call.args.add(arg.unwrap());
    }
    return Stmt::Expr{Expr::Call{.id2, call}};
}

//scope.name(arg)
func newCall(unit: Unit*, scope: Expr, name: str, arg: Expr): Stmt{
    let call = Call::new(name.str());
    let id = unit.node(0);
    let id2 = unit.node(0);
    call.scope = Ptr::new(scope);
    call.args.add(arg);
    return Stmt::Expr{Expr::Call{.id2, call}};
}

//scope.name()
func newCall(unit: Unit*, scope: Expr, name: str): Stmt{
    let call = Call::new(name.str());
    let id = unit.node(0);
    let id2 = unit.node(0);
    call.scope = Ptr::new(scope);
    return Stmt::Expr{Expr::Call{.id2, call}};
}

//scope.name()
func newCall(unit: Unit*, scope: str, name: str): Stmt{
    let id = unit.node(0);
    return newCall(unit, Expr::Name{.id, scope.str()}, name);
}

func newFa(unit: Unit*, scope: str, name: str): Expr{
    let id = unit.node(0);
    let id2 = unit.node(0);
    let scope_expr = Expr::Name{.id, scope.str()};
    return Expr::Access{.id2, Box::new(scope_expr), name.str()};
}

//scope.print("{lit}")
func newPrint(unit: Unit*, scope: str, lit: str): Stmt{
    let call = Call::new("print".str());
    let id = unit.node(0);
    let id2 = unit.node(0);
    let id3 = unit.node(0);
    call.scope = Ptr::new(Expr::Name{.id, scope.str()});
    call.args.add(Expr::Lit{.id2, Literal{LitKind::STR, format("\"{}\"", lit), Option<Type>::new()}});
    return Stmt::Expr{Expr::Call{.id3, call}};
}

func generate_derive(decl: Decl*, unit: Unit*, der: str): Impl{
    if(der.eq("Debug")){
        return generate_debug(decl, unit);
    }
    if(der.eq("Drop")){
        return generate_drop(decl, unit);
    }
    //todo clone
    panic("generate_derive decl: {} der: '{}'", decl.type, der);
}

func generate_drop(decl: Decl*, unit: Unit*): Impl{
    let body = Block::new();
    if let Decl::Enum(variants*)=(decl){
        for(let i = 0;i < variants.len();++i){
            let ev = variants.get_ptr(i);
            let vt = Simple::new(decl.type.clone(), ev.name.clone()).into();
            let then = Block::new();

            for(let j = 0;j < ev.fields.len();++j){
                let fd = ev.fields.get_ptr(j);
                //{fd.name}.drop()
                then.list.add(newCall(unit, fd.name.str(), "drop"));
            }

            let self_id = unit.node(0);
            let iflet = IfLet{vt, List<ArgBind>::new(), Expr::Name{.self_id, "self".str()}, Box::new(Stmt::Block{then}), Option<Box<Stmt>>::new()};
            for(let j = 0;j < ev.fields.len();++j){
                let fd = ev.fields.get_ptr(j);
                let arg_id = unit.node(0);
                iflet.args.add(ArgBind{.arg_id,fd.name.clone(), true});
            }
            body.list.add(Stmt::IfLet{iflet});
        }
    }else{
        let fields = decl.get_fields();
        for(let i=0;i<fields.len();++i){
            let fd = fields.get_ptr(i);
            if(!is_struct(&fd.type)) continue;
            //{fd.name}.drop();
            body.list.add(newCall(unit, fd.name.str(), "drop"));
        }
    }
    let m = Method::new(unit.node(0), "drop".str(), Type::new("void"));
    m.self = Option::new(Param{.unit.node(0), "self".str(), decl.type.clone().toPtr(), true, true});
    m.parent = Parent::Impl{make_info(decl, "Drop")};
    m.path = unit.path.clone();
    m.body = Option::new(body);
    let imp = make_impl(decl, "Drop");
    imp.methods.add(m);
    return imp;
}

func generate_debug(decl: Decl*, unit: Unit*): Impl{
    let imp = make_impl(decl, "Debug");
    let m = Method::new(Node::new(++unit.last_id, 0), "debug".str(), Type::new("void"));
    m.self = Option::new(Param{.Node::new(++unit.last_id, 0), "self".str(), decl.type.clone().toPtr(), true, false});
    m.params.add(Param{.Node::new(++unit.last_id, 0), "f".str(), Type::new("Fmt").toPtr(), false, false});
    m.parent = Parent::Impl{make_info(decl, "Debug")};
    m.path = unit.path.clone();
    let body = Block::new();
    if let Decl::Enum(variants*)=(decl){
        for(let i=0;i<variants.len();++i){
            let ev = variants.get_ptr(i);
            let vt = Simple::new(decl.type.clone(), ev.name.clone()).into();
            let then = Block::new();

            //f.print({decl.type}::{ev.name})
            then.list.add(newPrint(unit, "f", vt.print().str()));
            then.list.add(newPrint(unit, "f", "{"));
            for(let j = 0;j < ev.fields.len();++j){
                let fd = ev.fields.get_ptr(j);
                if(j > 0){
                    then.list.add(newPrint(unit, "f", ", "));
                }
                //f.print(fd.name)
                then.list.add(newPrint(unit, "f", fd.name.str()));
            }
            then.list.add(newPrint(unit, "f", "}"));

            let self_id = unit.node(0);
            let is = IfLet{vt, List<ArgBind>::new(), Expr::Name{.self_id, "self".str()}, Box::new(Stmt::Block{then}), Option<Box<Stmt>>::new()};
            for(let j = 0;j < ev.fields.len();++j){
                let fd = ev.fields.get_ptr(j);
                let arg_id = unit.node(0);
                is.args.add(ArgBind{.arg_id,fd.name.clone(), true});
            }
            body.list.add(Stmt::IfLet{is});
        }
    }else{
        //f.print(decl.type.print())
        body.list.add(newPrint(unit, "f", decl.type.print().str()));
        body.list.add(newPrint(unit, "f", "{"));
        let fields = decl.get_fields();
        for(let i=0;i<fields.len();++i){
            let fd = fields.get_ptr(i);
            if(i > 0){
                body.list.add(newPrint(unit, "f", ", "));
            }
            //self.{fd.name}.debug(f);
            let arg = Expr::Name{.unit.node(0), "f".str()};
            body.list.add(newCall(unit, newFa(unit, "self", fd.name.str()), "debug", arg));
        }
        body.list.add(newPrint(unit, "f", "}"));
    }
    m.body = Option::new(body);
    imp.methods.add(m);
    return imp;
}

func generate_format(node: Expr*, mc: Call*, r: Resolver*) {
    if (mc.args.empty()) {
        r.err(node, "format no arg");
    }
    let fmt: Expr* = mc.args.get_ptr(0);
    let lit_opt = is_str_lit(fmt);
    if (lit_opt.is_none()) {
        r.err(node, "format arg not str literal");
    }
    let fmt_str: String* = lit_opt.unwrap();
    let format_specs = ["%s", "%d", "%c", "%f", "%u", "%ld", "%lld", "%lu", "%llu", "%x", "%X"];
    for (let i = 0;i < format_specs.len();++i) {
        let fs = format_specs[i];
        if (fmt_str.str().contains(fs)) {
            r.err(node, format("invalid format specifier: {}", fs));
        }
    }
    let block = Block::new();
    let line = node.line;
    if (mc.args.len() == 1 && (Resolver::is_print(mc) || Resolver::is_panic(mc))) {
        //optimized print, no heap alloc, no fmt
        //"..".print(), exit(1) will be called by compiler
        let print_mc = Call::new("print".str());
        if (Resolver::is_panic(mc)) {
            //print_mc.scope = Ptr::new(make_panic_messsage(fmt_str, mc->line, r->curMethod));
        } else {
            print_mc.scope = Ptr::new(AstCopier::clone(fmt));
        }
        let id = r.unit.node(line);
        block.list.add(Stmt::Expr{Expr::Call{.id, print_mc}});
        //block.accept(r);
        //r->format_map.insert({mc->id, std::move(info)});
        return;
    }
}

func make_panic_messsage(line: i32, method: Method*): Expr {
    std::string message = "panic ";
    message += method->path + ":" + std::to_string(line);
    message += " " + printMethod(method);
    if (s.has_value()) {
        message += "\n";
        message += s.value();
    }
    message.append("\n");
    return Expr::Lit{Literal(Literal::STR, message)};
}