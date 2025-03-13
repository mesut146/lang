import parser/ast
import parser/resolver
import parser/utils
import std/hashmap

#derive(Debug)
struct ProgInfo{
    cnt: i32;
    sec: i32;
}
impl Compare for Pair<String*, ProgInfo*>{
    func compare(self, o: Pair<String*, ProgInfo*>*): i32{
        //return self.b.cnt - o.b.cnt;
        return self.b.sec - o.b.sec;
    }
}

static progress_print = false;
static prog_map = HashMap<String, ProgInfo>::new();
static prog_print_freq = false;

func init_prog(){
     prog_print_freq = getenv2("prog").is_some() && getenv2("prog").get().eq("2");
     progress_print = getenv2("prog").is_some() && getenv2("prog").get().eq("1");
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
                print("{:?}=>{:?}\n\n", p.a, p.b);
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
        let sec = end.sec(&beg);
        if(progress_print) print("resolve end {:?} time={}\n", s, sec);
        if(prog_print_freq){
            let nm = "".owned();
            if let Parent::Impl(inf*)= (&m.parent){
                nm.append(inf.type.name());
                nm.append("::");
            }
            nm.append(&m.name);
            let opt = prog_map.get(&nm);
            if(opt.is_none()){
                prog_map.add(nm.clone(), ProgInfo{1, sec});
            }else{
                let info = opt.unwrap();
                info.cnt += 1;
                info.sec += sec;
            }
            nm.drop();
        }
        s.drop();
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
        if(progress_print) print("compile end {:?} time={}\n", s, end.sec(&beg));
        s.drop();
    }
}