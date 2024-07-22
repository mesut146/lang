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
        for(let i = 0;i < lines.len();++i){
            let line = lines.get_ptr(i);
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
        for(let i = 0;i < self.map.len();++i){
            let pair = self.map.get_pair_idx(i).unwrap();
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
        let file_s = file.str();
        let old = self.map.get_ptr(&file_s);
        file_s.drop();
        if(old.is_some()){
            let old_time = old.unwrap();
            let cur_time = self.get_time(file);
            let res = !old_time.eq(cur_time.str());
            cur_time.drop();
            return res;
        }
        return true;
    }
    func update(self, file: str){
        if(!use_cache) return;
        self.map.add(file.str(), self.get_time(file));
    }
    func get_time(self, file: str): String{
        let cs = CStr::new(file);
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