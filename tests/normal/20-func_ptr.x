static calls = [ID::NONE; 20];
static idx = 0;

enum ID{
    NONE, F, F2, G, G2, MEMBER, MEMBER2
}
func enter(id: ID){
    calls[idx] = id;
    ++idx;
}
func check(ids: [ID; 10]){
    assert(idx == ids.len());
    for(let i = 0;i < idx;++i){
        if(calls[i] is ids[i]){
            continue;
        }
        printf("check failed i=%d\n", i);
        exit(1);
    }
}

struct A{
    a: i64;
}
impl A{
    func member(){
        enter(ID::MEMBER);
        printf("A::member() ");
    }
    func member2(self){
        enter(ID::MEMBER2);
        printf("A::member2(%d) ", self.a);
    }
}
struct B<T>{
    b: T;
}
impl<T> B<T>{
    //static B::member
    //todo not that important to implement this
    func member(){
        enter(ID::MEMBER);
        printf("B::member() ");
    }
    //B<?>::member2
    func member2(self){
        enter(ID::MEMBER2);
        printf("B::member2() ");
    }
}

func f(){
    enter(ID::F);
    printf("f() ");
}

func f2(){
    enter(ID::F2);
    printf("f2() ");
}

func g(a: i32): i32{
    enter(ID::G);
    printf("g(%d) ", a);
    return a * 2;
}

/*func g(a: A): A{
    enter(ID::G2);
    printf("g2(%d) ", a.a);
    return A{a: a.a * 2};
}*/

func take(fp: func() => void){
    printf("take ");
    fp();
}

func take2(fp: func(i32) => i32, val: i32): i32{
    let res = fp(val);
    printf("take2{%d} ", res);
    return res;
}



func main(){
    let fp1 = f;
    fp1();

    let fp2 = fp1;
    fp2();

    fp1 = f2;
    fp1();

    let g2 = g;
    assert(g2(10) == 20);

    take(f);
    take(fp2);
    take(f2);

    assert(take2(g, 50) == 100);

    let m1 = A::member;
    m1();
    let m2 = A::member2;
    let a = A{1234};
    m2(&a);
    
    /*let b2 = B<i32>::member2;
    b2();*/
    
    printf("\n");
    check([ID::F, ID::F, ID::F2, ID::G, ID::F, ID::F, ID::F2, ID::G, ID::MEMBER, ID::MEMBER2]);
    
}

/*

func try_func_ptr(self, expr: Expr*, name: str, err_multiple: bool): Option<RType>{
    let list = List<Signature>::new();
    let mr = MethodResolver::new(self);
    mr.collect_static(name, &list, self);
    //imported func
    let arr = self.get_resolvers();
    for (let i = 0;i < arr.len();++i) {
      let res = *arr.get_ptr(i);
      for(let j = 0;j < res.unit.items.len();++j){
        let item = res.unit.items.get_ptr(j);
        if let Item::Method(m*)=(item){
          if(m.name.eq(name)){
            let desc = Desc{
              kind: RtKind::Method,
              path: m.path.clone(),
              idx: j
            };
            list.add(Signature::new(m, desc, self, self));
          }
        }
      }
    }
    arr.drop();
    if(list.len() > 1 && err_multiple){
      self.err(expr, format("multiple matching functions for '{}'\n{:?}", name, list));
    }
    if(list.len() == 1){
      let sig = list.get_ptr(0);
      let method = sig.m.unwrap();
      if(method.is_generic){
        list.drop();
        return Option<RType>::new();
      }
      let ret = self.visit_type(&method.type).unwrap();
      let ft = FunctionType{return_type: ret, params: List<Type>::new()};
      for prm in &sig.args{
        let prm_rt = self.visit_type(prm);
        ft.params.add(prm_rt.unwrap());
      }
      let id = Node::new(-1, expr.line);
      let rt = RType::new(Type::Function{.id, type: Box::new(ft)});
      rt.method_desc = Option::new(sig.desc.clone());
      list.drop();
      return Option::new(rt);
    }
    list.drop();
    return Option<RType>::new();
  }
*/