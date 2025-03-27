import parser/ast
import parser/parser
import parser/compiler
import std/hashmap
import std/hashset

struct Incremental{
    //a.x:struct C <- main.x, b.x
    //a.x:enum E <- c.x
    //a.x:func ff -> b.x
    //#desc=file:name
    path: String;
    map: HashMap<String, HashMap<String, HashSet<String>>>;//file -> (desc -> list of dependants)
    enabled: bool;
}
impl Incremental{
    func new(out_dir: str, enabled: bool): Incremental{
        //todo read
        let path = format("{}/inc_map.txt", out_dir);
        return Incremental{
            path: path,
            map: HashMap<String, HashMap<String, HashSet<String>>>::new(), 
            enabled: enabled
        };
    }

    func read(self){
        if(!self.enabled) return;
    }

    func depends_decl(self, file: str, decl: Decl*){
        if(!self.enabled) return;
        if(decl.path.eq(file)) return;
        print("file {} -> decl {:?},{}\n", file, decl.type, decl.path);
        let map_opt = self.map.get(&decl.path);
        if(map_opt.is_none()){
            self.map.insert(decl.path.clone(), HashMap<String, HashSet<String>>::new());
            map_opt = self.map.get(&decl.path);
        }
        let map = map_opt.unwrap();
        let key = if(decl.is_struct()){
            format("struct {}", decl.type.name())
        }else{
            format("enum {}", decl.type.name())
        };
        let list_opt = map.get(&key);
        if(list_opt.is_none()){
            map.insert(key.clone(), HashSet<String>::new());
            list_opt = map.get(&key);
        }
        //todo set
        list_opt.unwrap().add(file.owned());
        self.save();
        key.drop();
    }

    func depends_decl(self, r: Resolver*, type: Type*){
        if(!self.enabled) return;
        let rt = r.visit_type(type);
        if(!rt.is_decl()){
            return;
        }
        self.depends_decl(r.unit.path.str(), r.get_decl(&rt).unwrap());
    }

    func save(self){
        if(!self.enabled) return;
        let buf = String::new();
        for pair in &self.map{
            buf.append("#");
            buf.append(pair.a);
            buf.append("\n");
            for pair2 in pair.b{
                buf.append(pair2.a);
                buf.append("<-");
                for file in pair2.b{
                    buf.append(file);
                    buf.append(",");
                }
                buf.append("\n");
            }
            buf.append("\n");
        }
        print("map={:?}\n", buf);
        File::write_string(buf.str(), self.path.str());
    }

    //file is modified, find other files that depend on the file
    func find_recompiles(c: Compiler*, config: CompilerConfig*, file: str, old_file: str){
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
                        if(compare_decl(decl, old_decl.unwrap())){
                            //scan other dependant files
                            /*let list: List<String> = File::list(config.file.str(), Option::new(".x"), true);
                            for other_file in &list{
                                let r = c.ctx.create_resolver(other_file);
                                //check other_file depends on file

                            }
                            list.drop();*/
                        }
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
                Item::Decl(decl*) => {
                    if(decl.type.eq(&d.type)) return Option::new(decl);
                },
                _ => {}
            }
        }
        return Option<Decl*>::none();
    }

    func compare_decl(d: Decl*, old: Decl*): bool{
        assert(d.type.eq(&old.type));
        match d{
            Decl::Struct(fields*) => {
                match old{
                    Decl::Struct(fields2*) => {
                        if(compare_struct(fields, fields2)){
                            //struct layout changed, now scan dependant files
                            return true;
                        }
                    },
                    _=> {
                        //was enum but now struct
                        return true;
                    }
                }
            },
            Decl::Enum(variants*)=>{
                match old{
                    Decl::Enum(variants2*) => {
                        //compare_enum(variants, variants2);
                    },
                    _=> {
                        //was struct but now enum
                        return true;
                    }
                }
            }
        }
        return false;
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

}