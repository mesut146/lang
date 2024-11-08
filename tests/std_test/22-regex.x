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
    /*test_match("^abc$", "abc");
    test_match_not("^abc$", "abd");
    
    test_match_not("ab", "abc");

    test_match("ab?c", "abc");
    test_match("ab?c", "ac");
    test_match("ab*c", "ac");
    test_match("ab*c", "abc");
    test_match("ab*c", "abbbc");
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
    test_match("a.c", "axc");*/
    //test_match("a.*c", "ac");
    test_match("a.*c", "abc");
    test_match("a.*c", "axxxc");
}

func main(){
    test_match();
    //let r = Regex::new("[0-9][a-z]*xy?.+");
    //r.captures("asd"); //Cap
    //r.is_match("asd"); //bool
    //r.find("asd"); // List<String>
    //^start_end$
    //r.replace_all
    //
}