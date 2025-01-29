struct Regex{
    pat: str;
    i: i32;
    node: Option<Node>;
    group_cnt: i32;
}

#derive(Debug)
struct Node{
    or: Or;
    begin: bool;
    end: bool;
}

#derive(Debug)
struct Or{
    list: List<Seq>;
}

#derive(Debug)
struct Seq{
    list: List<RegexItem>;
}

#derive(Debug)
struct Op{
    node: Box<Op>;
    kind: OpKind;
}
#derive(Debug)
struct Bracket{
    negated: bool;
    list: List<Range>;
}

#derive(Debug)
enum RegexItem {
    Group(node: Or, name: String),
    Brac(node: Bracket),
    Op(node: Box<RegexItem>, kind: OpKind),
    Ch(val: i32),
    Escape(val: i32),
    Dot
}

#derive(Debug)
struct Range{
    start: i32;
    end: i32;
}

#derive(Debug)
enum OpKind{
    Opt,
    Star,
    Plus
}

impl Regex{
    func new(pat: str): Regex{
        let res = Regex{pat: pat, i: 0, node: Option<Node>::new(), group_cnt: 0};
        res.node = Option::new(res.parse());
        let s = to_string(res.node.get());
        //print("pat={}\n", res.node.get());
        //print("pat={}\n", s);
        return res;
    }
    func is(self, ch: i32): bool{
        return self.pat.get(self.i) == ch;
    }
    func has(self): bool{
        return self.i < self.pat.len();
    }
    func parse(self): Node{
        let start = false;
        let end = false;
        if(self.is('^')){
            start = true;
            self.i += 1;
        }
        let or = self.parse_or();
        if(self.is('$')){
            end = true;
            self.i += 1;
        }
        return Node{or, start, end};
    }
    func parse_or(self): Or{
        let or = Or{list: List<Seq>::new()};
        let s1 = self.parse_seq();
        or.list.add(s1);
        while(self.is('|')){
            self.i += 1;
            let s2 = self.parse_seq();
            or.list.add(s2);
        }
        return or;
    }
    func parse_seq(self): Seq{
        let seq = Seq{list: List<RegexItem>::new()};
        let s1 = self.parse_op();
        seq.list.add(s1);
        while(self.has() && !self.is('$') && !self.is('|') && !self.is(')')){
            let s2 = self.parse_op();
            seq.list.add(s2);
        }
        return seq;
    }
    func is_op(self): bool{
        return self.is('.') || self.is('(') || self.is('[');
    }
    
    func parse_op(self): RegexItem{
        let it = self.parse_item();
        while(self.has()){
            if(self.is('*')){
                self.i += 1;
                let res = RegexItem::Op{Box::new(it), OpKind::Star};
                it = res;
            }
            else if(self.is('+')){
                self.i += 1;
                let res = RegexItem::Op{Box::new(it), OpKind::Plus};
                it = res;
            }
            else if(self.is('?')){
                self.i += 1;
                let res = RegexItem::Op{Box::new(it), OpKind::Opt};
                it = res;
            }else{
                break;
            }
        }
        return it;
    }
    
    func parse_item(self): RegexItem{
        let ch = self.pat.get(self.i);
        if(ch == '.'){
            self.i += 1;
            return RegexItem::Dot;
        }
        if(ch == '('){
            self.i += 1;
            let or = self.parse_or();
            self.i += 1;
            let name = format("{}", self.group_cnt);
            self.group_cnt += 1;
            return RegexItem::Group{or, name};
        }
        if(ch == '['){
            self.i += 1;
            let neg = false;
            if(self.is('^')){
                self.i += 1;
                neg = true;
            }
            let ranges = List<Range>::new();
            ranges.add(self.parse_range());
            while(!self.is(']')){
                ranges.add(self.parse_range());
            }
            self.i += 1;
            let res = RegexItem::Brac{Bracket{neg, ranges}};
            return res;
        }
        if(ch == '\\'){
            self.i += 1;
            let ch2 = self.pat.get(self.i);
            let val = 0;
            if(ch2=='\\'){
                val = '\\';
            }else if(ch2=='n'){
                val = '\n';
            }else if(ch2=='r'){
                val = '\r';
            }else if(ch2=='t'){
                val = '\t';
            }else if(ch2=='"'){
                val = '"';
            }else{
                panic("invalid escape {}", self.pat);
            }
        }
        return RegexItem::Ch{self.parse_chr()};
        //panic("{}", ch);
    }

    func parse_range(self): Range{
        let c1 = self.parse_chr();
        if(self.is('-')){
            self.i += 1;
            let c2 = self.parse_chr();
            return Range{c1,c2};
        }
        return Range{c1,c1};
    }
    func parse_chr(self): i32{
        let ch = self.pat.get(self.i);
        if(ch=='\\') panic("escape ch={}", ch);
        self.i += 1;
        return ch;
        /*if(ch >= '0' && ch <= '9'){
            self.i += 1;
            return ch;
        }
        if(ch >= 'a' && ch <= 'z'){
            self.i += 1;
            return ch;
        }
        if(ch == '#' || ch == '-' || ch == '_' || ch=='/'){
            self.i += 1;
            return ch;
        }
        panic("ch={}", ch);
        */
    }
}

impl Regex{
    func is_match(self, s: str): bool{
        let mv = MatchVisitor{self, s, Captures::new()};
        let res = mv.visit();
        return res;
    }
    func captures(self, s: str): Option<Captures>{
        let mv = MatchVisitor{self, s, Captures::new()};
        let res = mv.visit();
        if(res){
             Option::new(mv.cap)
        }else{
            Option<Captures>::new()
        }
    }
}
struct Captures{
    map: Map<str, Capture>;
}
impl Captures{
    func new(): Captures{
        return Captures{Map<str, Capture>::new()};
    }
    func get(self, idx: i32): Capture*{
        let s = format("{}", idx);
        let res = self.get(s.str());
        s.drop();
        return res;
    }
    func get(self, name: str): Capture*{
        let opt = self.map.get_ptr(&name);
        if(opt.is_none()){
            panic("group {} not found", name);
        }
        return opt.unwrap();
    }
    func has(self, name: str): bool{
        return self.map.get_ptr(&name).is_some();
    }
}
#derive(Debug)
struct Capture{
    arr: List<str>;
    buf: str;
    start: i32;
    end: i32;
}
impl Capture{
    func new(): Capture{
        return Capture{List<str>::new(), "", -1, -1};
    }
    func str(self): str{
        return self.buf;
    }
    func get(self, idx: i32): str{
        return *self.arr.get_ptr(idx);
    }
}

struct MatchVisitor{
    r: Regex*;
    s: str;
    cap: Captures;
}
struct MatchState{
    is_match: bool;
    len: i32;
}
impl MatchVisitor{
    func has(self, i: i32): bool{
        return i < self.s.len();
    }
    func visit(self): bool{
        //print("str={}\n", self.s);
        let res = self.visit_or(&self.r.node.get().or, 0);
        if(res.a && res.b != self.s.len()){
            if(res.b != self.s.len()){
                //let pat = to_string(self.r);
                //print("str not consumed {} len={} {} pat={}\n", res.b, self.s.len(), self.s, self.r.pat);   
            }
            return false;
        }
        return res.a;
    }
    func visit_or(self, or: Or*, i: i32): Pair<bool, i32>{
        if(or.list.len() == 1){
            return self.visit_seq(or.list.get_ptr(0), i);
        }
        let best = Pair::new(false, 0);
        for sq in &or.list{
            let tmp = self.visit_seq(sq, i);
            if(tmp.a){
                if(!best.a || tmp.b > best.b){
                    best = tmp;
                }
            }
        }
        return best;
    }
    func visit_seq(self, sq: Seq*, i: i32): Pair<bool, i32>{
        let total = 0;
        for(let idx=0;idx<sq.list.len();idx+=1){
            let item = sq.list.get_ptr(idx);
            //print("idx={} item={} total={}\n", idx, to_string(item), total);
            let it_used = false;
            //prevent greedy match
            match item{
                RegexItem::Op(ch*, kind*) => {
                    if((ch.get() is RegexItem::Dot || ch.get() is RegexItem::Ch) && kind is OpKind::Star && idx < sq.list.len() - 1){
                        let next = sq.list.get_ptr(idx + 1);
                        //print("gr ch={} next={}\n", ch.get(), next);
                        //do non greedy  (ab)*a
                        //b*b => bb
                        let end2 = i + total;
                        while(true){
                            let chr = self.visit_item(ch.get(), end2);
                            if(!chr.a) break;
                            let nextr = self.visit_item(next, end2);
                            if(nextr.a){
                                let nextr2 = self.visit_item(next, end2 + chr.b);
                                if(nextr2.a){
                                    //use ch
                                    //print("use ch\n");
                                    end2 += chr.b;
                                    total += chr.b;
                                    it_used = true;
                                }else{
                                    //ignore ch
                                    total = end2;
                                    //print("ignore ch\n");
                                    break;
                                }
                            }else{
                                //we must use ch
                                //print("use ch\n");
                                end2 += chr.b;
                                total += chr.b;
                                it_used = true;           
                            }
                         }
                        continue;
                    }else if((ch.get() is RegexItem::Dot || ch.get() is RegexItem::Ch) && kind is OpKind::Opt && idx < sq.list.len() - 1){
                        let next = sq.list.get_ptr(idx + 1);
                        //print("gr ch={} next={}\n", ch.get(), next);
                        let chr = self.visit_item(ch.get(), i+total);
                        if(!chr.a) continue;
                        let nextr = self.visit_item(next, i+total);
                        //a?a, a?(ab|c) => a,a,ab,aab,ac
                        if(nextr.a){
                            let nextr2 = self.visit_item(next, i+total + chr.b);
                                if(nextr2.a){
                                    //use ch
                                    //print("use ch\n");
                                    total += chr.b;
                                    it_used = true;
                                }else{
                                    //ignore ch                          
                                    //print("ignore ch\n");
                                    continue;
                                }
                        }else{
                            //use ch
                            total += chr.b;
                            it_used = true;        
                        }
                    }
                },
                _=>{
                    
                }
            }
            if(!it_used){
                let res = self.visit_item(item, i + total);
                if(!res.a) return Pair::new(false, 0);
                total += res.b;
            }
        }
        return Pair::new(true, total);
    }
    func is_dot(it: RegexItem*): bool{
        return it is RegexItem::Dot;
    }
    func is_empty(it: RegexItem*): bool{
        match it{
            RegexItem::Op(node*, kind*) => {
                return kind is OpKind::Opt || kind is OpKind::Star;
            },
            _=> { return false; }
        }
    }
    func visit_item(self, it: RegexItem*, i: i32): Pair<bool, i32>{
        if(!self.has(i)){
            if(is_empty(it)) return Pair::new(true, 0);
            return Pair::new(false, 0);
        }
        //print("visit_item i={} s='{}' {}\n", i, self.s.substr(i), to_string(it));
        let res = match it{
            RegexItem::Ch(ch) => 
                Pair::new(self.s.get(i) == ch, 1)
            ,
            RegexItem::Group(or*, name*) => {
                let tmp = self.visit_or(or, i);
                if(tmp.a){
                    let s = self.s.substr(i, i + tmp.b);
                    let c0 = self.cap.map.get_ptr(&name.str());
                    if(c0.is_some()){
                        let c = c0.unwrap();
                        c.arr.add(s);
                        c.buf = self.s.substr(c.start, c.end + tmp.b);
                        c.end += tmp.b;
                    }else{
                        let c = Capture::new();
                        c.arr.add(s);
                        c.buf = s;
                        c.start = i;
                        c.end = i + tmp.b;
                        self.cap.map.add(name.str(), c);
                    }
                }
                tmp
            },
            RegexItem::Op(node*, kind*) => {
                let tmp = self.visit_item(node.get(), i);
                match kind{
                    OpKind::Opt=>{
                        //print("node={} s='{}' tmp={} i={}\n", it, self.s.substr(i), tmp, i);
                        let rr = Pair::new(true, 0);
                        if(tmp.a){
                            rr.b = tmp.b;
                        }   
                        rr
                   },
                   OpKind::Star=>{
                       let rr = Pair::new(true, 0);
                       if(tmp.a){
                           rr.b = tmp.b;
                           while(true){
                               let tt = self.visit_item(node.get(), i + tmp.b);
                               if(!tt.a) break;
                               tmp.b += tt.b;
                               rr.b += tt.b;
                           }
                       }
                       rr
                   },
                   OpKind::Plus=>{
                       let rr = Pair::new(false, 0);
                       if(tmp.a){
                           rr.a = true;
                           rr.b = tmp.b;
                           while(true){
                               let tt = self.visit_item(node.get(), i + tmp.b);
                               if(!tt.a) break;
                               tmp.b += tt.b;
                               rr.b += tt.b;
                           }
                       }
                       rr
                   },
                   _=> panic("other kind")
                }
            },
            RegexItem::Dot=>{
                Pair::new(true, 1)
            },
            RegexItem::Brac(br*)=>{
                let valid = false;
                let ch = self.s.get(i);
                if(br.negated){
                }
                for rng in &br.list{
                    if(ch >= rng.start && ch <= rng.end){
                        valid = true;
                        break;
                    }
                }
                if(br.negated){
                    if(valid) return Pair::new(false, 0);
                    else return Pair::new(true, 1);
                }
                Pair::new(valid, 1)
            },
            _=>  panic("it={}\n", it)
        };
        //print("visit_item2 i={} s='{}' {} res={}\n", i, self.s.substr(i), to_string(it), res);
        return res;
    }
}


//-----------------------------------------------------
impl Display for Node{
    func fmt(self, f: Fmt*){
        if(self.begin) f.print("^");
        Display::fmt(&self.or, f);
        if(self.end) f.print("$");
    }
}
impl Display for Or{
    func fmt(self, f: Fmt*){
        let i = 0;
        for s in &self.list{
            if(i>0) f.print("|");
            i+=1;
            Display::fmt(s, f);
        }
    }
}
impl Display for Seq{
    func fmt(self, f: Fmt*){
        for item in &self.list{
            Display::fmt(item, f);
        }
    }
}
impl Display for Bracket {
    func fmt(self, f: Fmt*){
        f.print("[");
        if(self.negated){
            f.print("^");
        }
        for rn in &self.list{
            Display::fmt(rn, f);
        }
        f.print("]");
    }
}
impl Display for RegexItem{
    func fmt(self, f: Fmt*){
        match self{
            RegexItem::Dot => f.print("."), 
            RegexItem::Group(node*, name*)=>{
                f.print("(");
                f.print("?<");
                f.print(name);
                f.print(">");
                Display::fmt(node, f);
                f.print(")");
            },
            RegexItem::Brac(node*)=>{
                Display::fmt(node, f);
            },
            RegexItem::Op(node*, kind*)=>{
                Display::fmt(node.get(), f);
                Display::fmt(kind, f);
            },
            RegexItem::Ch(val)=>{
                f.print(&(val as i8));
            },
            RegexItem::Escape(val*)=>{
                f.print("\\");
                f.print(val);
            }
        }
    }
}
impl Display for Range{
    func fmt(self, f: Fmt*){
        f.print(&(self.start as i8));
        f.print("-");
        f.print(&(self.end as i8));
    }
}
impl Display for OpKind{
    func fmt(self, f: Fmt*){
        match self{
            OpKind::Opt => f.print("?"),
            OpKind::Star => f.print("*"),
            OpKind::Plus=> f.print("+")
        }
    }
}