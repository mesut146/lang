import parser/ast
import parser/resolver
import parser/utils
import std/hashmap

struct ProgInfo{
    cnt: i32;
    time: timeval;
}
impl Compare for Pair<String*, ProgInfo*>{
    func compare(self, o: Pair<String*, ProgInfo*>*): i64{
        //return self.b.cnt - o.b.cnt;
        return self.b.time.as_ms() - o.b.time.as_ms();
    }
}
impl Debug for ProgInfo{
    func debug(self, f: Fmt*){
        f.print("ProgInfo{cnt: ");
        Debug::debug(&self.cnt, f);
        f.print(", time: ");
        Debug::debug(&self.time.as_ms(), f);
        f.print("ms");
        f.print("}");
    }
}

static progress_print = false;
static prog_print_freq = false;
static prog_map = HashMap<String, ProgInfo>::new();
static compile_map = HashMap<String, ProgInfo>::new();

func init_prog(){
    let opt = std::getenv("prog");
    progress_print = opt.is_some() && opt.get().eq("1");
    prog_print_freq = opt.is_some() && opt.get().eq("2");
}

struct Progress{
    begin: Option<timeval>;
}

impl Progress{
    func new(): Progress{
        init_prog();
        Progress{begin: Option<timeval>::none()}
    }

    func resolve_done(self){
        if(progress_print) print("resolve done\n");
        if(prog_print_freq){
            let parr = prog_map.pairs();
            parr.sort();
            for p in &parr{
                print("{:?}=>{:?}\n", p.b, p.a);
            }
            parr.drop();
            prog_map.clear();
        }
    }

    func resolve_begin(self, m: Method*){
        let s = printMethod(m);
        if(progress_print) print("resolve begin {:?}\n", s);
        s.drop();
        self.begin.set(gettime());
    }

    func resolve_end(self, m: Method*){
        let beg = self.begin.unwrap();
        let end = gettime();
        let s = printMethod(m);
        let ms = end.sub(&beg);
        if(progress_print) print("resolve end {:?} time={}ms\n", s, ms.as_ms());
        if(prog_print_freq){
            self.update(m, &prog_map, ms);
        }
        s.drop();
    }

    func update(self, m: Method*, map: HashMap<String, ProgInfo>*, ms: timeval){
        let nm = "".owned();
        if let Parent::Impl(inf*)= (&m.parent){
            //nm.append(inf.type.name());
            nm.append(inf.type.print());
            nm.append("::");
        }
        nm.append(&m.name);
        let opt = map.get(&nm);
        if(opt.is_none()){
            map.add(nm.clone(), ProgInfo{1, ms});
        }else{
            let info = opt.unwrap();
            info.cnt += 1;
            info.time.tv_sec += ms.tv_sec;
            info.time.tv_usec += ms.tv_usec;
        }
        nm.drop();
    }

    func compile_begin(self, m: Method*){
        let s = printMethod(m);
        if(progress_print) print("compile begin {:?}\n", s);
        s.drop();
        self.begin.set(gettime());
    }

    func compile_end(self, m: Method*){
        let beg = self.begin.unwrap();
        let end = gettime();
        let s = printMethod(m);
        let ms = end.sub(&beg);
        if(progress_print) print("compile end {:?} time={}ms\n", s, ms.as_ms());
        self.update(m, &compile_map, ms);
        s.drop();
    }

    func compile_done(self){
        if(prog_print_freq){
            let parr = compile_map.pairs();
            parr.sort();
            print("-----------------compile map-----------------------\n\n");
            for p in &parr{
                print("{:?}=>{:?}\n", p.b, p.a);
            }
            parr.drop();
            compile_map.clear();
        }
    }
}