import std/libc

//Auto-drop of a boxed payload needs T's drop glue. Type erasure loses T, and
//the language cannot materialize that glue at a generic site (a generic
//function reference, a generic-method reference and a generic lambda are all
//rejected), so the site that knows T must hand it in:
//  - Any::new<T>(v)          : no glue; payload innards need drop2<T>.
//  - Any::new<T>(v, glue)    : auto-drop is total (frees payload innards).
//`glue` is a func(i8*) that drops a T living at that address.
func any_nop(p: i8*){
}

struct Any{
    box: Box<i8>;
    type: String;
    drop_f: func(i8*) => void;
}
   
impl Any{
    func new(): Any{
        return Any{box: Box::new(0i8), type: "".owned(), drop_f: any_nop};
    }
    func new<T>(val: T): Any{
        return Any::new<T>(val, any_nop);
    }
    func new<T>(val: T, drop_f: func(i8*) => void): Any{
        let b = Box<T>::new(val);
        let b2 = ptr::deref!(&b as Box<i8>*);
        std::no_drop(b);
        return Any{box: b2, type: std::print_type<T>().owned(), drop_f: drop_f};
    }

    func get<T>(self): T*{
        return self.box.get() as T*;
    }

    func drop2<T>(*self){
        let val: T = ptr::deref!(self.box.get() as T*);
        Drop::drop(val);
        //manual drop must be total: free the box shell and the type
        //string too (auto-drop covers those but not payload innards;
        //drop2 used to leak both shells - the complement).
        free(self.box.val as i8*);
        Drop::drop(self.type);
        std::no_drop(self);
    }
}

impl Drop for Any{
    func drop(*self){
        //Free the payload innards through the glue captured at construction
        //(any_nop when the constructing site did not know T), then the box
        //shell and the type string. This never panics: auto-drop must be
        //total. Manual drop2 frees a payload whose glue was not supplied.
        let dp = self.drop_f;
        dp(self.box.get() as i8*);
        free(self.box.val as i8*);
        Drop::drop(self.type);
        std::no_drop(self);
    }
}

impl Debug for Any{
    func debug(self, f: Fmt*){
        f.print("Any<");
        f.print(&self.type);
        f.print(">(");
        f.print(">)");
    }
}