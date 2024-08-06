import parser/ast
import parser/utils
import parser/printer
import parser/resolver
import parser/copier
import parser/parser
import parser/lexer
import parser/token
import parser/ownership
import std/libc
import std/map

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

func generate_derive(decl: Decl*, unit: Unit*, der: str): Impl{
    if(der.eq("Debug")){
        return generate_debug(decl, unit);
    }
    if(der.eq("Drop")){
        return generate_drop(decl, unit);
    }
    if(der.eq("Clone")){
        return generate_clone(decl, unit);
    }
    panic("generate_derive decl: {} der: '{}'", decl.type, der);
}

func parse_stmt(input: String, unit: Unit*, line: i32): Stmt{
    let parser = Parser::from_string(input, line);
    parser.unit = Option::new(unit);
    let res = parser.parse_stmt();
    Drop::drop(parser);
    return res;
}
func parse_expr(input: String, unit: Unit*, line: i32): Expr{
    let parser = Parser::from_string(input, line);
    parser.unit = Option::new(unit);
    let res = parser.parse_expr();
    Drop::drop(parser);
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
        //clone::clone(ptr::deref(self as <Base>*));
        body.list.add(parse_stmt(format("Clone::clone(self as {}*);", decl.base.get()), unit, decl.line));
    }
    
    if let Decl::Enum(variants*)=(decl){
        for ev in variants{
            let then = Block::new(line, line);
            for fd in &ev.fields{
                if(fd.type.is_pointer()){
                    then.list.add(parse_stmt(format("let __{} = {};", &fd.name, &fd.name), unit, line));
                }else{
                    then.list.add(parse_stmt(format("let __{} = {}.clone();", &fd.name, &fd.name), unit, line));
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
                    str.print(&fd.name);
                    str.print(": __");
                    str.print(&fd.name);
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
            let is = IfLet{vt, List<ArgBind>::new(), Expr::Name{.self_id, "self".str()}, Box::new(Stmt::Block{.block_id, then}), Ptr<Stmt>::new()};
            for fd in &ev.fields{
                let arg_id = unit.node(line);
                is.args.add(ArgBind{.arg_id, name: fd.name.clone(), is_ptr: is_struct(&fd.type)});
            }
            let iflet_id = unit.node(line);
            body.list.add(Stmt::IfLet{.iflet_id, is});
        }
        body.list.add(parse_stmt("panic(\"unreacheable\");".str(), unit, line));
    }else{
        let fields = decl.get_fields();
        for fd in fields{
            if(fd.type.is_pointer()){
                //let <name> = self.<name>;
                let clone_stmt = parse_stmt(format("let {} = self.{};", &fd.name, &fd.name), unit, line);
                body.list.add(clone_stmt);
            }else{
                //let <name> = self.<name>.clone();
                let clone_stmt = parse_stmt(format("let {} = self.{}.clone();", &fd.name, &fd.name), unit, line);
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
            str.print(&fd.name);
            str.print(": ");
            str.print(&fd.name);
            ++i;
        }
        str.print("};");
        let return_stmt = parse_stmt(str.unwrap(), unit, line);
        body.list.add(return_stmt);
    }
    let m = Method::new(unit.node(decl.line), "clone".str(), decl.type.clone());
    m.is_generic = decl.is_generic;
    m.self = Option::new(Param{.unit.node(decl.line),
                                name: "self".str(),
                                type: decl.type.clone().toPtr(),
                                is_self: true,
                                is_deref: false});
    m.parent = Parent::Impl{make_info(decl, "Clone")};
    m.path.drop();
    m.path = unit.path.clone();
    m.body = Option::new(body);
    let imp = make_impl(decl, "Clone");
    imp.methods.add(m);
    print("clone={}\n", &imp);
    return imp;
}

func generate_drop(decl: Decl*, unit: Unit*): Impl{
    //print("generate_drop {}\n", decl.type);
    let line = decl.line;
    let body = Block::new(line, line);
    if(decl.base.is_some()){
        //Drop::drop(ptr::deref(self as <Base>*));
        body.list.add(parse_stmt(format("Drop::drop(ptr::deref(self as {}*));", decl.base.get()), unit, line));
    }
    if let Decl::Enum(variants*)=(decl){
        for(let i = 0;i < variants.len();++i){
            let ev = variants.get_ptr(i);
            let vt = Simple::new(decl.type.clone(), ev.name.clone()).into(decl.line);
            let then = Block::new(line, line);

            for(let j = 0;j < ev.fields.len();++j){
                let fd = ev.fields.get_ptr(j);
                //Drop::drop({fd.name})
                let drop_stmt = parse_stmt(format("Drop::drop({});", &fd.name), unit, line);
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
                then: Box::new(Stmt::Block{.block_id, then}),
                else_stmt: Ptr<Stmt>::new()
            };
            for(let j = 0;j < ev.fields.len();++j){
                let fd = ev.fields.get_ptr(j);
                let arg_id = unit.node(line);
                iflet.args.add(ArgBind{.arg_id, fd.name.clone(), false});
            }
            body.list.add(Stmt::IfLet{.iflet_id, iflet});
        }
    }else{
        let fields = decl.get_fields();
        for(let i = 0;i < fields.len();++i){
            let fd = fields.get_ptr(i);
            if(!is_struct(&fd.type)) continue;
            //self.{fd.name}.drop();
            let drop_stmt = parse_stmt(format("Drop::drop(self.{});", &fd.name), unit, line);
            body.list.add(drop_stmt);
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
    if let Decl::Enum(variants*)=(decl){
        for(let i = 0;i < variants.len();++i){
            let ev = variants.get_ptr(i);
            let vt = Simple::new(decl.type.clone(), ev.name.clone()).into(line);
            let then = Block::new(line, line);

            //f.print({decl.type}::{ev.name})
            then.list.add(parse_stmt(format("f.print(std::print_type<{}>());", &vt), unit, line));
            if(ev.fields.len() > 0){
                then.list.add(parse_stmt("f.print(\"{\");".str(), unit, line));
                for(let j = 0;j < ev.fields.len();++j){
                    let fd = ev.fields.get_ptr(j);
                    if(j > 0){
                        then.list.add(parse_stmt("f.print(\", \");".str(), unit, line));
                    }
                    //f.print("<fd.name>: ")
                    then.list.add(parse_stmt(format("f.print(\"{}: \");", fd.name), unit, line));
                    if(fd.type.is_pointer()){
                        //print hex based address
                        //i64::debug_hex(<fd.name> as u64, f);
                        then.list.add(parse_stmt(format("i64::debug_hex({} as u64, f);", fd.name), unit, line));
                    }else{
                        //{fd.name}.debug(f);
                        //already ptr from if let arg
                        then.list.add(parse_stmt(format("Debug::debug({}, f);", fd.name), unit, line));
                    }
                }
                then.list.add(parse_stmt("f.print(\"}\");".str(), unit, line));
            }
            let self_id = unit.node(line);
            let block_id = unit.node(line);
            let is = IfLet{vt, List<ArgBind>::new(), Expr::Name{.self_id, "self".str()}, Box::new(Stmt::Block{.block_id, then}), Ptr<Stmt>::new()};
            for(let j = 0;j < ev.fields.len();++j){
                let fd = ev.fields.get_ptr(j);
                let arg_id = unit.node(line);
                is.args.add(ArgBind{.arg_id,fd.name.clone(), true});
            }
            let iflet_id = unit.node(line);
            body.list.add(Stmt::IfLet{.iflet_id, is});
        }
    }else{
        //f.print(<decl.type.print()>)
        body.list.add(parse_stmt(format("f.print(std::print_type<{}>());", &decl.type), unit, line));
        body.list.add(parse_stmt("f.print(\"{\");".str(), unit, line));
        let fields = decl.get_fields();
        for(let i = 0;i < fields.len();++i){
            let fd = fields.get_ptr(i);
            if(i > 0){
                body.list.add(parse_stmt(format("f.print(\", \");"), unit, line));
            }
            //f.print("<fd.name>: ");
            body.list.add(parse_stmt(format("f.print(\"{}: \");", fd.name), unit, line));
            if(fd.type.is_pointer()){
                //print hex based address
                //i64::debug_hex(fd.name as u64, f);
                body.list.add(parse_stmt(format("i64::debug_hex(self.{} as u64, f);", fd.name), unit, line));
            }else{
                //self.{fd.name}.debug(f);
                body.list.add(parse_stmt(format("Debug::debug(&self.{}, f);", fd.name), unit, line));
            }
        }
        body.list.add(parse_stmt(format("f.print(\"}\");", vt), unit, line));
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
    let info = FormatInfo::new(line);
    let block = &info.block;
    //print("gen {} id={} {}\n", node, node.id, r.unit.path);
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
        r.visit(block);
        r.format_map.add(node.id, info);
        return;
    }
    let var_name = format("f_{}", node.id);
    //let f = Fmt::new();
    let var_stmt = parse_stmt(format("let {} = Fmt::new();", &var_name), &r.unit, line);
    block.list.add(var_stmt);
    let pos = 0;
    let arg_idx = 1;
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
            let st = parse_stmt(format("{}.print(\"{}\");", &var_name, sub2), &r.unit, line);
            sub2.drop();
            block.list.add(st);
            if(br_pos == -1){
                break;
            }
        }
        pos = br_pos + 2;
        if(!(arg_idx < mc.args.len())){
            r.err(node, "format specifier not matched");
        }
        let arg = mc.args.get_ptr(arg_idx);
        ++arg_idx;
        //<arg>.debug(&f);
        let dbg_st = parse_stmt(format("({}).debug(&{});", arg, &var_name), &r.unit, line);
        block.list.add(dbg_st);
    }
    if(Resolver::is_print(mc)){
        //f.buf.print();
        let print_st = parse_stmt(format("{}.buf.print();", &var_name), &r.unit, line);
        block.list.add(print_st);
        //Drop::drop(f);
        let drop_st = parse_stmt(format("Drop::drop({});", &var_name), &r.unit, line);
        block.list.add(drop_st);
        //print("block={}\n", block);
        r.visit(block);
        r.format_map.add(node.id, info);
    }else if(Resolver::is_panic(mc)){
        //"<method:line>".print();
        let pos_info = make_panic_messsage(line, *r.curMethod.get(), Option<str>::new());
        let pos_info_st = parse_stmt(format("\"{}\".print();", &pos_info), &r.unit, line);
        pos_info.drop();
        block.list.add(pos_info_st);
        //f.buf.print();
        let print_st = parse_stmt(format("{}.buf.println();", &var_name), &r.unit, line);
        block.list.add(print_st);
        //Drop::drop(f);
        let drop_st = parse_stmt(format("Drop::drop({});", &var_name), &r.unit, line);
        block.list.add(drop_st);
        block.list.add(parse_stmt("exit(1);".str(), &r.unit, line));
        //print("block={}\n", block);
        r.visit(block);
        r.format_map.add(node.id, info);
    }else if(Resolver::is_format(mc)){
        //f.unwrap()
        let unwrap_mc = parse_expr(format("{}.unwrap()", &var_name), &r.unit, line);
        info.unwrap_mc = Option::new(unwrap_mc);
        r.visit(block);
        let tmp = r.visit(info.unwrap_mc.get());
        tmp.drop();
        r.format_map.add(node.id, info);
    }else{
        info.drop();
        r.err(node, "generate_format");
    }
    var_name.drop();
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
    let arg = mc.args.get_ptr(0);
    if(!r.is_condition(arg)){
        r.err(node, format("assert expr is not bool: {}", node));
    }
    let line = node.line;
    let info = FormatInfo::new(line);
    let block = &info.block;
    let arg_str = arg.print();
    let arg_norm = normalize_quotes(arg_str.str());
    arg_str.drop();
    let method_sig = printMethod(r.curMethod.unwrap());
    let str = format("if(!({})){\nprintf(\"{}:{}\nassertion `{}` failed in {}\n\");exit(1);\n}", arg, r.curMethod.unwrap().path, node.line, arg_norm, method_sig);
    arg_norm.drop();
    method_sig.drop();
    block.list.add(parse_stmt(str, &r.unit, line));
    r.visit(block);
    r.format_map.add(node.id, info);
}