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
    //test_match("^abc$", "abc");
    //test_match_not("^abc$", "abd");
    
    test_match_not("ab", "abc");

    //test_match("ab?c", "abc");
    //test_match("ab?c", "ac");
    //test_match("ab*c", "ac");
    //test_match("ab*c", "abc");
    //test_match("ab*c", "abbbc");
    
    //test_match("ab|(cde)", "ab");
    //test_match("ab|(cde)", "cde");
    //test_match_not("ab|(cd)", "a");
    //test_match_not("ab|(cd)", "ax");
    //test_match_not("a|(bc)", "ax");
    
    let r2 = Regex::new("a|bx(c|d)y");
    //let r2 = Regex::new("a|b");
    assert(r2.is_match("axcy"));
    assert(r2.is_match("axdy"));
    assert(r2.is_match("bxcy"));
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