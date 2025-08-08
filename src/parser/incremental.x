import std/hashmap
import std/hashset
import std/fs

import ast/ast
import ast/parser

import parser/compiler

struct Incremental{
    //a.x:struct C <- main.x, b.x
    //a.x:enum E <- c.x
    //a.x:func ff -> b.x
    //#desc=file:name
    path: String;
    map: HashMap<String, HashMap<String, HashSet<String>>>;//file -> (desc -> list of dependants)
    enabled: bool;
    recompiles: HashSet<String>;
    src_dir: String;
}
impl Incremental{
    func new(enabled: bool, out_dir: str, src_dir: String): Incremental{
        //todo read
        let path = format("{}/inc_map.txt", out_dir);
        let res = Incremental{
            path: path,
            map: HashMap<String, HashMap<String, HashSet<String>>>::new(), 
            enabled: enabled,
            recompiles: HashSet<String>::new(),
            src_dir: src_dir,
        };
        res.read();
        return res;
    }

    func read(self){
        if(!self.enabled) return;
        if(!File::exists(self.path.str())) return;
        let buf = File::read_string(self.path.str())?;
        let pos = 0;
        while(pos < buf.len()){
            if(buf.get(pos) == '#'){
                let end = buf.str().indexOf('\n', pos);
                let item_path = buf.substr(pos + 1, end);
                pos = end + 1;
                if(buf.get(pos) == '\n'){
                    pos += 1;
                    continue;
                }
                //read desc and set
                let map = HashMap<String, HashSet<String>>::new();
                while(pos < buf.len()){
                    if(buf.get(pos) == '#'){
                        break;
                    }
                    let arrow = buf.str().indexOf("<-", pos);
                    let desc = buf.substr(pos, arrow);
                    end = buf.str().indexOf('\n', arrow);
                    let list_str = buf.substr(arrow + 2, end - 1);
                    let set = HashSet<String>::new();
                    let items = list_str.split(",");
                    for item in &items{
                        set.insert(item.owned());
                    }
                    map.insert(desc.owned(), set);
                    pos = end + 1;
                    if(buf.get(pos) == '\n'){
                        pos += 1;
                        continue;
                    }
                }
                self.map.insert(item_path.owned(), map);
            }
        }
        //print("read={:?}\n", self.map);
    }

    func update(self, file: str, key: String, item_path: str){
        item_path = Path::relativize(item_path, self.src_dir.str());
        let map_opt = self.map.get_str(item_path);
        if(map_opt.is_none()){
            self.map.insert(item_path.owned(), HashMap<String, HashSet<String>>::new());
            map_opt = self.map.get_str(item_path);
        }
        let map = map_opt.unwrap();
        let list_opt = map.get(&key);
        if(list_opt.is_none()){
            map.insert(key.clone(), HashSet<String>::new());
            list_opt = map.get(&key);
        }
        list_opt.unwrap().add(Path::relativize(file, self.src_dir.str()).owned());
        key.drop();
    }

    func get_key(decl: Decl*): String{
        if(decl is Decl::Struct || decl is Decl::TupleStruct){
            format("struct {}", decl.type.name())
        }else{
            format("enum {}", decl.type.name())
        }
    }

    func depends_decl(self, file: str, decl: Decl*){
        if(!self.enabled) return;
        if(decl.path.eq(file)) return;
        let key = get_key(decl);
        self.update(file, key, decl.path.str());
        self.save();
    }

    func depends_decl(self, r: Resolver*, type: Type*){
        if(!self.enabled) return;
        let rt = r.visit_type(type);
        if(!rt.is_decl()){
            return;
        }
        self.depends_decl(r.unit.path.str(), r.get_decl(&rt).unwrap());
    }

    func depends_func(self, r: Resolver*, m: Method*){
        if(!self.enabled) return;
        let file = r.unit.path.str();
        if(file.eq(m.path.str())) return;
        let key = format("func {}", printMethod(m));
        self.update(file, key, m.path.str());
        self.save();
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
        //print("map={:?}\n", buf);
        File::write_string(buf.str(), self.path.str())?;
    }

    //file is modified, find other files that depend on the file
    func find_recompiles(self, file: str, old_file: str){
        if(!self.enabled) return;
        
        let p = Parser::from_path(file.owned());
        let unit = p.parse_unit();
        
        let p2 = Parser::from_path(old_file.owned());
        let unit2 = p2.parse_unit();
        
        //compare units
        //change of struct layout, method sig
        
        for it in &unit.items{
            match it{
                Item::Decl(decl) => {
                    let old_decl = find_old_struct(&unit2, decl);
                    if(old_decl.is_some()){
                        if(compare_decl(decl, old_decl.unwrap())){
                            //scan other dependant files
                            let opt = self.map.get_str(Path::relativize(file, self.src_dir.str()));
                            if(opt.is_some()){
                                let key = get_key(decl);
                                let list = opt.unwrap().get(&key);
                                for rec_file in list.unwrap(){
                                    self.recompiles.insert(rec_file.clone());
                                }
                            }
                        }
                    }
                },
                Item::Method(m)=>{
                    //todo
                },
                Item::Impl(imp)=>{
                    //todo cmp sig and methods
                },
                _ => {}
            }
        }
    }

    func find_old_struct(unit: Unit*, d: Decl*): Option<Decl*>{
        for it in &unit.items{
            match it{
                Item::Decl(decl) => {
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
            Decl::Struct(fields) => {
                match old{
                    Decl::Struct(fields2) => {
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
            Decl::TupleStruct(fields) => {
                //todo
            },
            Decl::Enum(variants)=>{
                match old{
                    Decl::Enum(variants2) => {
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
            if(!fd.name.get().eq(fd2.name.get())) return true;
            if(!fd.type.eq(&fd2.type)) return true;
        }
        return false;
    }

}
