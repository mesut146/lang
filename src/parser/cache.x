import std/hashmap
import std/io
import std/fs
import std/result

import parser/incremental

struct Cache{
    map: HashMap<String, String>;
    file: String;
    inc: Incremental;
    use_cache: bool;
    write: bool;
    //root of the source tree (the -i include path, e.g. src). add_witness()
    //walks exactly this and no higher. Set by new_cache(); when empty the
    //witness is skipped, which only costs build time, never correctness.
    src_root: String;
    //set when the persisted cache failed validation. add_witness() then
    //records current mtimes, which would otherwise make need_compile() see
    //every file as up to date and skip the rebuild the invalidation is
    //supposed to force. So the flag is what actually drives the rebuild.
    invalid: bool;
}

func CACHE_FILE(out_dir: str): String{
    return Path::concat(out_dir, "cache.txt");
}

impl Cache{
    func new(incremental_enabled: bool, use_cache: bool, out_dir: str, src_dir: String): Cache{
        return Cache{
            map: HashMap<String, String>::new(),
            file: CACHE_FILE(out_dir),
            inc: Incremental::new(incremental_enabled, out_dir, src_dir),
            use_cache: use_cache,
            write: true,
            src_root: String::new(),
            invalid: false,
        };
    }

    func read_cache(self){
        if(!self.use_cache) return;
        if(File::exists(self.file.str())){
            let buf = File::read_string(self.file.str())?;
            let lines = buf.str().split("\n");
            for line in &lines{
                if(line.len() == 0){
                    continue;
                }
                let eq = line.indexOf("=");
                let path = line.substr(0, eq);
                let time = line.substr(eq + 1);
                self.map.add(path.str(), time.str());
            }
        }
        //print("read_cache={}\n", self.map);
        //
        //Order matters: validate the persisted state FIRST, then extend
        //the witness. add_witness() records current mtimes, so running it
        //first would overwrite the stale ones and hide exactly the change
        //we are trying to detect.
        if(!self.entries_valid()){
            self.map.clear();
            self.invalid = true;
        }
        //Track every source file, not just this module's files, so a
        //change in a module we depend on invalidates us too. See
        //add_witness() for why that is required rather than merely nice.
        if(!self.src_root.empty()){
            self.add_witness(self.src_root.clone());
        }
        //Persist the witness now, while the recorded mtimes are still the
        //ones that describe the .o files on disk.
        //
        //This has to happen here rather than relying on the normal
        //write-back: when every file is a cache hit, Emitter::compile()
        //returns before it ever calls write_cache(), so on a fully warm
        //build the cache would never be rewritten and the witness would
        //never be recorded at all.
        //
        //Only when the cache is valid. If it was just invalidated, the .o
        //files on disk are stale, and writing the refreshed mtimes now
        //would make the NEXT build consider those stale objects current
        //and skip the very rebuild we need. In that case the compile path
        //repopulates the cache instead.
        if(!self.invalid){
            self.write_cache();
        }
    }

    //Record an entry for every .x file under the source root, whether or
    //not this module ever compiles it. The walk descends only, so it can
    //never climb above the root it is given, and the root is the -i
    //include path (src/), not the filesystem root or the repo root.
    //
    //Each module gets its own cache.txt (build/<mod>_out/cache.txt), so
    //without this a module's cache only ever mentions its own files and
    //is blind to the rest of src/. The compiler has no dependency graph
    //to consult, and that blindness is not mere staleness: a struct's
    //fields decide its size, so adding a field in src/ast changes sizeof
    //for every module that embeds or traverses that type. Reusing an
    //object built against the old layout links two different layouts
    //together, and the result then reads and frees memory through the
    //wrong offsets -- a silent miscompile that surfaces much later as a
    //crash in an unrelated drop path.
    //
    //The cost is that an edit rebuilds the dependent modules rather than
    //just the edited one. Being wrong in that direction only costs build
    //time; being wrong in the other one costs correctness.
    func add_witness(self, dir: String){
        if(!File::is_dir(dir.str())){
            return;
        }
        let res = File::read_dir(dir.str());
        if(res.is_err()){
            return;
        }
        let list = res.unwrap();
        for(let i = 0;i < list.len();++i){
            let name = list.get(i).str();
            //read_dir() returns "." and ".." like readdir does; recursing
            //into them loops forever (src/. -> src/./. -> ...), pinning a
            //core with no output. Skip them before anything else.
            if(name.eq(".") || name.eq("..")){
                name.drop();
                continue;
            }
            let full = format("{}/{}", dir.str(), name);
            if(File::is_dir(full.str())){
                //recursive call takes full by value (a move), so it must
                //not be dropped afterwards
                self.add_witness(full);
                name.drop();
                continue;
            }
            if(!name.ends_with(".x")){
                full.drop();
                name.drop();
                continue;
            }
            if(File::is_file(full.str())){
                let time = File::get_last_write_time(full.str()).str();
                //add() consumes both arguments, so neither is dropped
                self.map.add(full, time);
                continue;
            }
            full.drop();
            name.drop();
        }
    }

    //True when every recorded entry still matches the file on disk.
    //
    //need_compile() only ever asks about the files of the module being
    //built, so on its own it cannot see that a change elsewhere in the
    //source tree invalidates this module's objects too. entries_valid()
    //checks the whole recorded set instead, and a single mismatch drops
    //the entire cache so the module recompiles against current sources.
    //
    //The entries it checks are the module's own files plus the whole-tree
    //witness that add_witness() records, so "elsewhere in the tree" is
    //covered too.
    func entries_valid(self): bool{
        for pair in &self.map{
            let path = pair.a.str();
            //a recorded path that no longer exists (moved/removed
            //worktree, copied-in cache) is stale by definition
            if(!File::is_file(path)){
                return false;
            }
            let cur = File::get_last_write_time(path).str();
            let ok = cur.eq(pair.b.str());
            cur.drop();
            if(!ok){
                return false;
            }
        }
        return true;
    }
    
    func write_cache(self){
        if(!self.use_cache) return;
        if(!self.write) return;
        let str = String::new();
        for pair in &self.map{
            str.append(pair.a.str());
            str.append("=");
            str.append(pair.b.str());
            str.append("\n");
        }
        File::write_string(str.str(), self.file.str())?;
    }
    
    func need_compile(self, file: str, out: str): bool{
        if(!self.use_cache) return true;
        //a file elsewhere in src/ moved, so nothing we built before can be
        //trusted: recompile this module wholesale. Checked before the
        //per-file lookup because add_witness() has already refreshed every
        //entry to its current mtime by this point.
        if(self.invalid) return true;
        if(!File::is_file(out)){
            return true;
        }
        let resolved = File::resolve(file).unwrap();
        file = resolved.str();
        let file_s = file.str();
        let old = self.map.get(&file_s);
        if(old.is_some()){
            let old_time = old.unwrap();
            let cur_time = self.get_time(file);
            let res = !old_time.eq(cur_time.str());
            return res;
        }
        return true;
    }
    
    func update(self, file: str){
        if(!self.use_cache) return;
        let resolved = File::resolve(file)?;
        let time = self.get_time(resolved.str());
        self.map.add(resolved, time);
    }
    
    func get_time(self, file: str): String{
        let resolved = File::resolve(file)?;
        let time = File::get_last_write_time(resolved.str());
        return time.str();
    }
}