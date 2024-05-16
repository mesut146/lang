import parser/ast
import parser/utils
import parser/printer
import parser/resolver
import parser/copier
import parser/parser
import parser/lexer
import parser/token
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
            //self.{fd.name}.drop();
            let input = format("self.{}.drop();", &fd.name);
            let drop_stmt = parse_stmt(input, unit);
            print("drop_stmt: {}\n", &drop_stmt);
            body.list.add(drop_stmt);
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

func parse_stmt(input: String, unit: Unit*): Stmt{
    let parser = Parser::from_string(input);
    parser.unit = Option::new(unit);
    let res = parser.parse_stmt();
    Drop::drop(parser);
    return res;
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
    let fmt_str: str = lit_opt.unwrap().str();
    let format_specs = ["%s", "%d", "%c", "%f", "%u", "%ld", "%lld", "%lu", "%llu", "%x", "%X"];
    for (let i = 0;i < format_specs.len();++i) {
        let fs = format_specs[i];
        if (fmt_str.contains(fs)) {
            r.err(node, format("invalid format specifier: {}", fs));
        }
    }
    let line = node.line;
    let info = FormatInfo{block: Block::new(), unwrap_mc: Call::new("unwrap".str())};
    let block = &info.block;
    if (mc.args.len() == 1 && (Resolver::is_print(mc) || Resolver::is_panic(mc))) {
        //optimized print, no heap alloc, no fmt
        //"..".print(), exit(1) will be called by compiler
        let print_mc = Call::new("print".str());
        if (Resolver::is_panic(mc)) {
            print_mc.scope = Ptr::new(make_panic_messsage(line, *r.curMethod.get(), Option::new(fmt_str), &r.unit));
        } else {
            print_mc.scope = Ptr::new(AstCopier::clone(fmt, &r.unit));
        }
        let id = r.unit.node(line);
        block.list.add(Stmt::Expr{Expr::Call{.id, print_mc}});
        r.visit(block);
        r.format_map.add(node.id, info);
        return;
    }
    let var_name = format("f_{}", node.id);
    //let f = Fmt::new();
    let var_stmt = parse_stmt(format("let {} = Fmt::new();", &var_name), &r.unit);
    print("var_stmt: {}\n", &var_stmt);
    block.list.add(var_stmt);
    let pos = 0;
    let arg_idx = 0;
    while(pos < fmt_str.len()){
        let br_pos = fmt_str.indexOf("{}", pos);
        if(br_pos == -1 || br_pos > pos){
            let sub = "";
            if(br_pos == -1){
                sub = fmt_str.substr(pos);
            }else{
                sub = fmt_str.substr(pos, br_pos);
            }
            let sub2 = normalize_quotes(sub);
            let st = parse_stmt(format("{}.print({});", &var_name, sub2), &r.unit);
            print("st: {}\n", &st);
            block.list.add(st);
            break;
        }else{

        }
    }
    r.format_map.add(node.id, info);
    r.err(node, "generate_format");
}

//replace non escaped quotes into escaped ones
func normalize_quotes(s: str): String{
    let res = String::new();
    for(let i = 0;i < s.len();++i){
        let c = s.get(i);
        if(c == "\"" || c == "\\"){
            res.add('\\');
        }
        res.add(c);
    }
    return res;
}

func make_panic_messsage(line: i32, method: Method*, s: Option<str>, unit: Unit*): Expr {
    let message = Fmt::new("panic ".str());
    message.print(&method.path);
    message.print(":");
    message.print(&line);
    message.print(" ");
    message.print(printMethod(method).str());
    if (s.is_some()) {
        message.print("\n");
        message.print(s.get());
    }
    message.print("\n");
    let id = unit.node(line);
    return Expr::Lit{.id, Literal{LitKind::STR, message.unwrap(), Option<Type>::new()}};
}