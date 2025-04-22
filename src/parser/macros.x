import parser/ast
import parser/parser

//#derive_macro
func derive_clone(ts: TokenStream): TokenStream{
    
    panic("todo");
}

//#derive_macro
func derive_debug(it: Item): TokenStream{
    /*let res = TokenStream::new();
    if let Item::Decl(d*) = it{
        res.add("impl");
        //todo generic args
        res.add("Debug");
        res.add("for");
        res.add(d.type.print());
        res.add("{");
        res.add("func");
        res.add("debug");
        res.add("(");
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
    }*/
    panic("todo");
    //return res;
}