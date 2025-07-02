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

import parser/resolver
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

func generate_derive(r: Resolver*, decl: Decl*, unit: Unit*, name: str): Impl{
    if(name.eq("Debug")){
        return generate_debug(decl, unit);
    }
    if(name.eq("Drop")){
        return generate_drop(decl, unit);
    }
    if(name.eq("Clone")){
        return generate_clone(decl, unit);
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
    parser.drop();
    return res;
}
func parse_expr(input: String, unit: Unit*, line: i32): Expr{
    let parser = Parser::from_string(input, line);
    parser.unit = Option::new(unit);
    let res = parser.parse_expr();
    parser.drop();
    return res;
}

func make_impl_m(m: Method*, decl: Decl*, trait_name: str): Impl{
    m.parent = Parent::Impl{make_info(decl, trait_name)};
    m.path.drop();
    m.path = decl.path.clone();
    m.body = Option::new(Block::new(decl.line, decl.line));
    return make_impl(decl, trait_name);
}

func generate_clone(decl: Decl*, unit: Unit*): Impl{
    let line = decl.line;
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
                let vt = Simple::new(decl.type.clone(), ev.name.clone()).into(decl.line);
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
                if(fd.type.is_pointer()){
                    //let <name> = self.<name>;
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
        is_deref: false
    };
    m.self = Option::new(prm);
    m.parent = Parent::Impl{make_info(decl, "Clone")};
    m.path.drop();
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
                let vt = Simple::new(decl.type.clone(), ev.name.clone()).into(decl.line);
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
    m.self = Option::new(Param{.unit.node(line), "self".str(), decl.type.clone(), true, true});
    m.parent = Parent::Impl{make_info(decl, "Drop")};
    m.path.drop();
    m.path = unit.path.clone();
    m.body = Option::new(body);
    let imp = make_impl(decl, "Drop");
    imp.methods.add(m);
    return imp;
}

func generate_debug(decl: Decl*, unit: Unit*): Impl{
    let imp = make_impl(decl, "Debug");
    let line = decl.line;
    let m = Method::new(unit.node(line), "debug".str(), Type::new("void"), unit.path.clone());
    m.self = Option::new(Param{.unit.node(line), "self".str(), decl.type.clone().toPtr(), true, false});
    m.params.add(Param{.unit.node(line), "f".str(), Type::new("Fmt").toPtr(), false, false});
    m.parent = Parent::Impl{make_info(decl, "Debug")};
    m.is_generic = decl.is_generic;
    let body = Block::new(line, line);
    match decl{
        Decl::Enum(variants)=>{
            for(let i = 0;i < variants.len();++i){
                let ev = variants.get(i);
                let vt = Simple::new(decl.type.clone(), ev.name.clone()).into(line);
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
                                then.list.add(parse_stmt(format("std::debug({}, f);", fd.name.get()), unit, line));
                            }else{
                                //{fd.name}.debug(f);
                                //already ptr from if let arg
                                then.list.add(parse_stmt(format("Debug::debug({}, f);", fd.name.get()), unit, line));
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
                        body.list.add(parse_stmt(format("std::debug2(self.{}, f);", fd.name.get()), unit, line));
                    }else{
                        //self.{fd.name}.debug(f);
                        body.list.add(parse_stmt(format("Debug::debug(&self.{}, f);", fd.name.get()), unit, line));
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

func generate_format(node: Expr*, mc: Call*, r: Resolver*) {
    if (mc.args.empty()) {
        r.err(node, "format no arg");
    }
    let fmt: Expr* = mc.args.get(0);
    r.visit(fmt).drop();
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
            let msg = make_panic_messsage(line, *r.curMethod.get(), Option::new(fmt_str));
            let tmp = normalize_quotes(msg.str());
            msg.drop();
            msg = tmp;
            block.list.add(parse_stmt(format("printf(\"{}\");", msg), &r.unit, line));
            block.list.add(parse_stmt(format("exit(1);"), &r.unit, line));
            msg.drop();
        }else{
            let msg = normalize_quotes(fmt_str);
            block.list.add(parse_stmt(format("printf(\"{}\");", msg), &r.unit, line));
            msg.drop();
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
            sub2.drop();
            break;
        }
        if(br_pos > pos){
            let sub = fmt_str.substr(pos, br_pos);
            let sub2 = normalize_quotes(sub);
            let st = parse_stmt(format("{}.print(\"{}\");", &fmt_var_name, sub2), &r.unit, line);
            sub2.drop();
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
        let func_name = "Display::fmt";
        if(fmt_str.starts_with("{:?", br_pos)){
            debug = true;
            func_name = "Debug::debug";
            pos = br_pos + 3;
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
            arg_rt.drop();
            expr.drop();
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
            argt.drop();
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
        let pos_info = make_panic_messsage(line, *r.curMethod.get(), Option<str>::new());
        let pos_info_st = parse_stmt(format("\"{}\".print();", &pos_info), &r.unit, line);
        pos_info.drop();
        block.list.add(pos_info_st);
        //..f.buf.print();
        let print_st = parse_stmt(format("{}.buf.println();", &fmt_var_name), &r.unit, line);
        block.list.add(print_st);
        //..Drop::drop(f);
        let drop_st = parse_stmt(format("Drop::drop({});", &fmt_var_name), &r.unit, line);
        block.list.add(drop_st);
        block.list.add(parse_stmt("exit(1);".str(), &r.unit, line));
        //..print("block={}\n", block);
        r.visit_block(block);
    }else if(Resolver::is_format(mc)){
        //..f.unwrap()
        let unwrap_expr = parse_expr(format("{}.unwrap()", &fmt_var_name), &r.unit, line);
        block.return_expr.set(unwrap_expr);
        let tmp = r.visit_block(block);
        tmp.drop();
    }else{
        r.err(node, "generate_format");
    }
    r.format_map.add(node.id, info);
    fmt_var_name.drop();
}
func generate_format(node: Expr*, mc: MacroCall*, r: Resolver*) {
    if (mc.args.empty()) {
        r.err(node, "format no arg");
    }
    let fmt: Expr* = mc.args.get(0);
    r.visit(fmt).drop();
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
            let msg = make_panic_messsage(line, *r.curMethod.get(), Option::new(fmt_str));
            let tmp = normalize_quotes(msg.str());
            msg.drop();
            msg = tmp;
            block.list.add(parse_stmt(format("printf(\"{}\");", msg), &r.unit, line));
            block.list.add(parse_stmt(format("exit(1);"), &r.unit, line));
            msg.drop();
        }else{
            let msg = normalize_quotes(fmt_str);
            block.list.add(parse_stmt(format("printf(\"{}\");", msg), &r.unit, line));
            msg.drop();
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
            sub2.drop();
            break;
        }
        if(br_pos > pos){
            let sub = fmt_str.substr(pos, br_pos);
            let sub2 = normalize_quotes(sub);
            let st = parse_stmt(format("{}.print(\"{}\");", &fmt_var_name, sub2), &r.unit, line);
            sub2.drop();
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
        let func_name = "Display::fmt";
        if(fmt_str.starts_with("{:?", br_pos)){
            debug = true;
            func_name = "Debug::debug";
            pos = br_pos + 3;
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
            arg_rt.drop();
            expr.drop();
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
            argt.drop();
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
        let pos_info = make_panic_messsage(line, *r.curMethod.get(), Option<str>::new());
        let pos_info_st = parse_stmt(format("\"{}\".print();", &pos_info), &r.unit, line);
        pos_info.drop();
        block.list.add(pos_info_st);
        //..f.buf.print();
        let print_st = parse_stmt(format("{}.buf.println();", &fmt_var_name), &r.unit, line);
        block.list.add(print_st);
        //..Drop::drop(f);
        let drop_st = parse_stmt(format("Drop::drop({});", &fmt_var_name), &r.unit, line);
        block.list.add(drop_st);
        block.list.add(parse_stmt("exit(1);".str(), &r.unit, line));
        //..print("block={}\n", block);
        r.visit_block(block);
    }else if(Resolver::is_format(mc)){
        //..f.unwrap()
        let unwrap_expr = parse_expr(format("{}.unwrap()", &fmt_var_name), &r.unit, line);
        block.return_expr.set(unwrap_expr);
        let tmp = r.visit_block(block);
        tmp.drop();
    }else{
        r.err(node, "generate_format");
    }
    r.format_map.add(node.id, info);
    fmt_var_name.drop();
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


func make_panic_messsage(line: i32, method: Method*, s: Option<str>): String {
    let message = Fmt::new("panic ".str());
    message.print(&method.path);
    message.print(":");
    message.print(&line);
    message.print(" ");
    let method_sig = printMethod(method);
    message.print(method_sig.str());
    method_sig.drop();
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
    fm.print(format("printf(\"{}:{}\nassertion `{}` failed in {}\n\");", r.curMethod.unwrap().path, node.line, arg_norm, method_sig));
    fm.print("exit(1);\n}");
    let str = fm.unwrap();
    //print("assert='{}'", str);
    block.list.add(parse_stmt(str, &r.unit, line));
    r.format_map.add(node.id, info);
    //print("assert {} id={} path={}\nblock={}\n", node, node.id, r.unit.path, block);
    r.visit_block(block);
    arg_str.drop();
    arg_norm.drop();
    method_sig.drop();
}