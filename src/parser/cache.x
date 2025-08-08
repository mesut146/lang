import std/hashmap
import std/io
import std/fs
import std/result

import parser/incremental

struct Cache{
    map: HashMap<String, String>;
    file: String;
    inc: Incremental;
    use_cache: bool;
}

func CACHE_FILE(out_dir: str): String{
    return Path::concat(out_dir, "cache.txt");
}

impl Cache{
    func new(incremental_enabled: bool, use_cache: bool, out_dir: str, src_dir: String): Cache{
        return Cache{
            map: HashMap<String, String>::new(),
            file: CACHE_FILE(out_dir),
            inc: Incremental::new(incremental_enabled, out_dir, src_dir),
            use_cache: use_cache,
        };
    }

    func read_cache(self){
        if(!self.use_cache) return;
        if(!File::exists(self.file.str())){
            return;
        }
        let buf = File::read_string(self.file.str())?;
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
        if(!self.use_cache) return;
        let str = String::new();
        for pair in &self.map{
            str.append(pair.a.str());
            str.append("=");
            str.append(pair.b.str());
            str.append("\n");
        }
        File::write_string(str.str(), self.file.str())?;
        str.drop();
    }
    
    func need_compile(self, file: str, out: str): bool{
        if(!self.use_cache) return true;
        if(!File::is_file(out)){
            return true;
        }
        let resolved = File::resolve(file).unwrap();
        file = resolved.str();
        let file_s = file.str();
        let old = self.map.get(&file_s);
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
        if(!self.use_cache) return;
        let resolved = File::resolve(file)?;
        let time = self.get_time(resolved.str());
        self.map.add(resolved, time);
    }
    
    func get_time(self, file: str): String{
        let resolved = File::resolve(file)?;
        let time = File::get_last_write_time(resolved.str());
        resolved.drop();
        return time.str();
    }
}