//Shared helper for the tests that need *another unit's* module (a module's
//members are only visible in the unit that declares them; `tests/fail/
//foreign_mod_*.x` assert the diagnostic). Not a test itself: the gates glob
//tests/<dir>/*.x, and this lives in its own directory. The fail gate compiles
//with `-i tests` (bin/test.sh), so `import helpers/mod_owner` finds it the same
//way `import std/map` finds the std units.
mod m{
    struct S{
        a: i32;
    }
    func helper(): i32{
        return 1;
    }
}
