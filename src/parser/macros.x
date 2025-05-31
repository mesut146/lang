import ast/ast
import ast/parser

//#derive_macro(Clone)
func derive_clone(it: Item): TokenStream{
    
    panic("todo");
}

//#derive_macro(Debug)
func derive_debug(it: Item): TokenStream{
    let res = TokenStream::new();
    if let Item::Decl(d) = it{
        res.add("impl");
        if(d.type.is_generic()){
            res.add("<");
            let i = 0;
            for ta in d.type.get_args(){
                if(i > 0) res.add(", ");
                res.add(ta.print());
                i += 1;
            }
            res.add(">");
        }
        res.add(format("Debug for {:?}{{", d.type));
        res.add("func debug(self, f: Fmt*){{");
        match d{
            Decl::Struct(fields) => {
                for fd in fields{
                    res.add(format("debug_member!({}, f);", fd.name.get()));
                }
            },
            Decl::Enum(vars) => {

            },
            Decl::TupleStruct(fields) => {

            }
        }
        res.add("}");//impl end
    }else{
        panic("derive_debug can only be applied to structs");
    }
    //parse_ts(ts);
    if(true) panic("todo");
    return res;
}
