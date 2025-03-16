import std/map
import std/io
import parser/bridge

static use_cache: bool = true;

struct Cache{
    map: Map<String, String>;
    file: String;
}

func CACHE_FILE(out_dir: str): String{
    return format("{}/cache.txt", out_dir);
}

impl Cache{
    func new(out_dir: str): Cache{
        return Cache{
            map: Map<String, String>::new(),
            file: CACHE_FILE(out_dir)
        };
    }

    func read_cache(self){
        if(!use_cache) return;
        if(!exist(self.file.str())){
            return;
        }
        let buf = read_string(self.file.str());
        let lines = buf.str().split("\n");
        for line in &lines{
            if(line.len() == 0){
                continue;
            }
            let eq = line.indexOf("=");
            let path = line.substr(0, eq);
            let time = line.substr(eq + 1);
            self.map.add(path.str(), time.str());
        }
        lines.drop();
        buf.drop();
        //print("read_cache={}\n", self.map);
    }
    
    func write_cache(self){
        if(!use_cache) return;
        let str = String::new();
        for pair in &self.map{
            str.append(pair.a.str());
            str.append("=");
            str.append(pair.b.str());
            str.append("\n");
        }
        write_string(str.str(), self.file.str());
        str.drop();
    }
    
    func need_compile(self, file: str, out: str): bool{
        if(!use_cache) return true;
        if(!is_file(out)){
            return true;
        }
        let resolved = resolve(file);
        file = resolved.str();
        let file_s = file.str();
        let old = self.map.get_ptr(&file_s);
        file_s.drop();
        if(old.is_some()){
            let old_time = old.unwrap();
            let cur_time = self.get_time(file);
            let res = !old_time.eq(cur_time.str());
            cur_time.drop();
            resolved.drop();
            return res;
        }
        resolved.drop();
        return true;
    }
    
    func update(self, file: str){
        if(!use_cache) return;
        let resolved = resolve(file);
        let time = self.get_time(resolved.str());
        self.map.add(resolved, time);
    }
    
    func get_time(self, file: str): String{
        let resolved = resolve(file);
        let cs = CStr::new(resolved);
        let time = get_last_write_time(cs.ptr());
        cs.drop();
        return time.str();
    }
    
    func delete_cache(out_dir: str){
        let file = CACHE_FILE(out_dir);
        if(is_file(file.str())){
            File::remove_file(file.str());
        }
        file.drop();
    }
}