import std/fs
import std/result

import ast/ast
import ast/parser
import ast/lexer

import lsp/find_usages

func main(argc: i32, args: i8**){
  let cmd = CmdArgs::new(argc, args);
  if(cmd.is("overlay")){
      cmd.consume();
      overlay(&cmd);
  }
  cmd.end();
  cmd.drop();
}

func overlay(cmd: CmdArgs*){
    let file = cmd.get()?;
    let p = Parser::from_path(file);
    let unit = p.parse_unit();
    for it in &unit.items{
        match it{
            Method(m)=>{
                print_func(m);
            },
            Decl(d)=>{
                match d{
                    Decl::Struct(fields)=>{
                        print("struct {:?}{{\n", d.type);
                        print("}\n");
                    },
                    Decl::TupleStruct(fields)=>{
                        print("struct {:?}{{\n", d.type);
                        print("}\n");
                    },
                    Decl::Enum(vars)=>{
                        print("enum {:?}{{\n", d.type);
                        print("}\n");
                    }
                }
            },
            Impl(i)=>{
                print("impl ");
                if(i.info.trait_name.is_some()){
                    print("{:?} for ", i.info.trait_name.get());
                }
                print("{:?}{{\n", i.info.type);
                for m in &i.methods{
                    print("  ");
                    print_func(m);
                }
                print("}\n");
            },
            Trait(t)=>{},
            Type(name,rhs)=>{},
            Extern(items)=>{},
            Const(val)=>{},
            Glob(gl)=>{},
            Module(m)=>{},
            Use(us)=>{}
        }
    }
}

func print_func(m: Method*){
    print("func {:?}(", m.name);
    let i = 0;
    for prm in &m.params{
        if(i>0) print(", ");
        print("{:?}: {:?}", prm.name, prm.type);
        i+=1;
    }
    print("): {:?};\n", m.type);
}

func fu(){
    print("find usages()\n");
    print("pwd={:?}\n", current_dir()?);
    find_type = Option::new("TargetMachine");
    find_usage("../src/parser");
}