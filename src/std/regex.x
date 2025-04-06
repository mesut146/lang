struct Regex{
    pat: str;
    i: i32;
    node: Option<RegexNode>;
    group_cnt: i32;
}

#derive(Debug)
struct RegexNode{
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
enum OpKind{
    Opt,
    Star,
    Plus
}

#derive(Debug)
struct Op{
    RegexNode: Box<Op>;
    kind: OpKind;
}
#derive(Debug)
struct Bracket{
    negated: bool;
    list: List<Range>;
}

#derive(Debug)
enum RegexItem {
    Group(RegexNode: Or, name: String),
    Brac(RegexNode: Bracket),
    Op(RegexNode: Box<RegexItem>, kind: OpKind),
    Ch(val: i32),
    Escape(val: i32),
    Dot
}

#derive(Debug)
struct Range{
    start: i32;
    end: i32;
}

impl Regex{
    func new(pat: str): Regex{
        let res = Regex{pat: pat, i: 0, node: Option<RegexNode>::new(), group_cnt: 0};
        res.parse();
        return res;
    }
    func is(self, ch: i32): bool{
        return self.pat.get(self.i) == ch;
    }
    func has(self): bool{
        return self.i < self.pat.len();
    }
    func parse(self){
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
        let res = RegexNode{or, start, end};
        self.node = Option::new(res);
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
            if(ch2 == '\\'){
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
        if(ch == '\\') panic("escape ch={}", ch);
        self.i += 1;
        return ch;
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
        let opt = self.map.get(&name);
        if(opt.is_none()){
            panic("group {} not found", name);
        }
        return opt.unwrap();
    }
    func has(self, name: str): bool{
        return self.map.get(&name).is_some();
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
        return *self.arr.get(idx);
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
impl MatchState{
    func new(is_match: bool, len: i32): MatchState{
        return MatchState{is_match, len};
    }

}
impl MatchVisitor{
    func has(self, i: i32): bool{
        return i < self.s.len();
    }
    func visit(self): bool{
        let res = self.visit_or(&self.r.node.get().or, 0);
        if(res.is_match && res.len != self.s.len()){
            return false;
        }
        return res.is_match;
    }
    func visit_or(self, or: Or*, i: i32): MatchState{
        if(or.list.len() == 1){
            return self.visit_seq(or.list.get(0), i);
        }
        let best = MatchState::new(false, 0);
        for sq in &or.list{
            let tmp = self.visit_seq(sq, i);
            if(tmp.is_match && (!best.is_match || tmp.len > best.len)){
                best = tmp;
            }
        }
        return best;
    }
    func visit_seq(self, sq: Seq*, i: i32): MatchState{
        let total = 0;
        for(let idx = 0;idx < sq.list.len();idx += 1){
            let item = sq.list.get(idx);
            let it_used = false;
            //prevent greedy match
            if let RegexItem::Op(ch*, kind*) = item{
                if((ch.get() is RegexItem::Dot || ch.get() is RegexItem::Ch) && kind is OpKind::Star && idx < sq.list.len() - 1){
                    let next = sq.list.get(idx + 1);
                    //do non greedy  (ab)*a
                    //b*b => bb
                    let end2 = i + total;
                    while(true){
                        let chr = self.visit_item(ch.get(), end2);
                        if(!chr.is_match) break;
                        let nextr = self.visit_item(next, end2);
                        if(nextr.is_match){
                            let nextr2 = self.visit_item(next, end2 + chr.len);
                            if(nextr2.is_match){
                                //use ch
                                end2 += chr.len;
                                total += chr.len;
                                it_used = true;
                            }else{
                                //ignore ch
                                total = end2;
                                break;
                            }
                        }else{
                            //we must use ch
                            end2 += chr.len;
                            total += chr.len;
                            it_used = true;           
                        }
                        }
                    continue;
                }else if((ch.get() is RegexItem::Dot || ch.get() is RegexItem::Ch) && kind is OpKind::Opt && idx < sq.list.len() - 1){
                    let next = sq.list.get(idx + 1);
                    let chr = self.visit_item(ch.get(), i + total);
                    if(!chr.is_match) continue;
                    let nextr = self.visit_item(next, i + total);
                    //a?a, a?(ab|c) => a,a,ab,aab,ac
                    if(nextr.is_match){
                        let nextr2 = self.visit_item(next, i + total + chr.len);
                            if(nextr2.is_match){
                                //use ch
                                total += chr.len;
                                it_used = true;
                            }else{
                                //ignore ch                          
                                continue;
                            }
                    }else{
                        //use ch
                        total += chr.len;
                        it_used = true;        
                    }
                }
            }
            if(!it_used){
                let res = self.visit_item(item, i + total);
                if(!res.is_match) return MatchState::new(false, 0);
                total += res.len;
            }
        }
        return MatchState::new(true, total);
    }
    func is_dot(it: RegexItem*): bool{
        return it is RegexItem::Dot;
    }
    func is_empty(it: RegexItem*): bool{
        match it{
            RegexItem::Op(RegexNode*, kind*) => return kind is OpKind::Opt || kind is OpKind::Star,
            _=> return false,
        }
    }
    func visit_item(self, it: RegexItem*, i: i32): MatchState{
        if(!self.has(i)){
            if(is_empty(it)) return MatchState::new(true, 0);
            return MatchState::new(false, 0);
        }
        return match it{
            RegexItem::Ch(ch) => MatchState::new(self.s.get(i) == ch, 1),
            RegexItem::Escape(val) => {
                panic("todo escape");
            },
            RegexItem::Group(or*, name*) => {
                let tmp = self.visit_or(or, i);
                if(!tmp.is_match) return MatchState::new(false, 0);
                let cap_str: str = self.s.substr(i, i + tmp.len);
                let cap_opt = self.cap.map.get(&name.str());
                if(cap_opt.is_some()){
                    //capture in loop, extend substring
                    let cap: Capture* = cap_opt.unwrap();
                    cap.arr.add(cap_str);
                    cap.buf = self.s.substr(cap.start, cap.end + tmp.len);
                    cap.end += tmp.len;
                }else{
                    let cap = Capture::new();
                    cap.arr.add(cap_str);
                    cap.buf = cap_str;
                    cap.start = i;
                    cap.end = i + tmp.len;
                    self.cap.map.add(name.str(), cap);
                }
                tmp
            },
            RegexItem::Op(node*, kind*) => {
                let node_st = self.visit_item(node.get(), i);
                let res = MatchState::new(!(kind is OpKind::Plus), 0);
                if(!node_st.is_match) return res;
                
                match kind{
                    OpKind::Opt => {
                        res.len = node_st.len;
                    },
                    OpKind::Star => {
                        res.len = node_st.len;
                        while(true){
                            let next_st = self.visit_item(node.get(), i + node_st.len);
                            if(!next_st.is_match) break;
                            node_st.len += next_st.len;
                            res.len += next_st.len;
                        }
                    },
                    OpKind::Plus => {
                        res.is_match = true;
                        res.len = node_st.len;
                        while(true){
                            let next_st = self.visit_item(node.get(), i + node_st.len);
                            if(!next_st.is_match) break;
                            node_st.len += next_st.len;
                            res.len += next_st.len;
                        }
                    },
                }
                res
            },
            RegexItem::Dot => MatchState::new(true, 1),
            RegexItem::Brac(br*) => {
                let valid = false;
                let ch = self.s.get(i);
                for rng in &br.list{
                    if(ch >= rng.start && ch <= rng.end){
                        valid = true;
                        break;
                    }
                }
                if(br.negated){
                    if(valid) return MatchState::new(false, 0);
                    else return MatchState::new(true, 1);
                }
                MatchState::new(valid, 1)
            }
        };
    }
}


//-----------------------------------------------------
impl Display for RegexNode{
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
            RegexItem::Group(RegexNode*, name*)=>{
                f.print("(");
                f.print("?<");
                f.print(name);
                f.print(">");
                Display::fmt(RegexNode, f);
                f.print(")");
            },
            RegexItem::Brac(RegexNode*)=>{
                Display::fmt(RegexNode, f);
            },
            RegexItem::Op(RegexNode*, kind*)=>{
                Display::fmt(RegexNode.get(), f);
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