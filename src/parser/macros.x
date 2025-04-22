import parser/ast
import parser/parser

//#derive_macro
func derive_clone(ts: TokenStream): TokenStream{
    
    panic("todo");
}

//#derive_macro
func derive_debug(it: Item): TokenStream{
    let res = TokenStream::new();
    if let Item::Decl(d*) = it{
        res.add("impl");
        if(d.type.is_generic()){
            res.add("<");
            let i = 0;
            for ta in d.type.get_args(){
                if(i > 0) res.add(", ");
                res.add_all(ta.print());
                i += 1;
            }
            res.add(">");
        }
        res.add("Debug");
        res.add("for");
        res.add_all(d.type.print());
        res.add("{");
        res.add("func");
        res.add("debug");
        res.add("(");
        res.add("self");
        res.add(",");
        res.add("Fmt");
        res.add("*");
        res.add(")");
        match d{
            Decl::Struct(fields*) =>{

            },
            Decl::Enum(vars*)=>{

            }
        }
        res.add("}");//impl end
    }else{
        panic("derive_debug can only be applied to structs");
    }
    if(true) panic("todo");
    return res;
}
