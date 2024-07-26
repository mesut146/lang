struct Block{
    list: List<String>;
}
impl Block{
    func new(): Block{
        return Block{list: List<String>::new()};
    }
}
struct Method{
    body: Option<Block>;
}

func parse_block(): Block{
    let res = Block::new();
    res.list.add(String::new("test"));
    return res;
}
func parse_method(c: bool): Method{
    let body = Option<Block>::new();
    if(c){
        body = Option::new(parse_block());
    }
    return Method{body: body};
}
func parse_unit(){
    let m = parse_method(true);
    m.drop();
}

func main(){
    parse_unit();
}