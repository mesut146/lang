import std/libc
import std/map
import std/stack

import ast/ast
import ast/utils
import ast/printer
import ast/copier
import ast/parser
import ast/lexer
import ast/token

import resolver/resolver
import resolver/drop_helper

import parser/ownership

func make_info(decl: Decl*, trait_name: str): ImplInfo{
    let info = ImplInfo::new(decl.type.clone());
    info.trait_name = Option::new(Type::new(trait_name.str()));
    for ta in decl.type.get_args(){
        info.type_params.add(ta.clone());
    }
    return info;
}

func make_impl(decl: Decl*, trait_name: str): Impl{
    let info = make_info(decl, trait_name);
    return Impl{info: info, methods: List<Method>::new()};
}

//True when this unit already has a hand-written impl of `trait_name` for
//`decl` (`impl Display for A{...}`). A derive then steps aside: the explicit
//impl is the user's choice, and registering a second impl for the same type
//would make method lookup depend on candidate order.
func has_trait_impl(r: Resolver*, decl: Decl*, trait_name: str): bool{
    for(let i = 0;i < r.unit.items.len();++i){
        let it: Item* = r.unit.items.get(i);
        if(!(it is Item::Impl)){
            continue;
        }
        let imp: Impl* = it.as_impl();
        let tr = &imp.info.trait_name;
        if(tr.is_none() || !tr.get().is_simple()){
            continue;
        }
        if(!tr.get().name().eq(trait_name)){
            continue;
        }
        if(imp.info.type.is_simple() && imp.info.type.name().eq(decl.type.name())){
            return true;
        }
    }
    return false;
}

func generate_derive(r: Resolver*, decl: Decl*, unit: Unit*, name: str): Impl{
    if(name.eq("Debug")){
        return generate_debug(decl, unit);
    }
    if(name.eq("Display")){
        return generate_display(decl, unit);
    }
    if(name.eq("Drop")){
        return generate_drop(decl, unit);
    }
    if(name.eq("Clone")){
        return generate_clone(r, decl, unit);
    }
    if(name.eq("Drop")){
        r.err(decl.line, "drop is auto impl");
    }
    r.err(decl.line, format("generate_derive decl: {:?} der: '{}'", decl.type, name));
    std::unreachable!();
}

func parse_stmt(input: String, unit: Unit*, line: i32): Stmt{
    let parser = Parser::from_string(input, line);
    parser.unit = Option::new(unit);
    let res = parser.parse_stmt();
    return res;
}
func parse_expr(input: String, unit: Unit*, line: i32): Expr{
    let parser = Parser::from_string(input, line);
    parser.unit = Option::new(unit);
    let res = parser.parse_expr();
    return res;
}

func make_impl_m(m: Method*, decl: Decl*, trait_name: str): Impl{
    m.parent = Parent::Impl{make_info(decl, trait_name)};
    m.path = decl.path.clone();
    m.body = Option::new(Block::new(decl.line, decl.line));
    return make_impl(decl, trait_name);
}

//A field that is a plain value is *copied* instead of cloned: primitives
//(bool, i8..u64, f32/f64), `str` and slices (views, they never own), and --
//when the declaration is not generic -- any type with no drop glue (a struct of
//values is itself a value in x, so its bytes can be copied). Only owners need
//Clone::clone: String and friends, a #drop struct, and in a *generic*
//declaration a type parameter or a type built from one (the instantiation
//decides whether it owns, so those stay on clone()).
//Pre-fix: every non-pointer field went through `.clone()`, and std has Clone
//impls only for i8..u64 and String, so `struct S{ s: str; }` + #derive(Clone)
//did not compile ("no such method str::clone(str)").
func is_clone_copy(decl: Decl*, helper: DropHelper*, type: Type*): bool{
    if(type.is_prim() || type.is_str() || type.is_slice()){
        return true;
    }
    if(decl.is_generic){
        return false;
    }
    return !helper.is_drop_type(type);
}

func generate_clone(r: Resolver*, decl: Decl*, unit: Unit*): Impl{
    let line = decl.line;
    let helper = DropHelper::new(r);
    let body = Block::new(decl.line, decl.line);
    if(decl.base.is_some()){
        body.list.add(parse_stmt(format("Clone::clone(self as {:?}*);", decl.base.get()), unit, decl.line));
    }
    match decl{
        Decl::Enum(variants)=>{
            for ev in variants{
                let then = Block::new(line, line);
                for fd in &ev.fields{
                    if(fd.type.is_pointer()){
                        //then.list.add(parse_stmt(format("printf(\"{}=%p *=%d\\n\", *&fd.name);", &fd.name, &fd.name, &fd.name), unit, line));
                        //then.list.add(parse_stmt(format("let __{} = {};", &fd.name, &fd.name), unit, line));
                    }else if(is_clone_copy(decl, &helper, &fd.type)){
                        //plain value: the if-let binding is a pointer to the
                        //payload, so deref-copy it
                        then.list.add(parse_stmt(format("let __{} = *{};", fd.name.get(), fd.name.get()), unit, line));
                    }else{
                        then.list.add(parse_stmt(format("let __{} = {}.clone();", fd.name.get(), fd.name.get()), unit, line));
                    }
                }
                let str = Fmt::new();
                str.print("return ");
                str.print(&decl.type);
                str.print("::");
                str.print(&ev.name);
                if(!ev.fields.empty()){
                    str.print("{");
                    let i = 0;
                    for fd in &ev.fields{
                        if(i > 0){
                            str.print(", ");
                        }
                        str.print(fd.name.get());
                        str.print(": ");
                        if(fd.type.is_pointer()){
                            str.print("*");
                            str.print(fd.name.get());
                        }else{
                            str.print("__");
                            str.print(fd.name.get());
                        }
                        ++i;
                    }
                    str.print("};");
                }else{
                    str.print(";");
                }
                let return_stmt = parse_stmt(str.unwrap(), unit, line);
                then.list.add(return_stmt);

                let self_id = unit.node(line);
                let block_id = unit.node(line);
                let vt = Simple::new(decl.type.clone(), ev.name.str()).into(decl.line);
                let is = IfLet{
                    type: vt,
                    args: List<ArgBind>::new(),
                    rhs: Expr::Name{.self_id, "self".str()},
                    then: Box::new(Body::Block{.block_id, then}),
                    else_stmt: Ptr<Body>::new()
                };
                for fd in &ev.fields{
                    let arg_id = unit.node(line);
                    is.args.add(ArgBind{.arg_id, name: fd.name.get().clone()});
                }
                let iflet_id = unit.node(line);
                body.list.add(Expr::IfLet{.iflet_id, Box::new(is)}.into_stmt());
            }
            body.list.add(parse_stmt("panic(\"unreacheable\");".str(), unit, line));
        },
        Decl::Struct(fields)=>{
            for fd in fields{
                if(fd.type.is_pointer() || is_clone_copy(decl, &helper, &fd.type)){
                    //let <name> = self.<name>;  (pointer or plain value: a copy)
                    let clone_stmt = parse_stmt(format("let {} = self.{};", fd.name.get(), fd.name.get()), unit, line);
                    body.list.add(clone_stmt);
                }else{
                    //let <name> = self.<name>.clone();
                    let clone_stmt = parse_stmt(format("let {} = self.{}.clone();", fd.name.get(), fd.name.get()), unit, line);
                    body.list.add(clone_stmt);
                }
            }
            let str = Fmt::new();
            str.print("return ");
            str.print(&decl.type);
            str.print("{");
            let i = 0;
            for fd in fields{
                if(i > 0){
                    str.print(", ");
                }
                str.print(fd.name.get());
                str.print(": ");
                str.print(fd.name.get());
                ++i;
            }
            str.print("};");
            let return_stmt = parse_stmt(str.unwrap(), unit, line);
            body.list.add(return_stmt);
        },
        Decl::TupleStruct(fields)=>{
            panic("todo");
        }
    }
    let m = Method::new(unit.node(decl.line), "clone".str(), decl.type.clone());
    m.is_generic = decl.is_generic;
    let prm = Param{
        .unit.node(decl.line),
        name: "self".str(),
        type: decl.type.clone().toPtr(),
        is_self: true,
        is_deref: false,
        is_captured: false
    };
    m.self = Option::new(prm);
    m.parent = Parent::Impl{make_info(decl, "Clone")};
    m.path = unit.path.clone();
    m.body = Option::new(body);
    //print("mlone={:?}\n", &m);
    let imp = make_impl(decl, "Clone");
    imp.methods.add(m);
    //print("clone={}\n", &imp);
    return imp;
}

func generate_drop(decl: Decl*, unit: Unit*): Impl{
    //print("generate_drop {}\n", decl.type);
    let line = decl.line;
    let body = Block::new(line, line);
    if(decl.base.is_some()){
        //Drop::drop(ptr::deref!(self as <Base>*));
        body.list.add(parse_stmt(format("Drop::drop(ptr::deref!(self as {:?}*));", decl.base.get()), unit, line));
    }
    match decl{
        Decl::Enum(variants)=>{
            for(let i = 0;i < variants.len();++i){
                let ev = variants.get(i);
                let vt = Simple::new(decl.type.clone(), ev.name.str()).into(decl.line);
                let then = Block::new(line, line);

                for(let j = 0;j < ev.fields.len();++j){
                    let fd = ev.fields.get(j);
                    //Drop::drop({fd.name})
                    let drop_stmt = parse_stmt(format("Drop::drop({});", fd.name.get()), unit, line);
                    then.list.add(drop_stmt);
                }
                then.list.add(parse_stmt("return;".str(), unit, line));

                let self_id = unit.node(line);
                let block_id = unit.node(line);
                let iflet_id = unit.node(line);
                let iflet = IfLet{
                    type: vt,
                    args: List<ArgBind>::new(),
                    rhs: Expr::Name{.self_id, "self".str()},
                    then: Box::new(Body::Block{.block_id, then}),
                    else_stmt: Ptr<Body>::new()
                };
                for(let j = 0;j < ev.fields.len();++j){
                    let fd = ev.fields.get(j);
                    let arg_id = unit.node(line);
                    iflet.args.add(ArgBind{.arg_id, name: fd.name.get().clone()});
                }
                body.list.add(Expr::IfLet{.iflet_id, Box::new(iflet)}.into_stmt());
            }
        },
        Decl::Struct(fields)=>{
            for(let i = 0;i < fields.len();++i){
                let fd = fields.get(i);
                if(!is_struct(&fd.type)) continue;
                //self.{fd.name}.drop();
                if(fd.name.is_some()){
                    let drop_stmt = parse_stmt(format("Drop::drop(self.{});", fd.name.get()), unit, line);
                    body.list.add(drop_stmt);
                }else{
                    let drop_stmt = parse_stmt(format("Drop::drop(self.{});", i), unit, line);
                    body.list.add(drop_stmt);
                }
            }
        },
        Decl::TupleStruct(fields)=>{
            panic("todo");
        }
    }
    let m = Method::new(unit.node(line), "drop".str(), Type::new("void"));
    m.is_generic = decl.is_generic;
    m.self = Option::new(Param{.unit.node(line), "self".str(), decl.type.clone(), true, true, false});
    m.parent = Parent::Impl{make_info(decl, "Drop")};
    m.path = unit.path.clone();
    m.body = Option::new(body);
    let imp = make_impl(decl, "Drop");
    imp.methods.add(m);
    return imp;
}
//B2: manual Drop keeps its body; append derived frees for the drop-typed
//struct fields the body does NOT already handle (side-effect-only customs
//get all of them). Whole-self use keeps full manual responsibility; naming
//a field (self.f...) suppresses only that field. Enums keep full manual
//responsibility. Idempotent: an appended `self.f` marks f touched, so a
//re-run skips it.
func augment_manual_drop(r: Resolver*, decl: Decl*, unit: Unit*){
    if(!(decl is Decl::Struct)){
        return;
    }
    let helper = DropHelper::new(r);
    let imp = helper.find_drop_impl(decl);
    if(imp.methods.empty()){
        return;
    }
    let m = imp.methods.get(0);
    if(m.body.is_none()){
        return;
    }
    let scan = DropScan{touched: false, fields: Map<String, bool>::new()};
    r.scan_drop_body(&scan, m.body.get());
    //Whole-self use (bare self, casts, helpers, lambdas) keeps full manual
    //responsibility (frees can hide behind it); otherwise only the fields
    //the body names are taken as freed, and the rest still get recursion.
    if(scan.touched){
        return;
    }
    if let Decl::Struct(fields) = decl{
        for(let i = 0;i < fields.len();++i){
            let fd = fields.get(i);
            if(!is_struct(&fd.type)){
                continue;
            }
            if(!fd.name.is_some()){
                continue;
            }
            if(scan.fields.contains(fd.name.get())){
                continue;
            }
            let stmt = parse_stmt(format("Drop::drop(self.{});", fd.name.get()), unit, decl.line);
            m.body.get().list.add(stmt);
        }
    }
}

//The shared body of #derive(Debug) and #derive(Display): both dump a value
//as Type{field: value} / Type::Variant(field, ...) through the trait's
//printer (Debug::debug / Display::fmt). #derive(Display) is an opt-in default
//dump for `{}`; handle_attr skips it when the unit already has a hand-written
//Display (has_trait_impl), so an explicit impl is never competed with.
func generate_debug(decl: Decl*, unit: Unit*): Impl{
    return generate_printer(decl, unit, "Debug", "debug", "Debug::debug", "std::debug", "std::debug2");
}

func generate_display(decl: Decl*, unit: Unit*): Impl{
    return generate_printer(decl, unit, "Display", "fmt", "Display::fmt", "std::display", "std::display2");
}

func generate_printer(decl: Decl*, unit: Unit*, trait_name: str, method_name: str, call_path: str, generic_helper: str, generic_helper2: str): Impl{
    let imp = make_impl(decl, trait_name);
    let line = decl.line;
    let m = Method::new(unit.node(line), method_name.str(), Type::new("void"), unit.path.clone());
    m.self = Option::new(Param{.unit.node(line), "self".str(), decl.type.clone().toPtr(), true, false, false});
    m.params.add(Param{.unit.node(line), "f".str(), Type::new("Fmt").toPtr(), false, false, false});
    m.parent = Parent::Impl{make_info(decl, trait_name)};
    m.is_generic = decl.is_generic;
    let body = Block::new(line, line);
    match decl{
        Decl::Enum(variants)=>{
            for(let i = 0;i < variants.len();++i){
                let ev = variants.get(i);
                let vt = Simple::new(decl.type.clone(), ev.name.str()).into(line);
                let then = Block::new(line, line);

                //f.print({decl.type}::{ev.name})
                then.list.add(parse_stmt(format("f.print(std::print_type<{:?}>());", &decl.type), unit, line));
                then.list.add(parse_stmt(format("f.print(\"::{}\");", &ev.name), unit, line));
                if(ev.fields.len() > 0){
                    if(ev.is_tuple){
                        then.list.add(parse_stmt("f.print(\"(\");".str(), unit, line));
                    }else{
                        then.list.add(parse_stmt("f.print(\"{\");".str(), unit, line));
                    }
                    for(let j = 0;j < ev.fields.len();++j){
                        let fd = ev.fields.get(j);
                        if(j > 0){
                            then.list.add(parse_stmt("f.print(\", \");".str(), unit, line));
                        }
                        /*if(fd.name.is_some()){
                            then.list.add(parse_stmt(format("f.print(\"{}: \");", fd.name.get()), unit, line));
                            then.list.add(parse_stmt(format("debug_member!(*{}, f);", fd.name.get()), unit, line));
                        }else{
                            //then.list.add(parse_stmt(format("f.print(\"{}: \");", j), unit, line));
                            then.list.add(parse_stmt(format("debug_member!(*_{}, f);", j), unit, line));
                        }*/
                        //print("then={:?}\n", then.list.last());
                        then.list.add(parse_stmt(format("f.print(\"{}: \");", fd.name.get()), unit, line));
                        if(fd.type.is_pointer()){
                            //print hex based address
                            //i64::debug_hex(<fd.name> as u64, f);
                            then.list.add(parse_stmt(format("i64::debug_hex({} as u64, f);", fd.name.get()), unit, line));
                        }else{
                            if(decl.is_generic){
                                then.list.add(parse_stmt(format("{}({}, f);", generic_helper, fd.name.get()), unit, line));
                            }else{
                                //{fd.name}.debug(f);
                                //already ptr from if let arg
                                then.list.add(parse_stmt(format("{}({}, f);", call_path, fd.name.get()), unit, line));
                            }
                        }
                    }
                    if(ev.is_tuple){
                        then.list.add(parse_stmt("f.print(\")\");".str(), unit, line));
                    }else{
                        then.list.add(parse_stmt("f.print(\"}\");".str(), unit, line));
                    }
                }
                let self_id = unit.node(line);
                let block_id = unit.node(line);
                let is = IfLet{
                    type: vt,
                    args: List<ArgBind>::new(),
                    rhs: Expr::Name{.self_id, "self".str()},
                    then: Box::new(Body::Block{.block_id, then}),
                    else_stmt: Ptr<Body>::new()
                };
                for(let j = 0;j < ev.fields.len();++j){
                    let fd = ev.fields.get(j);
                    let arg_id = unit.node(line);
                    if(fd.name.is_some()){
                        is.args.add(ArgBind{.arg_id, name: fd.name.get().clone()});
                    }else{
                        is.args.add(ArgBind{.arg_id, name: format("_{}", i)});
                    }
                }
                let iflet_id = unit.node(line);
                body.list.add(Expr::IfLet{.iflet_id, Box::new(is)}.into_stmt());
            }
        },
        Decl::Struct(fields)=>{
            //f.print(<decl.type.print()>)
            body.list.add(parse_stmt(format("f.print(std::print_type<{:?}>());", &decl.type), unit, line));
            body.list.add(parse_stmt("f.print(\"{\");".str(), unit, line));
            for(let i = 0;i < fields.len();++i){
                let fd = fields.get(i);
                if(i > 0){
                    body.list.add(parse_stmt(format("f.print(\", \");"), unit, line));
                }
                //f.print("<fd.name>: ");
                body.list.add(parse_stmt(format("f.print(\"{}: \");", fd.name.get()), unit, line));
                if(fd.type.is_pointer()){
                    //print hex based address
                    //i64::debug_hex(fd.name as u64, f);
                    body.list.add(parse_stmt(format("i64::debug_hex(self.{} as u64, f);", fd.name.get()), unit, line));
                }else{
                    if(decl.is_generic){
                        body.list.add(parse_stmt(format("{}(self.{}, f);", generic_helper2, fd.name.get()), unit, line));
                    }else{
                        //self.{fd.name}.debug(f);
                        body.list.add(parse_stmt(format("{}(&self.{}, f);", call_path, fd.name.get()), unit, line));
                    }
                }
            }
            body.list.add(parse_stmt("f.print(\"}\");".str(), unit, line));
        },
        Decl::TupleStruct(fields)=>{
            panic("todo");
        }
    }
    m.body = Option::new(body);
    imp.methods.add(m);
    //print("{}\n", imp);
    return imp;
}

//Backtrace emission for fatal paths (panic/assert), inlined as parsed
//statements: lib-less binaries cannot link prelude-defined helpers, and
//a runtime env switch would need str->i8* conversion (also unavailable),
//so traces are a build-time decision (XBACKTRACE=1). glibc execinfo is
//absent on bionic, so Termux-targeted builds omit them entirely.
func emit_backtrace(block: Block*, unit: Unit*, line: i32, id: i32){
    if(std::getenv("XTERMUX").is_some()){
        return;
    }
    if(std::getenv("XBACKTRACE").is_none()){
        return;
    }
    //one statement per parse_stmt call (it parses a single statement).
    block.list.add(parse_stmt(format!("let __bt{}_buf = [0 as u64; 64];", id), unit, line));
    block.list.add(parse_stmt(format!("let __bt{}_n = backtrace(__bt{}_buf.ptr(), 64);", id, id), unit, line));
    block.list.add(parse_stmt(format!("backtrace_symbols_fd(__bt{}_buf.ptr(), __bt{}_n, 2);", id, id), unit, line));
}

func generate_format(node: Expr*, mc: Call*, r: Resolver*) {
    if (mc.args.empty()) {
        r.err(node, "format no arg");
    }
    let fmt: Expr* = mc.args.get(0);
    let lit_opt = is_str_lit(fmt);
    if (lit_opt.is_none()) {
        r.err(node, "format arg not str literal");
    }
    let fmt_str: str = lit_opt.unwrap().str();
    /*let format_specs = ["%s", "%d", "%c", "%f", "%u", "%ld", "%lld", "%lu", "%llu", "%x", "%X"];
    for (let i = 0;i < format_specs.len();++i) {
        let fs = format_specs[i];
        if (fmt_str.contains(fs)) {
            r.err(node, format("invalid format specifier: {}", fs));
        }
    }*/
    let line = node.line;
    let info = FormatInfo::new(line);
    let block = &info.block;
    //print("macro {} id={} {}\n", node, node.id, r.unit.path);
    if (mc.args.len() == 1 && (Resolver::is_print(mc) || Resolver::is_panic(mc))) {
        //optimized print, no heap alloc, no fmt
        //printf("..")
        if (Resolver::is_panic(mc)) {
            let msg = make_panic_messsage(line, *r.curMethod.get(), Option::new(fmt_str), r);
            let tmp = normalize_quotes(msg.str());
            msg = tmp;
            block.list.add(parse_stmt(format("printf(\"{}\");", msg), &r.unit, line));
            emit_backtrace(block, &r.unit, line, node.id);
            block.list.add(parse_stmt(format("exit(1);"), &r.unit, line));
        }else{
            let msg = normalize_quotes(fmt_str);
            block.list.add(parse_stmt(format("printf(\"{}\");", msg), &r.unit, line));
        }
        r.visit_block(block);
        r.format_map.add(node.id, info);
        return;
    }
    let fmt_var_name = format("f_{}", node.id);
    let var_stmt = parse_stmt(format("let {} = Fmt::new();", &fmt_var_name), &r.unit, line);
    block.list.add(var_stmt);
    let pos = 0;
    let arg_idx = 1;//skip fmt_str
    while(pos < fmt_str.len()){
        let br_pos = fmt_str.indexOf("{", pos);
        if(br_pos == -1){
            let sub = fmt_str.substr(pos);
            let sub2 = normalize_quotes(sub);
            let st = parse_stmt(format("{}.print(\"{}\");", &fmt_var_name, sub2), &r.unit, line);
            block.list.add(st);
            break;
        }
        if(br_pos > pos){
            let sub = fmt_str.substr(pos, br_pos);
            let sub2 = normalize_quotes(sub);
            let st = parse_stmt(format("{}.print(\"{}\");", &fmt_var_name, sub2), &r.unit, line);
            block.list.add(st);
        }
        // '{' escaped as '{{'
        if(fmt_str.get(br_pos + 1) == '{'){
            let st = parse_stmt(format("{}.print(\"{{\");", &fmt_var_name), &r.unit, line);
            block.list.add(st);
            pos = br_pos + 2;
            continue;
        }
        let br_end = fmt_str.indexOf("}", br_pos);
        if(br_end == -1){
            r.err(node, "invalid format no closing }");
        }
        let debug = false;
        let func_name: String = "Display::fmt".str();
        if(fmt_str.starts_with("{:?", br_pos)){
            debug = true;
            func_name = "Debug::debug".str();
            pos = br_pos + 3;
        }else if(fmt_str.starts_with("{::", br_pos)){
            //Custom printer: `{::TraitName}` calls that trait's printer
            //(`TraitName::fmt(<arg>, &f)`) instead of Display::fmt /
            //Debug::debug -- a user trait with `func fmt(self, f: Fmt*)`
            //(doc/todo). The argument is positional, like `{}`; the name is
            //used verbatim as a path prefix.
            let name = fmt_str.substr(br_pos + 3, br_end);
            if(name.len() == 0){
                r.err(node, "invalid format custom printer");
            }
            func_name = format("{}::fmt", name);
            pos = br_end;
        }else{
            pos = br_pos + 1;
        }
        if(pos < br_end){
            //named arg
            let arg_str = fmt_str.substr(pos, br_end);
            let expr = parse_expr(arg_str.owned(), &r.unit, line);
            let arg_rt = r.visit(&expr);
            if(is_struct(&arg_rt.type)){
                //coerce automatically
                let dbg_st = parse_stmt(format("{}(&{:?}, &{});", func_name, arg_str, fmt_var_name), &r.unit, line);
                block.list.add(dbg_st);
            }else{
                let dbg_st = parse_stmt(format("{}({:?}, &{});", func_name, arg_str, fmt_var_name), &r.unit, line);
                block.list.add(dbg_st);
            }
        }else{
            if(arg_idx >= mc.args.len()){
                r.err(node, "format specifier not matched");
            }
            let arg = mc.args.get(arg_idx);
            let argt = r.visit(arg);
            if(is_struct(&argt.type)){
                //coerce automatically
                let dbg_st = parse_stmt(format("{}(&{:?}, &{});", func_name, arg, fmt_var_name), &r.unit, line);
                block.list.add(dbg_st);
            }else{
                let dbg_st = parse_stmt(format("{}({:?}, &{});", func_name, arg, fmt_var_name), &r.unit, line);
                block.list.add(dbg_st);
            }
            ++arg_idx;
        }
        pos = br_end + 1;
        // argt.drop();
    }
    if(arg_idx < mc.args.len()){
        r.err(node, format("format arg not matched in specifier {:?}", mc.args.get(arg_idx)));
    }
    if(Resolver::is_print(mc)){
        //..f.buf.print();
        let print_st = parse_stmt(format("String::print(&{}.buf);", &fmt_var_name), &r.unit, line);
        block.list.add(print_st);
        //..Drop::drop(f);
        let drop_st = parse_stmt(format("Drop::drop({});", &fmt_var_name), &r.unit, line);
        block.list.add(drop_st);
        r.visit_block(block);
    }else if(Resolver::is_panic(mc)){
        //.."<method:line>".print();
        let pos_info = make_panic_messsage(line, *r.curMethod.get(), Option<str>::new(), r);
        let pos_info_st = parse_stmt(format("\"{}\".print();", &pos_info), &r.unit, line);
        block.list.add(pos_info_st);
        //..f.buf.print();
        let print_st = parse_stmt(format("{}.buf.println();", &fmt_var_name), &r.unit, line);
        block.list.add(print_st);
        //..Drop::drop(f);
        let drop_st = parse_stmt(format("Drop::drop({});", &fmt_var_name), &r.unit, line);
        block.list.add(drop_st);
        emit_backtrace(block, &r.unit, line, node.id);
        block.list.add(parse_stmt("exit(1);".str(), &r.unit, line));
        //..print("block={}\n", block);
        r.visit_block(block);
    }else if(Resolver::is_format(mc)){
        //..f.unwrap()
        let unwrap_expr = parse_expr(format("{}.unwrap()", &fmt_var_name), &r.unit, line);
        block.return_expr.set(unwrap_expr);
        let tmp = r.visit_block(block);
        //the emitter needs the resolved result type to drop a discarded
        //result (the format call's own RType is a bare, decl-less String).
        info.rt = r.visit(block.return_expr.get());
    }else{
        r.err(node, "generate_format");
    }
    r.format_map.add(node.id, info);
}

//Macro names the resolver expands itself in visit_macrocall: a user macro with
//one of these names would be shadowed (and the ownership pass keys on them).
func is_builtin_macro_name(name: str): bool{
    return name.eq("format") || name.eq("print") || name.eq("panic") || name.eq("debug_member");
}

const MAX_MACRO_DEPTH: i32 = 64;

//`Expr` is the syntax-slot marker: a parameter declared with it is replaced by
//a copy of the argument at every use. Any other declared type makes it a value
//parameter (see expand_user_macro).
func is_expr_param(prm: MacroParam*): bool{
    return prm.type.is_some() && prm.type.get().print().eq("Expr");
}

//`name!(a, b)` where `name` is a `macro name(p1: Expr, p2: i32)` (own unit or
//an imported one). Expanded per call site into a block:
//- each *value* parameter (`p: i32`) is bound once, in declaration order, by
//  `let p: i32 = <arg>;` at the top of the expansion: typed, evaluated once,
//  and the argument resolves in the caller's scope (so a body local cannot
//  capture it). When the parameter's own name is already live at the call site
//  (x has no shadowing, and the argument is often a variable of that name:
//  `take!(s)`) the binding takes a fresh name and the body's references are
//  renamed with it (rename_map);
//- each `Expr` parameter is a syntax slot: every reference to it in the body is
//  replaced by a copy of the argument expression (a twice-used argument is
//  evaluated twice, which the ownership pass reports as a use-after-move when
//  it moves);
//- the body is hygienic for the names *it* declares (`hygienic: true`): let/for
//  variables, for-each and lambda parameters and match/if-let bindings are
//  alpha-renamed per call site, so a macro may use `t`, `i` or `res` without
//  colliding with the caller's variables, and a substituted argument cannot be
//  captured by a body local of the same name. A body name that is *not*
//  declared (and is not a parameter) is a free name: it resolves at the call
//  site, but a live caller local of that spelling is an error (see the guard
//  below) instead of a silent capture; a nested binder's spelling keeps its
//  fresh name to the end of the body.
//AstCopier re-issues node ids, so two calls of one macro -- and two uses of one
//argument -- never share nodes. The block is then resolved like any other
//generated code and the emitter picks it up through format_map, the same
//channel the builtin macros use. A trailing expression in the body makes the
//macro an expression macro of the inferred result type.
func expand_user_macro(node: Expr*, call: MacroCall*, mac: Macro*, r: Resolver*): RType{
    //a list parameter (`xs: Expr...`) takes every remaining argument; it must
    //be the last parameter and there can be only one
    let list_cnt = 0;
    for(let i = 0;i < mac.params.len();++i){
        let prm = mac.params.get(i);
        if(prm.list){
            list_cnt += 1;
            if(i + 1 != mac.params.len()){
                r.err(node, format("macro {} list parameter must be last", mac.name));
            }
            if(!is_expr_param(prm)){
                r.err(node, format("macro {} list parameter must be an Expr", mac.name));
            }
        }
    }
    if(list_cnt > 1){
        r.err(node, format("macro {} has more than one list parameter", mac.name));
    }
    let fixed = mac.params.len();
    if(list_cnt > 0){
        fixed -= 1;
    }
    if(list_cnt == 0 && call.args.len() != mac.params.len()){
        r.err(node, format!("macro {} expects {} args, got {}", mac.name, mac.params.len(), call.args.len()));
    }
    if(list_cnt > 0 && call.args.len() < fixed){
        r.err(node, format!("macro {} expects at least {} args, got {}", mac.name, fixed, call.args.len()));
    }
    if(r.macro_depth >= MAX_MACRO_DEPTH){
        r.err(node, format!("macro expansion too deep (recursive macro {})", mac.name));
    }
    let args = HashMap<String, Expr*>::new();
    let renames = HashMap<String, String>::new();
    let info = FormatInfo::new(node.line);
    for(let i = 0;i < fixed;++i){
        let prm = mac.params.get(i);
        if(is_expr_param(prm)){
            args.add(prm.name.clone(), call.args.get(i));
        }else{
            //value parameter: bound once, in declaration order, with its
            //declared type. The binding keeps the parameter's name when that
            //name is free at the call site; otherwise (x has no shadowing, and
            //the argument is often a variable of the same name: `take!(s)`) it
            //is bound under a fresh name and the body's references are renamed.
            let bind_name = if(r.has_live_name(&prm.name)){ format!("{}_{}", prm.name, node.id) } else { prm.name.clone() };
            if(!bind_name.eq(&prm.name)){
                renames.add(prm.name.clone(), bind_name.clone());
            }
            let bind = format!("let {}: {} = {:?};", bind_name, prm.type.get().print(), call.args.get(i));
            info.block.list.add(parse_stmt(bind, &r.unit, node.line));
        }
    }
    let types = HashMap<String, Type>::new();
    let copier = AstCopier::new(&types, &r.unit, args, renames);
    //hygienic: names the body declares are alpha-renamed per call site
    copier.hygienic = true;
    copier.rename_id = node.id;
    if(list_cnt > 0){
        //`$( ... )*` fills in `$xs` per element while the body is copied
        let elems = List<Expr*>::new();
        for(let i = fixed;i < call.args.len();++i){
            elems.add(call.args.get(i));
        }
        copier.repeat_param = Option::new(mac.params.get(fixed).name.clone());
        copier.repeat_elems = elems;
    }
    //visit_stmts splices `$( ... )*` (a repetition cannot stay a statement:
    //it expands to one copy of its body per element)
    copier.visit_stmts(&mac.body.list, &info.block.list);
    if(mac.body.return_expr.is_some()){
        info.block.return_expr.set(copier.visit(mac.body.return_expr.get()));
    }
    //problems the copier could not report itself (bad `$name`, nested
    //repetition, bare list parameter)
    for e in &copier.errors{
        r.err(node, e.clone());
    }
    //Definition-site guard: a free body name is resolved at the call site (the
    //copy is visited in the caller's scopes). If the caller happens to have a
    //local of that name, the body would silently read it -- x has no shadowing
    //and the spelling matches, so there is no diagnostic anywhere else. Such a
    //read has to be explicit: pass it as a parameter.
    for free in &copier.free_names{
        if(r.has_live_local(free)){
            r.err(node, format("macro {} body name '{}' resolves to a local at this call site; pass it as a parameter or declare it in the body", mac.name, *free));
        }
    }
    r.newScope();
    r.macro_depth += 1;
    r.visit_block(&info.block);
    r.macro_depth -= 1;
    r.dropScope();
    if(info.block.return_expr.is_some()){
        //the emitter needs the resolved result type to drop a discarded result
        info.rt = r.visit(info.block.return_expr.get());
    }
    let res = info.rt.clone();
    r.format_map.add(node.id, info);
    return res;
}

func generate_format(node: Expr*, mc: MacroCall*, r: Resolver*) {
    if (mc.args.empty()) {
        r.err(node, "format no arg");
    }
    let fmt: Expr* = mc.args.get(0);
    let lit_opt = is_str_lit(fmt);
    if (lit_opt.is_none()) {
        r.err(node, "format arg not str literal");
    }
    let fmt_str: str = lit_opt.unwrap().str();
    /*let format_specs = ["%s", "%d", "%c", "%f", "%u", "%ld", "%lld", "%lu", "%llu", "%x", "%X"];
    for (let i = 0;i < format_specs.len();++i) {
        let fs = format_specs[i];
        if (fmt_str.contains(fs)) {
            r.err(node, format("invalid format specifier: {}", fs));
        }
    }*/
    let line = node.line;
    let info = FormatInfo::new(line);
    let block = &info.block;
    //print("macro {} id={} {}\n", node, node.id, r.unit.path);
    if (mc.args.len() == 1 && (Resolver::is_print(mc) || Resolver::is_panic(mc))) {
        //optimized print, no heap alloc, no fmt
        //printf("..")
        if (Resolver::is_panic(mc)) {
            let msg = make_panic_messsage(line, *r.curMethod.get(), Option::new(fmt_str), r);
            let tmp = normalize_quotes(msg.str());
            msg = tmp;
            block.list.add(parse_stmt(format("printf(\"{}\");", msg), &r.unit, line));
            emit_backtrace(block, &r.unit, line, node.id);
            block.list.add(parse_stmt(format("exit(1);"), &r.unit, line));
        }else{
            let msg = normalize_quotes(fmt_str);
            block.list.add(parse_stmt(format("printf(\"{}\");", msg), &r.unit, line));
        }
        r.visit_block(block);
        r.format_map.add(node.id, info);
        return;
    }
    let fmt_var_name = format("f_{}", node.id);
    let var_stmt = parse_stmt(format("let {} = Fmt::new();", &fmt_var_name), &r.unit, line);
    block.list.add(var_stmt);
    let pos = 0;
    let arg_idx = 1;//skip fmt_str
    while(pos < fmt_str.len()){
        let br_pos = fmt_str.indexOf("{", pos);
        if(br_pos == -1){
            let sub = fmt_str.substr(pos);
            let sub2 = normalize_quotes(sub);
            let st = parse_stmt(format("{}.print(\"{}\");", &fmt_var_name, sub2), &r.unit, line);
            block.list.add(st);
            break;
        }
        if(br_pos > pos){
            let sub = fmt_str.substr(pos, br_pos);
            let sub2 = normalize_quotes(sub);
            let st = parse_stmt(format("{}.print(\"{}\");", &fmt_var_name, sub2), &r.unit, line);
            block.list.add(st);
        }
        if(fmt_str.get(br_pos + 1) == '{'){
            let st = parse_stmt(format("{}.print(\"{{\");", &fmt_var_name), &r.unit, line);
            block.list.add(st);
            pos = br_pos + 2;
            continue;
        }
        let br_end = fmt_str.indexOf("}", br_pos);
        if(br_end == -1){
            r.err(node, "invalid format no closing }");
        }
        let debug = false;
        let func_name: String = "Display::fmt".str();
        if(fmt_str.starts_with("{:?", br_pos)){
            debug = true;
            func_name = "Debug::debug".str();
            pos = br_pos + 3;
        }else if(fmt_str.starts_with("{::", br_pos)){
            //Custom printer: `{::TraitName}` calls that trait's printer
            //(`TraitName::fmt(<arg>, &f)`) instead of Display::fmt /
            //Debug::debug -- a user trait with `func fmt(self, f: Fmt*)`
            //(doc/todo). The argument is positional, like `{}`; the name is
            //used verbatim as a path prefix.
            let name = fmt_str.substr(br_pos + 3, br_end);
            if(name.len() == 0){
                r.err(node, "invalid format custom printer");
            }
            func_name = format("{}::fmt", name);
            pos = br_end;
        }else{
            pos = br_pos + 1;
        }
        if(pos < br_end){
            //named arg
            let arg_str = fmt_str.substr(pos, br_end);
            let expr = parse_expr(arg_str.owned(), &r.unit, line);
            let arg_rt = r.visit(&expr);
            if(is_struct(&arg_rt.type)){
                //coerce automatically
                let dbg_st = parse_stmt(format("{}(&{:?}, &{});", func_name, arg_str, fmt_var_name), &r.unit, line);
                block.list.add(dbg_st);
            }else{
                let dbg_st = parse_stmt(format("{}({:?}, &{});", func_name, arg_str, fmt_var_name), &r.unit, line);
                block.list.add(dbg_st);
            }
        }else{
            if(arg_idx >= mc.args.len()){
                r.err(node, "format specifier not matched");
            }
            let arg = mc.args.get(arg_idx);
            let argt = r.visit(arg);
            if(is_struct(&argt.type)){
                //coerce automatically
                let dbg_st = parse_stmt(format("{}(&{:?}, &{});", func_name, arg, fmt_var_name), &r.unit, line);
                block.list.add(dbg_st);
            }else{
                let dbg_st = parse_stmt(format("{}({:?}, &{});", func_name, arg, fmt_var_name), &r.unit, line);
                block.list.add(dbg_st);
            }
            ++arg_idx;
        }
        pos = br_end + 1;
        // argt.drop();
    }
    if(arg_idx < mc.args.len()){
        r.err(node, format("format arg not matched in specifier {:?}", mc.args.get(arg_idx)));
    }
    if(Resolver::is_print(mc)){
        //..f.buf.print();
        let print_st = parse_stmt(format("String::print(&{}.buf);", &fmt_var_name), &r.unit, line);
        block.list.add(print_st);
        //..Drop::drop(f);
        let drop_st = parse_stmt(format("Drop::drop({});", &fmt_var_name), &r.unit, line);
        block.list.add(drop_st);
        r.visit_block(block);
    }else if(Resolver::is_panic(mc)){
        //.."<method:line>".print();
        let pos_info = make_panic_messsage(line, *r.curMethod.get(), Option<str>::new(), r);
        let pos_info_st = parse_stmt(format("\"{}\".print();", &pos_info), &r.unit, line);
        block.list.add(pos_info_st);
        //..f.buf.print();
        let print_st = parse_stmt(format("{}.buf.println();", &fmt_var_name), &r.unit, line);
        block.list.add(print_st);
        //..Drop::drop(f);
        let drop_st = parse_stmt(format("Drop::drop({});", &fmt_var_name), &r.unit, line);
        block.list.add(drop_st);
        emit_backtrace(block, &r.unit, line, node.id);
        block.list.add(parse_stmt("exit(1);".str(), &r.unit, line));
        //..print("block={}\n", block);
        r.visit_block(block);
    }else if(Resolver::is_format(mc)){
        //..f.unwrap()
        let unwrap_expr = parse_expr(format("{}.unwrap()", &fmt_var_name), &r.unit, line);
        block.return_expr.set(unwrap_expr);
        let tmp = r.visit_block(block);
        //the emitter needs the resolved result type to drop a discarded
        //result (the format call's own RType is a bare, decl-less String).
        info.rt = r.visit(block.return_expr.get());
    }else{
        r.err(node, "generate_format");
    }
    r.format_map.add(node.id, info);
}

//replace non escaped quotes into escaped ones
func normalize_quotes(s: str): String{
    let res = String::new();
    for(let i = 0;i < s.len();++i){
        let c = s.get(i);
        if(c == '\\'){
            res.append(c);
            res.append(s.get(i + 1));
            i += 1;
            continue;
        }
        if(c == '\"' || c == '\\'){
            res.append('\\' as i8);
        }
        res.append(c);
    }
    return res;
}


func make_panic_messsage(line: i32, method: Method*, s: Option<str>, r: Resolver*): String {
    let message = Fmt::new("panic ".str());
    message.print(r.ctx.display_path(method.path.str()));
    message.print(":");
    message.print(&line);
    message.print(" ");
    let method_sig = printMethod(method);
    message.print(method_sig.str());
    if (s.is_some()) {
        message.print("\n");
        message.print(s.get());
    }
    message.print("\n");
    return message.unwrap();
}

func generate_assert(node: Expr*, mc: Call*, r: Resolver*){
    if(mc.args.len() != 1){
        r.err(node, format("assert expects one element got: {}", mc.args.len()));
    }
    let arg = mc.args.get(0);
    if(!r.is_condition(arg)){
        r.err(node, format("assert expr is not bool: {:?}", node));
    }
    let line = node.line;
    let info = FormatInfo::new(line);
    let block = &info.block;
    let arg_str = arg.print();
    let arg_norm: String = normalize_quotes(arg_str.str());
    let method_sig = printMethod(r.curMethod.unwrap());
    //let str = format("if(!({:?})){\nprintf(\"{}:{}\nassertion `{}` failed in {}\n\");exit(1);\n}", arg, r.curMethod.unwrap().path, node.line, arg_norm, method_sig);
    let fm = Fmt::new(format("if(!({:?})){{\n", arg));
    fm.print(format("printf(\"{}:{}\nassertion `{}` failed in {}\n\");", r.ctx.display_path(r.curMethod.unwrap().path.str()), node.line, arg_norm, method_sig));
    if(std::getenv("XTERMUX").is_none() && std::getenv("XBACKTRACE").is_some()){
      fm.print(format!("let __bta{}_buf = [0 as u64; 64];\n", node.id));
      fm.print(format!("let __bta{}_n = backtrace(__bta{}_buf.ptr(), 64);\n", node.id, node.id));
      fm.print(format!("backtrace_symbols_fd(__bta{}_buf.ptr(), __bta{}_n, 2);\n", node.id, node.id));
    }
    fm.print("exit(1);\n}");
    let str = fm.unwrap();
    //print("assert='{}'", str);
    block.list.add(parse_stmt(str, &r.unit, line));
    r.format_map.add(node.id, info);
    //print("assert {} id={} path={}\nblock={}\n", node, node.id, r.unit.path, block);
    r.visit_block(block);
}