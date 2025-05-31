import std/fs
import std/result

import ast/ast
import ast/parser
import ast/lexer

func main(){
    print("find usages()\n");
    print("pwd={:?}\n", current_dir()?);
    find_usage("../src/parser");
}

func find_usage(dir: str){
    for name in File::read_dir(dir).unwrap(){
        if(!name.str().ends_with(".x")) continue;
        let file = format("{}/{}", dir, name);
        print("file={:?}\n", file);
        let p = Parser::from_path(file);
        let unit = p.parse_unit();
        //print("----------------------unit={:?}\n\n", &unit);
    }
}