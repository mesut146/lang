import parser/ast
import parser/parser

//file is modified, find other files that depend on the file
func find_recompiles(file: str, old_file: str){
    let p = Parser::from_path(file.owned());
    let unit = p.parse_unit();
    
    let p2 = Parser::from_path(old_file.owned());
    let unit2 = p2.parse_unit();
    
    //compare units
    //change of struct layout, method sig
    
    for it in &unit.items{
        match it{
            Item::Decl(decl*)=>{
                let old_decl = find_old_struct(&unit2, decl);
                if(old_decl.is_some()){
                    compare_decl(decl, old_decl.unwrap());
                }
            },
            Item::Method(m*)=>{
                //todo
            },
            Item::Impl(imp*)=>{
                //todo cmp sig and methods
            },
            _=>{}
        }
    }
}

func find_old_struct(unit: Unit*, d: Decl*): Option<Decl*>{
    for it in &unit.items{
        match it{
            Item::Decl(decl*)=>{
                if(decl.type.eq(&d.type)) return Option::new(decl);
            },
            _=>{}
        }
    }
    return Option<Decl*>::none();
}

func compare_decl(d: Decl*, old: Decl*){
    assert(d.type.eq(&old.type));
    match d{
        Decl::Struct(fields*) => {
            match old{
                Decl::Struct(fields2*) => {
                    compare_struct(fields, fields2);
                },
                _=> panic("was enum but now struct")
            }
        },
        Decl::Enum(variants*)=>{
            match old{
                Decl::Enum(variants2*) => {
                    //compare_enum(variants, variants2);
                },
                _=> {
                    panic("was struct but now enum");
                }
            }
        }
    }
}
func compare_struct(fields: List<FieldDecl>*, fields2: List<FieldDecl>*): bool{
    if(fields.len() != fields2.len()){
        return true;
    }
    for(let i = 0;i < fields.len();i += 1){
        let fd = fields.get(i);
        let fd2 = fields2.get(i);
        if(!fd.name.eq(&fd2.name)) return true;
        if(!fd.type.eq(&fd2.type)) return true;
    }
    return false;
}