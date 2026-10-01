import ast/parser
import ast/printer
import std/io
import std/fs

//fmt: parse a file and reprint it canonically via Debug pretty-printing
//(print_cst off). NOTE: comments are dropped (the lexer does not keep
//them) and layout is normalized; output must parse to the same AST.
//usage: fmt <in.x> [out.x] (stdout when out.x is omitted)
func main(argc: i32, args: i8**){
    let cmd = CmdArgs::new(argc, args);
    if(cmd.args.len() < 1 || cmd.args.len() > 2){
        print("usage: fmt <in.x> [out.x]\n");
        exit(1);
    }
    let inp = cmd.args.get(0).clone();
    let parser = Parser::from_path(inp.clone());
    let unit = parser.parse_unit();
    parser.drop();
    let out = Fmt::str(&unit);
    unit.drop();
    if(cmd.args.len() == 2){
        let dst = cmd.args.get(1).clone();
        out.append("\n");
        let res = File::write_string(out.str(), dst.str());
        if(res.is_err()){
            print("cannot write {}\n", &dst);
            out.drop();
            dst.drop();
            inp.drop();
            cmd.drop();
            exit(1);
        }
        res.drop();
        dst.drop();
    }else{
        print("{}\n", &out);
    }
    out.drop();
    inp.drop();
    cmd.drop();
}
