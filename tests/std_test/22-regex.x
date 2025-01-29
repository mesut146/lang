import std/regex

func test_match(pat: str, s: str){
    if(!Regex::new(pat).is_match(s)){
        panic("failed {} -> {}\n", pat, s);
    }
}
func test_match_not(pat: str, s: str){
    if(Regex::new(pat).is_match(s)){
        panic("failed {} -> {}\n", pat, s);
    }
}

func test_match(){
    test_match("^abc$", "abc");
    test_match_not("^abc$", "abd");
    
    test_match_not("ab", "abc");

    test_match("b?c", "bc");
    test_match("ab?c", "ac");
    test_match("ab*c", "ac");
    test_match("b*c", "bc");
    test_match("b*c", "bbc");
    test_match("b*c", "bbbc");
    test_match("ab+c", "abc");
    test_match("ab+c", "abbbc");
    test_match_not("ab+c", "ac");
    
    test_match("ab|(cde)", "ab");
    test_match("ab|(cde)", "cde");
    test_match_not("ab|(cd)", "a");
    test_match_not("ab|(cd)", "ax");
    test_match_not("a|(bc)", "ax");
    
    test_match("a|bc", "bc");
    
    test_match("(a|b)x(c|d)y", "axcy");
    test_match("(a|b)x(c|d)y", "axdy");
    test_match("(a|b)x(c|d)y", "bxcy");
    test_match("(a|b)x(c|d)y", "bxdy");
    
    test_match("a.c", "abc");
    test_match("a.c", "axc");
    test_match("ab.*", "abcdef");
    test_match("ab.*", "ab");
    //greedy
    test_match("a.*c", "ac");
    test_match("a.*c", "abc");
    test_match("a.*c", "axxxc");
    test_match("ab*b", "ab");
    test_match("b*b", "bb");
    
    test_match("a(bc)*b", "ab");
    test_match("a(bc)*b", "abcbcb");
    
    test_match("ab?b", "ab");
    test_match("ab?b", "abb");
    
    test_match("[a-z]#[0-9]", "m#5");
    test_match("[a-z0-9]#", "x#");
    test_match("[a-z0-9]#", "6#");
    test_match("[^a-z]#", "3#");
    test_match("[^a-z0-9]#", "=#");
}

func test_captures(){
    let c = Regex::new("a(bc)d(e)?").captures("abcde").unwrap();
    assert(c.get(0).str().eq("bc"));
    assert(c.get(1).str().eq("e"));
    
    c = Regex::new("a(bc)d(e)?").captures("abcd").unwrap();
    assert(c.get(0).str().eq("bc"));
    assert(!c.has("1"));
    
    c = Regex::new("<([a-z][0-9])*<([a-z])+").captures("<b2x7<xyz").unwrap();
    assert(c.get(0).str().eq("b2x7"));
    assert(c.get(0).get(1).eq("x7"));
    assert(c.get(1).str().eq("xyz"));
    
}

func main(){
    test_match();
    test_captures();
}