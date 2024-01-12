struct AstCopier{
    map: Map<String, Type>*;
}

impl AstCopier{
    func new(map: Map<String, Type>*): AstCopier{
        return AstCopier{map: map};
    }

    func visit(self, m: Method*): Method{
        panic("AstCopier::visit(Method)");
    }
}